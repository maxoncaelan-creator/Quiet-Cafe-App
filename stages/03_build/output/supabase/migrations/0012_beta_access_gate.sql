-- Closed-beta referral gate, added 2026-08-20 per Caelan's design: a
-- requester fills out the marketing site's existing "Request early access"
-- form (early_access_signups, 0011), Caelan gets one email with an Approve
-- link, approving mints a single-use code and emails it to the requester.
-- The app then hard-blocks entry until a valid code is entered. See
-- build-log.md "Referral-code gate" session for the full design, including
-- why an inbox-reading approval bot was rejected in favor of a real
-- confirm-and-click link.
--
-- 0011 was never actually applied to the live project (confirmed via
-- list_migrations before writing this — it isn't in the applied list),
-- so this migration creates early_access_signups itself rather than
-- assuming it already exists.

create table if not exists early_access_signups (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists early_access_signups_email_key
  on early_access_signups (lower(email));

alter table early_access_signups enable row level security;

-- early_access_signups becomes the beta-request record: it already is one
-- (one row per person asking to get in) — extending it rather than adding
-- a parallel table.
alter table early_access_signups
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'approved')),
  add column if not exists approval_token uuid not null default gen_random_uuid(),
  add column if not exists approved_at timestamptz;

create unique index if not exists early_access_signups_approval_token_key
  on early_access_signups (approval_token);

-- Writes now go through the beta-signup Edge Function (service role), which
-- checks for an existing row before inserting and sends the approval email
-- — a direct anon insert would skip both, so this is no longer the intended
-- path. Dropped rather than left dormant and misleading.
drop policy if exists "anon can request early access" on early_access_signups;

-- One code per approved requester (unique on email), single-use, expires a
-- year after issuance if never redeemed (Caelan, 2026-08-20). No RLS policy
-- grants anon or authenticated any access at all — every read/write goes
-- through redeem_beta_code() below or the beta-approve Edge Function
-- (service role), so this table can't be scraped or forged from the client
-- the way early_access_signups' old anon-insert policy was written to guard
-- against for that table.
create table if not exists beta_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  email text not null unique,
  request_id uuid references early_access_signups(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 year'),
  redeemed_at timestamptz,
  redeemed_device_id text
);

alter table beta_codes enable row level security;

-- Called by the app (anon key — this gate runs before any account exists)
-- to redeem a code and unlock the app on this device. security definer so
-- it can read/update beta_codes despite the table granting no RLS policies
-- at all. The three-way return value is intentional, matching Caelan's
-- "hard block with a message" call: the app needs to tell "wrong code"
-- apart from "expired" apart from "already used by someone else," not
-- collapse them into one generic failure.
--
-- Redeeming the same code again from the *same* device is idempotent
-- (returns 'ok') rather than 'already_redeemed', so reinstalling the app on
-- the same phone doesn't lock its own owner out.
create or replace function redeem_beta_code(p_code text, p_device_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row beta_codes%rowtype;
begin
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    return 'invalid';
  end if;

  select * into v_row from beta_codes where code = upper(trim(p_code));

  if not found then
    return 'invalid';
  end if;

  if v_row.expires_at <= now() then
    return 'expired';
  end if;

  if v_row.redeemed_at is not null then
    if v_row.redeemed_device_id = p_device_id then
      return 'ok';
    end if;
    return 'already_redeemed';
  end if;

  update beta_codes
    set redeemed_at = now(), redeemed_device_id = p_device_id
    where id = v_row.id;

  return 'ok';
end;
$$;

revoke all on function redeem_beta_code(text, text) from public;
grant execute on function redeem_beta_code(text, text) to anon, authenticated;
