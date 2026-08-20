// The other half of the referral gate: Caelan clicks the review link from
// beta-signup's email. Deliberately NOT a bare "click here to approve" GET
// action — GET only ever renders a confirm page with a real button; only
// the POST that button submits actually approves anything. This project
// has already been bitten once by a GET-triggered action with real
// consequences (MISTAKES.md, the otp_expired confirmation-link issue: a
// mail security scanner pre-visited the link before Caelan's real click).
// A plain "approve" GET link would reproduce that exact failure mode here,
// silently granting access nobody meant to grant.
//
// verify_jwt is off for this function (set at deploy time, matching how
// this project's other functions set it) — it's opened directly from an
// email client with no way to attach a bearer token. The approval_token
// itself is the real credential: a random uuid, good for exactly one
// approval since status flips to 'approved' the moment it's used.

import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const MAIL_FROM = Deno.env.get('MAIL_FROM');

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function page(body: string, status = 200) {
  return new Response(
    `<!doctype html><html><head><meta charset="utf-8"><title>cafequiet beta</title></head>` +
      `<body style="font-family:sans-serif;max-width:480px;margin:64px auto;padding:0 16px;">${body}</body></html>`,
    { status, headers: { 'Content-Type': 'text/html; charset=utf-8' } },
  );
}

function generateCode(): string {
  // Excludes visually ambiguous characters (0/O, 1/I/L) — a code someone
  // has to type in by hand from an email shouldn't be easy to misread.
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

async function sendCodeEmail(email: string, code: string) {
  if (!RESEND_API_KEY || !MAIL_FROM) {
    console.error('beta-approve: RESEND_API_KEY/MAIL_FROM not configured — code email not sent');
    return;
  }
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: MAIL_FROM,
      to: email,
      subject: "You're in — your cafequiet beta code",
      html: `<p>Here's your access code:</p><p style="font-size:24px;font-weight:bold;letter-spacing:2px;">${code}</p><p>Enter it in the app to get started. It's good for one year.</p>`,
    }),
  });
  if (!res.ok) {
    console.error('beta-approve: Resend code email failed', res.status, await res.text());
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === 'GET') {
    const token = url.searchParams.get('token');
    if (!token) return page('<p>Missing approval link.</p>', 400);

    const { data: row, error } = await supabaseAdmin
      .from('early_access_signups')
      .select('email, status')
      .eq('approval_token', token)
      .maybeSingle();

    if (error || !row) return page("<p>This approval link isn't valid.</p>", 404);
    if (row.status === 'approved') {
      return page(`<p>Already approved — a code was already sent to ${escapeHtml(row.email)}.</p>`);
    }

    return page(`
      <p>Approve beta access for <strong>${escapeHtml(row.email)}</strong>?</p>
      <form method="POST">
        <input type="hidden" name="token" value="${escapeHtml(token)}">
        <button type="submit" style="font-size:16px;padding:8px 16px;">Approve</button>
      </form>
    `);
  }

  if (req.method === 'POST') {
    const form = await req.formData();
    const token = form.get('token')?.toString();
    if (!token) return page('<p>Missing approval link.</p>', 400);

    const { data: row, error } = await supabaseAdmin
      .from('early_access_signups')
      .select('id, email, status')
      .eq('approval_token', token)
      .maybeSingle();

    if (error || !row) return page("<p>This approval link isn't valid.</p>", 404);
    if (row.status === 'approved') {
      return page(`<p>Already approved — a code was already sent to ${escapeHtml(row.email)}.</p>`);
    }

    const code = generateCode();
    const { error: insertError } = await supabaseAdmin
      .from('beta_codes')
      .insert({ code, email: row.email, request_id: row.id });

    // 23505 here means this email already has a code — most likely a
    // double form submit. Treat as already-done rather than failing; don't
    // send a second code email in that case.
    if (insertError && insertError.code !== '23505') {
      console.error('beta-approve: code insert failed', insertError.message);
      return page('<p>Something went wrong generating the code. Try again.</p>', 500);
    }

    const { error: updateError } = await supabaseAdmin
      .from('early_access_signups')
      .update({ status: 'approved', approved_at: new Date().toISOString() })
      .eq('id', row.id)
      .eq('status', 'pending');

    if (updateError) {
      console.error('beta-approve: status update failed', updateError.message);
    }

    if (!insertError) {
      await sendCodeEmail(row.email, code);
    }

    return page(`<p>Approved. A code was emailed to ${escapeHtml(row.email)}.</p>`);
  }

  return page('<p>Method not allowed.</p>', 405);
});
