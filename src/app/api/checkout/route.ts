import { NextResponse, type NextRequest } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import {
  GRACE_COOKIE,
  GUEST_COOKIE,
  guestOwner,
  verifyCsrf,
  verifyGuestToken,
} from "@/lib/guest/token";

/**
 * Server-side checkout. The client can influence only WHAT is ordered, never
 * what it costs, who owns it, or how it is paid — all of that is derived inside
 * the SECURITY DEFINER `public.create_order` RPC.
 *
 * Design ref: docs/STAGE3_SUPABASE_SCHEMA.md §17, §24.2, §24.5.
 *
 * CHECKOUT IS DISABLED (decision B2): the order-reference sequence is unseeded
 * until verified references / backend source are available. Set CHECKOUT_ENABLED
 * ="true" only after that gate is cleared.
 */

const MAX_BODY_BYTES = 64 * 1024;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(status: number, body: unknown): NextResponse {
  return NextResponse.json(body, { status });
}

function checkoutEnabled(): boolean {
  return process.env.CHECKOUT_ENABLED === "true";
}

function canonicalOrigin(): string | null {
  const raw = process.env.NEXT_PUBLIC_SITE_URL;
  if (!raw) return null;
  try {
    return new URL(raw).origin;
  } catch {
    return null;
  }
}

/**
 * Trusted, server-derived client IP. On Vercel the platform sets these headers;
 * we never trust an arbitrary client-supplied value (a client cannot choose the
 * leftmost hop behind the platform proxy).
 */
function trustedIp(req: NextRequest): string | null {
  const candidates = [
    req.headers.get("x-real-ip"),
    req.headers.get("x-vercel-forwarded-for"),
    req.headers.get("x-forwarded-for"),
  ];
  for (const raw of candidates) {
    if (raw) {
      const first = raw.split(",")[0]?.trim();
      if (first) return first;
    }
  }
  return null;
}

// Best-effort in-memory per-IP fixed-window limiter (per server instance only).
const WINDOW_MS = 60_000;
const MAX_PER_WINDOW = 10;
const buckets = new Map<string, { count: number; resetAt: number }>();

function rateLimited(key: string): boolean {
  const now = Date.now();
  const bucket = buckets.get(key);
  if (!bucket || now >= bucket.resetAt) {
    buckets.set(key, { count: 1, resetAt: now + WINDOW_MS });
    return false;
  }
  bucket.count += 1;
  return bucket.count > MAX_PER_WINDOW;
}

function originAllowed(req: NextRequest): boolean {
  const site = req.headers.get("sec-fetch-site");
  if (site && site !== "same-origin" && site !== "none") return false;

  const canonical = canonicalOrigin();
  const origin = req.headers.get("origin");
  if (canonical) {
    if (origin) return origin === canonical;
    const referer = req.headers.get("referer");
    return Boolean(referer && (referer === canonical || referer.startsWith(canonical + "/")));
  }
  // Canonical origin unset: require same-origin evidence rather than trusting Origin.
  return site === "same-origin" || site === "none";
}

function rpcResponse(data: unknown, error: { message?: string } | null): NextResponse {
  if (error) {
    const message = error.message ?? "";
    if (message.includes("insufficient_stock")) return json(409, { error: "insufficient_stock" });
    if (message.includes("idempotency_key_reused"))
      return json(409, { error: "idempotency_key_reused" });
    if (message.includes("product_unavailable")) return json(409, { error: "product_unavailable" });
    if (message.includes("invalid_")) return json(400, { error: "invalid_order" });
    return json(400, { error: "order_failed" });
  }
  // The RPC returns only { order_reference, public_token, total, idempotent }.
  return json(200, data);
}

export async function POST(req: NextRequest): Promise<NextResponse> {
  // 1. Feature gate — checkout stays disabled until the sequence gate is cleared.
  if (!checkoutEnabled()) return json(503, { error: "checkout_disabled" });

  // 2. Method is POST only (this handler); Origin / Sec-Fetch-Site defence in depth.
  if (!originAllowed(req)) return json(403, { error: "bad_origin" });

  // 3. Per-IP rate limit (trusted, server-derived IP).
  if (rateLimited(trustedIp(req) ?? "global")) return json(429, { error: "rate_limited" });

  // 4. Size guard, then parse.
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return json(413, { error: "payload_too_large" });

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (!body || typeof body !== "object") return json(400, { error: "invalid_json" });
  const input = body as Record<string, unknown>;

  const idempotencyKey = typeof input.idempotency_key === "string" ? input.idempotency_key : null;
  if (!idempotencyKey || !UUID_RE.test(idempotencyKey)) {
    return json(400, { error: "invalid_idempotency_key" });
  }
  const payload = input.order;
  if (!payload || typeof payload !== "object") return json(400, { error: "invalid_payload" });

  // 5. Identity resolved SERVER-SIDE.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    // Signed-in: the user JWT reaches the RPC; owner = auth.uid() inside the function.
    const { data, error } = await supabase.rpc("create_order", {
      payload,
      p_idempotency_key: idempotencyKey,
    });
    return rpcResponse(data, error);
  }

  // Guest: validate the signed cookie, then a CSRF token derived from the same sid.
  const session = verifyGuestToken(req.cookies.get(GUEST_COOKIE)?.value);
  if (!session) return json(403, { error: "no_guest_session" });

  const csrfField = typeof input.csrf === "string" ? input.csrf : null;
  if (!verifyCsrf(session.sid, csrfField)) return json(403, { error: "bad_csrf" });

  // Previous owner (grace) applies to the idempotency conflict lookup only.
  const grace = verifyGuestToken(req.cookies.get(GRACE_COOKIE)?.value);

  // service_role only — never a client-supplied owner.
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("create_order", {
    payload,
    p_idempotency_key: idempotencyKey,
    p_guest_owner: guestOwner(session.sid),
    p_guest_owner_prev: grace ? guestOwner(grace.sid) : null,
  });
  return rpcResponse(data, error);
}

/** No state-changing GET. */
export function GET(): NextResponse {
  return json(405, { error: "method_not_allowed" });
}
