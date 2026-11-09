import "server-only";

import { createClient } from "@supabase/supabase-js";

/**
 * SERVER-ONLY Supabase client that uses the service-role key.
 *
 * SECURITY
 * - Never import this module from a client component or any code that ships to the browser.
 * - The service-role key is a server secret and is intentionally NOT prefixed with
 *   NEXT_PUBLIC_, so Next.js removes it from client bundles.
 * - This client bypasses RLS. Every call must be preceded by an explicit server-side
 *   authorization check (see docs/IMPLEMENTATION_PLAN.md §10D and §10E).
 */
export function createAdminClient() {
  if (typeof window !== "undefined") {
    throw new Error("createAdminClient() must never run in the browser.");
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.",
    );
  }

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
