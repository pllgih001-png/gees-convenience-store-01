import "server-only";

import { cookies } from "next/headers";

import {
  GRACE_COOKIE,
  GRACE_TTL_SECONDS,
  GUEST_COOKIE,
  GUEST_TTL_SECONDS,
  csrfToken,
  guestOwner,
  issueGraceToken,
  issueGuestToken,
  renewGuestToken,
  signGuestToken,
  verifyCsrf,
  verifyGuestToken,
  type GuestPayload,
} from "./token";

/**
 * Server-side guest session boundary. The DB never trusts a browser-supplied
 * guest identity: this module establishes, signs, validates and forwards it.
 *
 * Design ref: docs/STAGE3_SUPABASE_SCHEMA.md §24.1, §24.2, §24.4.
 */

export interface GuestSession {
  sid: string;
  /** Idempotency owner derived from the sid (`g:<sha256(sid)>`). */
  owner: string;
  /** Signed cookie value for the current session. */
  token: string;
  /** Server-derived CSRF token to render into the server-rendered form. */
  csrf: string;
}

const BASE_COOKIE = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/",
} as const;

/** Read + verify the primary guest cookie without rotating it. */
export async function readGuestSession(): Promise<GuestPayload | null> {
  const store = await cookies();
  return verifyGuestToken(store.get(GUEST_COOKIE)?.value);
}

/** Verify a raw cookie value (used on the POST path, where nothing is written yet). */
export function verifyGuestCookie(value: string | null | undefined): GuestPayload | null {
  return verifyGuestToken(value);
}

/** Verify a raw grace-cookie value (previous owner only; short TTL). */
export function verifyGraceCookie(value: string | null | undefined): GuestPayload | null {
  return verifyGuestToken(value);
}

/**
 * Return the current session, creating one if absent/invalid. A valid session is
 * RENEWED (same sid, extended exp) so the owner — and therefore idempotency — is
 * preserved. Must be called from a Route Handler or Server Action (writes cookies).
 */
export async function getOrCreateGuestId(): Promise<GuestSession> {
  const store = await cookies();
  const existing = verifyGuestToken(store.get(GUEST_COOKIE)?.value);

  let payload: GuestPayload;
  let token: string;
  if (existing) {
    payload = renewGuestToken(existing); // same sid, extended exp → owner unchanged
    token = signGuestToken(payload);
  } else {
    const issued = issueGuestToken();
    payload = issued.payload;
    token = issued.token;
  }
  store.set(GUEST_COOKIE, token, { ...BASE_COOKIE, maxAge: GUEST_TTL_SECONDS });

  return { sid: payload.sid, owner: guestOwner(payload.sid), token, csrf: csrfToken(payload.sid) };
}

/**
 * Controlled INVALIDATION: issue a NEW sid and record the previous owner in a
 * short-lived signed grace cookie so a straddling idempotency retry still
 * resolves to the original order. Only for sign-in / logout / suspected abuse.
 */
export async function rotateGuestId(): Promise<GuestSession> {
  const store = await cookies();
  const prev = verifyGuestToken(store.get(GUEST_COOKIE)?.value);

  const { token, payload } = issueGuestToken();
  if (prev) {
    store.set(GRACE_COOKIE, issueGraceToken(prev.sid), {
      ...BASE_COOKIE,
      maxAge: GRACE_TTL_SECONDS,
    });
  }
  store.set(GUEST_COOKIE, token, { ...BASE_COOKIE, maxAge: GUEST_TTL_SECONDS });

  return { sid: payload.sid, owner: guestOwner(payload.sid), token, csrf: csrfToken(payload.sid) };
}

/** Clear the guest identity (owner no longer preserved). */
export async function clearGuestId(): Promise<void> {
  const store = await cookies();
  store.delete(GUEST_COOKIE);
  store.delete(GRACE_COOKIE);
}

export { GRACE_COOKIE, GUEST_COOKIE, csrfToken, guestOwner, verifyCsrf };
export type { GuestPayload };
