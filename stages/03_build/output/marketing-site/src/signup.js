// Early-access signup for the cafequiet marketing site.
//
// Posts to the beta-signup Edge Function rather than straight to PostgREST
// (still no supabase-js bundle — a plain fetch is enough either way). This
// changed 2026-08-20 when the referral gate landed: a signup now has to
// trigger a real side effect (emailing Caelan an approve link), and an API
// key for that (Resend) can't live in client-side code the way the old
// direct-insert approach worked for a plain table write. See
// supabase/functions/beta-signup/index.ts and build-log.md
// "Referral-code gate" for the full design.
//
// Security: the anon key is public by design and safe in the client — the
// function itself is what enforces dedupe and rate-shaping now, the same
// role RLS played for the old direct insert.
//
// Every user-visible string here is owned by the quiet-restaurant-finder-
// marketing workspace (stages/05_finalize/output/final.md, "Signup form").
// Take them verbatim; if a new one is needed, ask that workspace for it
// rather than writing it here.

(function () {
  'use strict';

  var STRINGS = {
    submit:     'Request access',
    submitting: 'Sending…',
    success:    "You're on the list. We'll be in touch when a spot opens.",
    invalid:    "That doesn't look like an email address.",
    duplicate:  "You're already on the list.",
    generic:    'Something went wrong. Try again in a moment.'
  };

  var form   = document.getElementById('signup-form');
  var input  = document.getElementById('email');
  var button = document.getElementById('signup-submit');
  var status = document.getElementById('form-status');

  if (!form || !input || !button || !status) return;

  var config = window.CAFEQUIET_CONFIG || {};
  var endpoint = config.supabaseUrl
    ? config.supabaseUrl.replace(/\/+$/, '') + '/functions/v1/beta-signup'
    : null;

  function say(message, kind) {
    status.textContent = message;
    status.className = 'form-status ' + (kind === 'ok' ? 'is-ok' : 'is-err');
  }

  function busy(isBusy) {
    button.disabled = isBusy;
    button.textContent = isBusy ? STRINGS.submitting : STRINGS.submit;
  }

  // Deliberately loose. Strict email regexes reject real addresses, and the
  // database has the final say anyway — this only catches obvious typos
  // before a round trip.
  function looksLikeEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }

  form.addEventListener('submit', function (event) {
    event.preventDefault();

    var email = input.value.trim().toLowerCase();

    if (!looksLikeEmail(email)) {
      say(STRINGS.invalid, 'err');
      input.focus();
      return;
    }

    // A misconfigured deploy must not look like a successful signup.
    if (!endpoint || !config.supabaseAnonKey) {
      say(STRINGS.generic, 'err');
      if (window.console) {
        console.error('cafequiet: Supabase config missing. Did build.js run with SUPABASE_URL and SUPABASE_ANON_KEY set?');
      }
      return;
    }

    busy(true);
    status.textContent = '';

    fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': config.supabaseAnonKey,
        'Authorization': 'Bearer ' + config.supabaseAnonKey
      },
      body: JSON.stringify({ email: email })
    })
      .then(function (response) {
        return response.json().catch(function () { return {}; }).then(function (data) {
          if (response.ok && data.status === 'submitted') {
            form.hidden = true;
            say(STRINGS.success, 'ok');
            return;
          }
          // The function returns this both when the email already requested
          // access and when it was already approved — same user-facing
          // message either way, per the existing copy.
          if (response.status === 409 || data.status === 'duplicate') {
            say(STRINGS.duplicate, 'err');
            return;
          }
          say(STRINGS.generic, 'err');
          if (window.console) console.error('cafequiet signup failed:', response.status, data);
        });
      })
      .catch(function (error) {
        say(STRINGS.generic, 'err');
        if (window.console) console.error('cafequiet signup failed:', error);
      })
      .then(function () {
        if (!form.hidden) busy(false);
      });
  });
})();
