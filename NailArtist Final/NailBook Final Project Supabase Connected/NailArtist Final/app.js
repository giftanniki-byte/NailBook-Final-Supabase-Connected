/* ============================================================
   NailBook - Supabase browser configuration
   ============================================================
   The publishable key is safe to use in browser code when Supabase RLS
   policies are configured correctly. Never put a service_role/secret key here.
   ============================================================ */

const SUPABASE_URL = 'https://yahcgqwojrfnxaajqoel.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_RnJmhQbImteftN91MZw3hg_ijKRud9p';

if (!window.supabase) {
  throw new Error('Supabase JS was not loaded. Make sure the Supabase CDN script appears before app.js.');
}

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: 'pkce'
    }
  }
);

window.supabaseClient = supabaseClient;
