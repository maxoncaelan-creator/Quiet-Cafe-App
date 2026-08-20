// Template. build.js substitutes these placeholders from the environment
// and writes the result to dist/config.js — which is generated, not
// committed, mirroring how the Flutter app takes the same two values via
// --dart-define rather than hardcoding them (see
// app/lib/services/supabase_service.dart).
//
// The anon key is safe in the client under RLS. It still isn't committed,
// so that rotating it is a deploy concern rather than a git-history one.
window.CAFEQUIET_CONFIG = {
  supabaseUrl: '__SUPABASE_URL__',
  supabaseAnonKey: '__SUPABASE_ANON_KEY__'
};
