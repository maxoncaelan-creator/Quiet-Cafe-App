# cafequiet marketing site

The public marketing site for cafequiet — `cafequiet.com`. Static HTML, no
framework, no dependencies.

Not to be confused with the Flutter web app (`app/`, deployed to
`app.cafequiet.com`). Different thing, different deploy, same repo.

## Why plain HTML and not Flutter web

The app is Flutter, so building this in Flutter would have been the obvious
consistency play. It would also have defeated the point. Flutter web renders
to a canvas: crawlers get almost nothing, and this page's entire job is to
be found by search and quoted by AI assistants (see the marketing
workspace's `04_seo-aeo` stage). A static page also loads faster and needs
no build toolchain to change a word of copy.

## Where the copy comes from

**Every user-visible string on this page is owned by the
`quiet-restaurant-finder-marketing` workspace**, in
`stages/05_finalize/output/final.md`. Take strings from there verbatim.

If a new string is needed, ask that workspace for it rather than writing one
here. The wording carries a reading-level standard, positioning, and hard
constraints on what may be claimed about score accuracy — in particular the
score must always read as an indicator, never a guarantee. None of that
context is visible from inside this folder.

## Layout

```
marketing-site/
  build.js              copies src/ → dist/, injects Supabase config
  src/
    index.html          the page, including FAQ JSON-LD
    styles.css          light/dark, responsive, accessibility-first
    signup.js           early-access form → Supabase REST
    config.template.js  placeholders build.js substitutes
  dist/                 generated, gitignored
```

## Build

```
SUPABASE_URL=... SUPABASE_ANON_KEY=... node build.js
```

Both variables are required and the build fails loudly without them —
a page whose signup form silently does nothing is worse than no page.

The anon key is safe in the client (it's protected by RLS, see below) but
isn't committed, mirroring how the Flutter app takes the same two values via
`--dart-define`.

## Deploy (Cloudflare Pages)

Not set up yet — Caelan's, dashboard-only. The app's own Pages project is a
working reference; this needs its own, pointed at the apex domain rather
than `app.`.

| Setting | Value |
|---|---|
| Build command | `node build.js` |
| Build output directory | `dist` |
| Root directory | `stages/03_build/output/marketing-site` |
| Environment variables | `SUPABASE_URL`, `SUPABASE_ANON_KEY` |
| Custom domain | `cafequiet.com` (and `www`) |

When attaching the domain, check the apex `A`/`CNAME` records are what you
intend — this zone has already served a stale parking page once, on
2026-08-19, from records auto-imported during the nameserver migration.

## Signups

Addresses land in `early_access_signups`
(`supabase/migrations/0011_early_access_signups.sql`). Apply that migration
before the form can work.

RLS gives `anon` **insert only**. There is deliberately no select policy, so
the public key on this page cannot read the list back — read it from the
Supabase dashboard or a service-role connection. Adding a select policy
would expose every signup to anyone who views source.

## Accessibility

Not decoration here. The audience explicitly includes people over 50 and
neurodivergent people, so: 18px base type, high contrast in both themes,
visible focus rings, a skip link, `aria-live` on the form result, and
`prefers-reduced-motion` honoured.

Verified 2026-08-19: renders correctly at 375px with no horizontal
overflow; form validation, the sending state, and error recovery all
click-tested locally.

## Known gaps

- **The referral-code gate doesn't exist yet.** The page says one is
  required. Until it's built, that sentence is a promise the product
  doesn't keep. See the build log's open items.
- **No privacy policy**, and this page collects email addresses.
  `form.privacy` promises the address is only used for early access, with
  nothing behind it. Worth sorting before the form goes live.
- **The signup success path has never run against a real Supabase.** Local
  testing used a fake host, which exercises validation and the failure
  path but not a successful insert, the duplicate-email 409, or the RLS
  policy. Re-test once the migration is applied.
