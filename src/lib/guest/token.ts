/**
 * Guest-session token primitives (HMAC-signed, stateless).
 *
 * SECURITY
 * - The HMAC key `GUEST_SESSION_SECRET` is a server-only secret. It is NOT
 *   prefixed with NEXT_PUBLIC_, so Next.js never inlines it into client bundles.
 * - The expiry (`exp`) lives INSIDE the signed bytes, so it cannot be extended
 *   without invalidating the signature.
 * - This module is pure (no `next/headers`, no `server-only`) so it can be unit
 *   tested directly under Node. It must only ever be imported by server code
 *   (see src/lib/guest/session.ts, which marks itself `server-only`).
 *
 * Design ref: docs/STAGE3_SUPABASE_SCHEMA.md §24.1, §24.2, §24.4.
 */
import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

/** Cookie names — single source of truth. */
export const GUEST_COOKIE = "gees_guest";
export const GRACE_COOKIE = "gees_guest_prev";

/** Primary session TTL and the shorter grace (owner-preservation) TTL, seconds. */
export const GUEST_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days
export const GRACE_TTL_SECONDS = 60 * 10; // 10 minutes

export interface GuestPayload {
  sid: string;
  iat: number;
  exp: number;
}

function secret(): string {
  const value = process.env.GUEST_SESSION_SECRET;
  if (!value || value.length < 32) {
    throw new Error("GUEST_SESSION_SECRET is missing or too short (need >= 32 chars).");
  }
  return value;
}

function b64url(buf: Buffer): string {
  return buf.toString("base64url");
}

function hmac(data: string): string {
  return b64url(createHmac("sha256", secret()).update(data).digest());
}

/** Constant-time string comparison; length mismatch is reported without leaking content. */
export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) {
    timingSafeEqual(ab, ab); // keep timing independent of the compared bytes
    return false;
  }
  return timingSafeEqual(ab, bb);
}

/** 128-bit random session id, base64url-encoded. */
export function newSid(): string {
  return b64url(randomBytes(16));
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

/** Serialise + sign an arbitrary guest payload into `"<body>.<sig>"`. */
export function signGuestToken(payload: GuestPayload): string {
  const body = b64url(Buffer.from(JSON.stringify(payload), "utf8"));
  return `${body}.${hmac(body)}`;
}

/**
 * Verify signature (timing-safe) then require `iat <= now < exp`.
 * Returns the payload on success, or null on any tamper/expiry/shape failure.
 */
export function verifyGuestToken(
  token: string | null | undefined,
  now: number = nowSeconds(),
): GuestPayload | null {
  if (!token) return null;
  const dot = token.indexOf(".");
  if (dot <= 0 || dot === token.length - 1) return null;

  const body = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  if (!safeEqual(sig, hmac(body))) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object") return null;

  const p = parsed as Record<string, unknown>;
  if (typeof p.sid !== "string" || p.sid.length === 0) return null;
  if (typeof p.iat !== "number" || typeof p.exp !== "number") return null;
  if (!(p.iat <= now && now < p.exp)) return null;

  return { sid: p.sid, iat: p.iat, exp: p.exp };
}

/** Issue a brand-new session (new sid). */
export function issueGuestToken(now: number = nowSeconds()): {
  token: string;
  payload: GuestPayload;
} {
  const payload: GuestPayload = { sid: newSid(), iat: now, exp: now + GUEST_TTL_SECONDS };
  return { token: signGuestToken(payload), payload };
}

/** Renew: extend `exp` while keeping the SAME sid, so the idempotency owner is unchanged. */
export function renewGuestToken(
  payload: GuestPayload,
  now: number = nowSeconds(),
): GuestPayload {
  return { sid: payload.sid, iat: payload.iat, exp: now + GUEST_TTL_SECONDS };
}

/**
 * Grace token: identical signed format, short TTL, carries only a PREVIOUS sid.
 * Used solely to preserve the idempotency owner across a controlled invalidation.
 */
export function issueGraceToken(prevSid: string, now: number = nowSeconds()): string {
  return signGuestToken({ sid: prevSid, iat: now, exp: now + GRACE_TTL_SECONDS });
}

/** Idempotency owner derived from a sid. Opaque and stable for a given sid. */
export function guestOwner(sid: string): string {
  return "g:" + createHash("sha256").update(sid).digest("hex");
}

/** Server-derived CSRF token, keyed by the (server-only) sid — nothing is stored. */
export function csrfToken(sid: string): string {
  return b64url(createHmac("sha256", secret()).update("csrf:" + sid).digest());
}

/** Validate a submitted CSRF field against the session-derived token (timing-safe). */
export function verifyCsrf(sid: string, submitted: string | null | undefined): boolean {
  if (!submitted) return false;
  return safeEqual(submitted, csrfToken(sid));
}
