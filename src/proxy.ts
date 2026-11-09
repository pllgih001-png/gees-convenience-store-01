import type { NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/session";

/**
 * Next.js 16 Proxy (formerly middleware).
 * Refreshes the Supabase auth session before routes are rendered.
 * Route protection for /Account and /Admin is added in a later stage.
 */
export function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    // Skip Next internals and static assets.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
