import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// Edge Functions only answer signed-in callers. The app signs in anonymously
/// (no sign-up screen); the session is kept and refreshed by supabase_flutter (PRD_step6).
Future<void> ensureSignedIn(SupabaseClient client) async {
  if (client.auth.currentSession != null) return;
  await client.auth.signInAnonymously();
}
