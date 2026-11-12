/**
 * SCRATCH-ONLY Stage 3 guest-session boundary tests (pure Node, no DB).
 *
 * Covers the server-side token/CSRF/renewal/grace guarantees of
 * docs/STAGE3_SUPABASE_SCHEMA.md §24 that are provable without Postgres:
 *   T3  browser cannot forge/substitute the guest identity
 *   T5  renewal/rotation preserves the idempotency owner (server-derived)
 *   G1  HMAC signature detects any tamper
 *   G2  tampered grace cookie is rejected
 *   G3  a grace cookie cannot impersonate the current guest and carries no data
 *   G4  expiry is inside the signed bytes → not replayable/extendable
 *   G5  CSRF token is server-derived from the sid and verified timing-safe
 *   G6  grace cookie is single-purpose (sid/iat/exp only)
 *
 * Run: node --test scripts/test/10_guest_boundary.test.mts
 * The HttpOnly/Secure/SameSite cookie attributes are set in
 * src/lib/guest/session.ts (imports `next/headers`); they are asserted by code
 * inspection + the Next build, not by this runner.
 */
import { test } from "node:test";
import assert from "node:assert/strict";

process.env.GUEST_SESSION_SECRET =
  "test-secret-0123456789abcdefghij0123456789abcdefghij";

import {
  GRACE_COOKIE,
  GRACE_TTL_SECONDS,
  GUEST_COOKIE,
  GUEST_TTL_SECONDS,
  csrfToken,
  guestOwner,
  issueGraceToken,
  issueGuestToken,
  newSid,
  renewGuestToken,
  signGuestToken,
  verifyCsrf,
  verifyGuestToken,
} from "../../src/lib/guest/token.ts";

const T0 = 1_700_000_000;

test("cookie names are the single source of truth", () => {
  assert.equal(GUEST_COOKIE, "gees_guest");
  assert.equal(GRACE_COOKIE, "gees_guest_prev");
});

// ---------------------------------------------------------------------------
// G1 — HMAC signature detects any tamper
// ---------------------------------------------------------------------------
test("G1 a freshly issued, validly signed token verifies", () => {
  const { token, payload } = issueGuestToken(T0);
  assert.deepEqual(verifyGuestToken(token, T0 + 1), payload);
});

test("G1 a single-byte change to the body is rejected", () => {
  const { token } = issueGuestToken(T0);
  const [body, sig] = token.split(".");
  const flipped = body.slice(0, 3) + (body[3] === "A" ? "B" : "A") + body.slice(4);
  assert.equal(verifyGuestToken(`${flipped}.${sig}`, T0 + 1), null);
});

test("G1 a single-byte change to the signature is rejected", () => {
  const { token } = issueGuestToken(T0);
  const [body, sig] = token.split(".");
  const flipped = sig.slice(0, -1) + (sig.endsWith("A") ? "B" : "A");
  assert.equal(verifyGuestToken(`${body}.${flipped}`, T0 + 1), null);
});

test("G1 a token signed with a different secret is rejected", () => {
  const forged = signGuestToken({ sid: newSid(), iat: T0, exp: T0 + 1000 });
  const saved = process.env.GUEST_SESSION_SECRET!;
  process.env.GUEST_SESSION_SECRET = "another-secret-0123456789abcdefghij0123";
  assert.equal(verifyGuestToken(forged, T0 + 1), null);
  process.env.GUEST_SESSION_SECRET = saved;
});

// ---------------------------------------------------------------------------
// T3 — the browser cannot forge or substitute the guest identity
// ---------------------------------------------------------------------------
test("T3 absent / malformed / unshaped tokens are rejected", () => {
  assert.equal(verifyGuestToken(null), null);
  assert.equal(verifyGuestToken(undefined), null);
  assert.equal(verifyGuestToken(""), null);
  assert.equal(verifyGuestToken("garbage"), null);
  assert.equal(verifyGuestToken("no-dot-here"), null);
  assert.equal(verifyGuestToken(".onlysig"), null);
  assert.equal(verifyGuestToken("bodyonly."), null);
  assert.equal(verifyGuestToken("a.b.c"), null);
});

test("T3 a well-signed token with wrong JSON shape is rejected", () => {
  // empty sid: correct signature, but the shape check must still reject it
  const emptySid = signGuestToken({ sid: "", iat: T0, exp: T0 + 10 } as never);
  assert.equal(verifyGuestToken(emptySid, T0 + 1), null);
  // non-numeric exp
  const badExp = signGuestToken({ sid: newSid(), iat: T0, exp: "soon" } as never);
  assert.equal(verifyGuestToken(badExp, T0 + 1), null);
});

// ---------------------------------------------------------------------------
// T5 — renewal/rotation preserves a SERVER-derived owner
// ---------------------------------------------------------------------------
test("T5 renewal keeps the same sid → same idempotency owner", () => {
  const { payload } = issueGuestToken(T0);
  const renewed = renewGuestToken(payload, T0 + 60);
  assert.equal(renewed.sid, payload.sid);
  assert.equal(guestOwner(renewed.sid), guestOwner(payload.sid));
  assert.equal(renewed.exp, T0 + 60 + GUEST_TTL_SECONDS);
});

test("T5 a new session has a different sid → different owner", () => {
  const a = issueGuestToken(T0).payload;
  const b = issueGuestToken(T0).payload;
  assert.notEqual(a.sid, b.sid);
  assert.notEqual(guestOwner(a.sid), guestOwner(b.sid));
});

test("T5 the owner is an opaque hash, never the raw sid", () => {
  const { payload } = issueGuestToken(T0);
  const owner = guestOwner(payload.sid);
  assert.match(owner, /^g:[0-9a-f]{64}$/);
  assert.ok(!owner.includes(payload.sid));
});

// ---------------------------------------------------------------------------
// G2 — grace cookie tamper is rejected
// ---------------------------------------------------------------------------
test("G2 a tampered grace cookie is rejected", () => {
  const grace = issueGraceToken(newSid(), T0);
  const [body, sig] = grace.split(".");
  assert.equal(verifyGuestToken(`${body}.${sig}x`, T0 + 1), null);
  const flipped = body.slice(0, 2) + (body[2] === "A" ? "B" : "A") + body.slice(3);
  assert.equal(verifyGuestToken(`${flipped}.${sig}`, T0 + 1), null);
});

// ---------------------------------------------------------------------------
// G3 / G6 — grace is single-purpose: prior sid only, no impersonation, no data
// ---------------------------------------------------------------------------
test("G3 grace carries the PREVIOUS sid, not the current session's sid", () => {
  const prev = issueGuestToken(T0).payload;
  const current = issueGuestToken(T0).payload; // issued after rotation
  const gv = verifyGuestToken(issueGraceToken(prev.sid, T0), T0 + 1)!;
  assert.equal(gv.sid, prev.sid);
  assert.notEqual(gv.sid, current.sid);
  assert.notEqual(guestOwner(gv.sid), guestOwner(current.sid));
});

test("G6 grace payload exposes only sid/iat/exp (no order/customer data)", () => {
  const gv = verifyGuestToken(issueGraceToken(newSid(), T0), T0 + 1)!;
  assert.deepEqual(Object.keys(gv).sort(), ["exp", "iat", "sid"]);
});

// ---------------------------------------------------------------------------
// G4 — expiry is inside the signed bytes: not extendable, not replayable
// ---------------------------------------------------------------------------
test("G4 extending exp without re-signing invalidates the token", () => {
  const { token } = issueGuestToken(T0);
  const [body, sig] = token.split(".");
  const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  payload.exp = payload.exp + 10_000_000; // attacker tries to extend the life
  const editedBody = Buffer.from(JSON.stringify(payload)).toString("base64url");
  assert.equal(verifyGuestToken(`${editedBody}.${sig}`, T0 + 1), null);
  void sig;
});

test("G4 an expired token is rejected; the instant before expiry still verifies", () => {
  const token = signGuestToken({ sid: newSid(), iat: T0, exp: T0 + 60 });
  assert.ok(verifyGuestToken(token, T0 + 59)); // still valid one second before expiry
  assert.equal(verifyGuestToken(token, T0 + 60), null); // now < exp is false at the boundary
  assert.equal(verifyGuestToken(token, T0 + 61), null);
});

test("G4 a future-dated token (not yet valid) is rejected", () => {
  const token = signGuestToken({ sid: newSid(), iat: T0 + 100, exp: T0 + 200 });
  assert.equal(verifyGuestToken(token, T0 + 50), null);
});

test("G4 grace TTL is shorter than the session TTL", () => {
  assert.ok(GRACE_TTL_SECONDS < GUEST_TTL_SECONDS);
  const gv = verifyGuestToken(issueGraceToken(newSid(), T0), T0 + 1)!;
  assert.equal(gv.exp - gv.iat, GRACE_TTL_SECONDS);
});

// ---------------------------------------------------------------------------
// G5 — CSRF is server-derived from the sid and verified timing-safe
// ---------------------------------------------------------------------------
test("G5 the CSRF token is deterministic, per-session and never the sid", () => {
  const { payload } = issueGuestToken(T0);
  const csrf = csrfToken(payload.sid);
  assert.equal(csrfToken(payload.sid), csrf); // deterministic (no storage)
  assert.notEqual(csrf, payload.sid);
  assert.ok(!csrf.includes(payload.sid));
  const other = issueGuestToken(T0).payload;
  assert.notEqual(csrfToken(other.sid), csrf);
});

test("G5 verifyCsrf accepts the derived token and rejects everything else", () => {
  const { payload } = issueGuestToken(T0);
  const csrf = csrfToken(payload.sid);
  assert.equal(verifyCsrf(payload.sid, csrf), true);
  assert.equal(verifyCsrf(payload.sid, csrf + "x"), false);
  assert.equal(verifyCsrf(payload.sid, null), false);
  assert.equal(verifyCsrf(payload.sid, ""), false);
  const other = issueGuestToken(T0).payload;
  assert.equal(verifyCsrf(payload.sid, csrfToken(other.sid)), false); // cross-session
});

// ---------------------------------------------------------------------------
// Secret hygiene
// ---------------------------------------------------------------------------
test("a missing or too-short GUEST_SESSION_SECRET is refused", () => {
  const saved = process.env.GUEST_SESSION_SECRET;
  process.env.GUEST_SESSION_SECRET = "tooshort";
  assert.throws(() => issueGuestToken(T0), /GUEST_SESSION_SECRET/);
  delete process.env.GUEST_SESSION_SECRET;
  assert.throws(() => csrfToken("abc"), /GUEST_SESSION_SECRET/);
  process.env.GUEST_SESSION_SECRET = saved;
});
