// Public endpoint for the marketing site's "Request early access" form —
// replaces a direct anon insert into early_access_signups (0011) now that
// a request needs a side effect a client can't safely do itself: emailing
// Caelan an Approve link. The Resend API key stays server-side, same
// reason ANTHROPIC_API_KEY and GOOGLE_PLACES_KEY live only in
// search-assistant/places-search. See build-log.md "Referral-code gate"
// for the full design.

import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const DEVELOPER_EMAIL = Deno.env.get('DEVELOPER_EMAIL');
// e.g. 'cafequiet <noreply@cafequiet.com>' — must be on Resend's verified
// sending domain, or Resend will only deliver back to the account owner.
const MAIL_FROM = Deno.env.get('MAIL_FROM');

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Same bound early_access_signups' own CHECK constraint enforces (0011) —
// checked again here so a bad address gets a clean 400, not an opaque
// constraint-violation 500.
function looksLikeEmail(value: string): boolean {
  return value.length >= 3 && value.length <= 320 && value.indexOf('@') > 0;
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

async function sendApprovalEmail(email: string, approvalToken: string) {
  if (!RESEND_API_KEY || !DEVELOPER_EMAIL || !MAIL_FROM) {
    console.error('beta-signup: RESEND_API_KEY/DEVELOPER_EMAIL/MAIL_FROM not fully configured — approval email not sent');
    return;
  }
  // Deliberately not a "click here to approve" GET link — see
  // beta-approve/index.ts for why (MISTAKES.md, the otp_expired
  // confirmation-link precedent: mail security scanners pre-fetch GET
  // links). This just links to a confirm page; the approval itself only
  // happens on the POST that page's own button submits.
  const reviewUrl = `${SUPABASE_URL}/functions/v1/beta-approve?token=${approvalToken}`;
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: MAIL_FROM,
      to: DEVELOPER_EMAIL,
      subject: 'cafequiet beta request',
      html: `<p>${escapeHtml(email)} asked for beta access.</p><p><a href="${reviewUrl}">Review the request</a></p>`,
    }),
  });
  if (!res.ok) {
    console.error('beta-signup: Resend approval email failed', res.status, await res.text());
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  let body: { email?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ status: 'invalid' }, 400);
  }

  const email = body.email?.trim().toLowerCase();
  if (!email || !looksLikeEmail(email)) {
    return jsonResponse({ status: 'invalid' }, 400);
  }

  // Optimization, not the real guarantee — see the insert's 23505 handling
  // below for the actual (case-insensitive, race-safe) dedupe backstop.
  const { data: existing, error: selectError } = await supabaseAdmin
    .from('early_access_signups')
    .select('id')
    .eq('email', email)
    .maybeSingle();

  if (selectError) {
    console.error('beta-signup: lookup failed', selectError.message);
    return jsonResponse({ status: 'error' }, 500);
  }

  if (existing) {
    // Same response either way (still pending, or already approved) — reuses
    // the marketing site's existing "duplicate" copy rather than inventing a
    // new string not owned by that workspace.
    return jsonResponse({ status: 'duplicate' }, 409);
  }

  const { data: inserted, error: insertError } = await supabaseAdmin
    .from('early_access_signups')
    .insert({ email })
    .select('approval_token')
    .single();

  if (insertError) {
    // 23505 = unique_violation on lower(email) — a race with a concurrent
    // duplicate submission, still a duplicate from the requester's side.
    if (insertError.code === '23505') {
      return jsonResponse({ status: 'duplicate' }, 409);
    }
    console.error('beta-signup: insert failed', insertError.message);
    return jsonResponse({ status: 'error' }, 500);
  }

  await sendApprovalEmail(email, inserted.approval_token as string);

  return jsonResponse({ status: 'submitted' });
});
