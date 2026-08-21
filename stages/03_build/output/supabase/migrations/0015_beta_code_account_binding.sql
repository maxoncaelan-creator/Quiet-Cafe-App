-- Rebinds beta-code redemption to the signed-in account instead of the
-- device that happened to redeem it — added 2026-08-21 after Caelan hit
-- exactly the failure mode this replaces: he redeemed his real code on one
-- browser, then got "That code has already been used" opening the same
-- link on a different browser, because 0012's model tied a code to
-- whichever device redeemed it first, not to him. His intent all along was
-- one code per *person*, portable across whatever device/browser they
-- sign in from — this migration is that correction.
--
-- New flow this supports (built alongside this migration): sign-in is now
-- required before anything else during the closed beta; once signed in,
-- the app checks has_beta_access() for that account, and only asks for a
-- code if it comes back false. Redeeming a code permanently attaches it to
-- that account, not to a device.

-- redeemed_device_id served the old per-device model and has no meaning
-- under the new one — dropped rather than left dormant and misleading.
alter table beta_codes drop column if exists redeemed_device_id;

alter table beta_codes
  add column if not exists redeemed_by uuid references auth.users (id) on delete set null;

-- Backfill for any code already redeemed under the old model: if the
-- redeeming email happens to match a real auth.users account, attach it
-- directly rather than forcing a re-redemption.
update beta_codes bc
set redeemed_by = u.id
from auth.users u
where bc.redeemed_at is not null
  and bc.redeemed_by is null
  and lower(u.email) = lower(bc.email);

-- Anything still unattached after that backfill (redeemed under the old
-- model by someone with no matching auth.users account yet — Caelan's own
-- test code, specifically: redeemed by device before he had a real account
-- in this project) is reset to unredeemed rather than left as a
-- permanently-stuck code nobody can attach to. Safe to do broadly: this
-- gate went live only hours ago, so no real requester has been affected by
-- this window.
update beta_codes
set redeemed_at = null
where redeemed_at is not null and redeemed_by is null;

-- Old device-based signature is fully superseded — drop it explicitly
-- rather than leaving two versions callable.
drop function if exists redeem_beta_code(text, text);

-- Redeems a code for the *calling account* (auth.uid()), not a device.
-- Requires an authenticated caller — the app only ever reaches this screen
-- after sign-in now, but this still fails safely (returns 'invalid') if
-- called anonymously somehow. Re-entering a code already redeemed by this
-- same account is idempotent ('ok') — e.g. a reinstall, or checking again
-- from a second device already signed into the same account, which is
-- exactly the case this migration exists to make work correctly.
create or replace function redeem_beta_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row beta_codes%rowtype;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
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
    if v_row.redeemed_by = v_uid then
      return 'ok';
    end if;
    return 'already_redeemed';
  end if;

  update beta_codes
    set redeemed_at = now(), redeemed_by = v_uid
    where id = v_row.id;

  return 'ok';
end;
$$;

revoke all on function redeem_beta_code(text) from public;
grant execute on function redeem_beta_code(text) to authenticated;

-- Lets the app check, right after sign-in, whether this account already
-- has beta access — without granting any direct read access to
-- beta_codes itself (still no RLS policies on that table at all).
create or replace function has_beta_access()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  return exists(select 1 from beta_codes where redeemed_by = auth.uid());
end;
$$;

revoke all on function has_beta_access() from public;
grant execute on function has_beta_access() to authenticated;

-- `revoke ... from public` above only removes the PUBLIC pseudo-role's
-- grant — it doesn't touch anon/authenticated's own grants, and this
-- project's schema apparently grants execute on new functions to both by
-- default (confirmed via get_advisors after first applying this migration,
-- not assumed). Both functions already refuse an anon caller safely
-- (auth.uid() is null -> 'invalid'/false), but close the grant gap
-- explicitly too now that these are meant to be authenticated-only.
revoke execute on function redeem_beta_code(text) from anon;
revoke execute on function has_beta_access() from anon;
