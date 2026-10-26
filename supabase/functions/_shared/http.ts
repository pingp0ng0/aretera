import { createClient } from "npm:@supabase/supabase-js@2.118.0";

// Shared helpers for Bivi Edge Functions (PRD_step6).

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

/**
 * The caller must be signed in (the app signs in anonymously). Checked here rather than with
 * the platform's verify_jwt flag, which doesn't accept tokens from the new signing keys.
 * Returns the user id, or null when the token is missing or invalid.
 */
export async function requireUser(req: Request): Promise<string | null> {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY") ?? firstPublishableKey();
  if (!url || !key) return null;
  const supabase = createClient(url, key, { auth: { persistSession: false } });
  const { data, error } = await supabase.auth.getUser(token);
  return error || !data.user ? null : data.user.id;
}

function firstPublishableKey(): string | undefined {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    return Object.values(keys)[0] as string | undefined;
  } catch {
    return undefined;
  }
}
