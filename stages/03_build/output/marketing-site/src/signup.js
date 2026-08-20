// Early-access signup for the cafequiet marketing site.
//
// Posts straight to Supabase's REST endpoint rather than pulling in the
// supabase-js bundle — one insert into one table doesn't justify the
// dependency on a page whose whole point is loading fast for search.
//
// Security: the anon key is public by design and safe in the client. What
// actually protects the signup list is RLS —
// supabase/migrations/0011_early_access_signups.sql grants anon INSERT and
// nothing else, so this key cannot read back a single address. Do not add a
// select policy to that table without rethinking this.
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
    ? config.supabaseUrl.replace(/\/+$/, '') + '/rest/v1/early_access_signups'
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
        'Authorization': 'Bearer ' + config.supabaseAnonKey,
        'Prefer': 'return=minimal'
      },
      body: JSON.stringify({ email: email })
    })
      .then(function (response) {
        if (response.ok) {
          form.hidden = true;
          say(STRINGS.success, 'ok');
          return;
        }
        // 23505 = unique_violation. The unique index on lower(email) is what
        // makes "already on the list" distinguishable from a real failure.
        if (response.status === 409) {
          say(STRINGS.duplicate, 'err');
          return;
        }
        return response.text().then(function (body) {
          if (body && body.indexOf('23505') !== -1) {
            say(STRINGS.duplicate, 'err');
          } else {
            say(STRINGS.generic, 'err');
            if (window.console) console.error('cafequiet signup failed:', response.status, body);
          }
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
