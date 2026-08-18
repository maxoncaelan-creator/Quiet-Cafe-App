# UI/UX redesign — decisions and backend implications

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Stage: [[quiet-restaurant-finder/stages/03_build/CONTEXT|03 Build]]
Design work: Figma, [Quiet Restaurant Finder — UI Redesign](https://www.figma.com/design/95t2ExwFowpYEAEUuqllsC)

Written 2026-08-17, after a multi-session Figma design pass, before starting
the Flutter implementation of it. Each item below is tagged with what it
actually needs on the backend — most of this redesign is presentation-layer
only, but a few pieces are real new infrastructure, and two are blocked on
Caelan providing external credentials.

## Ready to build — no backend change needed

**Material 3 visual system.** Color roles, type scale, shape/elevation —
all client-side theming. Flutter's `ColorScheme.fromSeed()` generates the
same kind of tonal palette from one seed color, so implementing this is
"pick the seed color," not "hand-port 28 hex values."

**Dark mode.** A second mode on the same color variables, not a separate
palette — `ColorScheme.fromSeed(brightness: Brightness.dark)` from the same
seed. Toggle lives in Settings → Display; persist the choice locally
(`shared_preferences`, already a transitive dependency via other packages —
confirm before assuming it's already a direct one). No sync-across-devices
requirement was stated, so this is local-only unless told otherwise.

**Noise score display (was quietness score).** Caelan corrected this
mid-session: the UI should show *louder = bigger number, fuller bar*, not
quieter = bigger number. This is a display-only transform —
`quietness_score` stays exactly as-is in the database and drives ranking
exactly as before (quietest first). The UI computes
`noiseScore = 100 - quietnessScore` and uses that for both the number shown
and the gauge fill. **Do not rename or invert the underlying
`quietness_score` column or the pipeline's scoring logic** — only the
Flutter display layer changes. Gauge fill color is keyed off the *true*
quietness value (teal ≥75 quiet, amber 35–75, red ≤35 loud), not off the
displayed noise number, so it doesn't need re-deriving.

**Superseded 2026-08-17: numbers replaced with named categories on a
colored bar.** Caelan's call — the gauge-plus-number wasn't landing with
users. `QuietnessGauge` (semicircle + number) removed entirely, replaced by
`widgets/noise_level_bar.dart` (`NoiseLevelBar`): seven named categories
(Silent, Very Quiet, Quiet, Moderate, Loud, Very Loud, Earsplitting) over
even bands of `quietness_score`, shown as a segmented spectrum bar with the
current category highlighted and the category name as the primary heading
— no raw number shown anywhere in the main display. Same non-negotiable as
above still holds: `quietness_score` itself is untouched, this is a display
layer change only. See build-log.md "numbers replaced with a categorical
noise bar" for the verification.

**Superseded 2026-08-18: "Score breakdown" removed entirely, replaced by
loudness votes.** Per Caelan, the detail screen no longer shows the
per-signal breakdown (Microphone readings / Review mentions / Popular
times, each with a raw 0–100 number) at all — the open question above about
extending the categorical treatment to it is now moot. In its place: a
"How loud is this venue?" heading with three vote buttons (Quiet/Normal/
Loud), feeding the same quietness score a mic reading does. See "Loudness
votes" and "Reading flow moved inline" below.

**Google rating display.** `restaurants.google_rating` already exists in
the schema and is already read into the `Restaurant` model
(`supabase_service.dart`) — it was just never rendered anywhere. Flutter
work only: show it under the restaurant name on List/Favourites rows.
Restaurants with no rating yet show "New listing · no rating yet" instead
of a fabricated number (mirrors the existing cold-start "Not enough data
yet" pattern).

**Favorite star UI.** Sits to the right of the gauge on List/Favourites
rows, and in the Detail screen's app bar. See "Favorites" below for the
backend piece this depends on.

**Search bar with voice input (List screen).** Voice-to-text for filtering
the list — this is a client-side speech-to-text concern
(`speech_to_text` or platform APIs), not a backend one. Distinct from the
noise-reading microphone feature elsewhere in the app; keep the two
visually and functionally separate in implementation, not just in the mockup.

**Navigation drawer.** Five destinations (Search Assistant, List,
Favourites, Login/Signup, Settings) plus Report a problem and a version
number pinned to the bottom. **The "overlay with a scrim, don't lose
context" requirement is Flutter's default behavior** — `Scaffold(drawer: ...)`
already renders as a modal overlay with a scrim over the current screen,
which is exactly what was mocked up. This should not need custom
implementation, just using the standard widget rather than pushing a route.

**Settings — Display, Location (UI only), Permissions (UI only), Log out.**
All client-side:
- Display: the dark-mode toggle above.
- Location: the city field is still UI only — **v1 is hardcoded to Sydney,
  NSW per the PRD**, so it has nothing real to change yet. The GPS
  toggle itself is still not wired to anything. **Partially superseded
  2026-08-18**: the app now does use real device location, just not via
  this Settings toggle or for proximity filtering — see "GPS venue guess"
  below. Wiring the Settings toggle to something (or removing it if the
  venue-guess feature makes it redundant) is still open.
- Permissions: microphone toggle reads/writes the OS mic permission
  (`permission_handler`, already a dependency). Notifications toggle is UI
  only until push infrastructure exists — see "Needs new backend work" below.
- Log out: calls `SupabaseService.signOut()`, which already exists
  (`supabase_service.dart`, added when the account indicator was built).
  No new backend work.

## Needs new backend work (not blocked, just not started)

**Favorites.** No table existed before this session —
`stages/03_build/output/supabase/migrations/0004_favorites.sql`, applied
live 2026-08-17. `favorites (user_id, place_id, created_at)`, RLS-scoped to
`auth.uid() = user_id`, same account gate as mic readings: **favoriting
requires sign-in**, browsing does not. This wasn't explicitly stated by
Caelan but follows directly from the existing mic-reading pattern and from
a favorite only meaning something tied to an account — flagging the
inference here in case that's wrong. Flutter work: a `FavoritesRepository`
mirroring `RestaurantRepository`'s shape, and wiring the star toggle to
insert/delete rows (prompting sign-in on tap if not authenticated, same UX
as "Take a reading here").

**Push notifications.** The Permissions screen's "Notifications" toggle
implies alerts ("your submitted readings," "new quiet spots nearby") that
nothing currently sends. No FCM/APNs setup, no Supabase function to
trigger them. Real scope: device token registration, a notifications table
or a Supabase Edge Function triggered on relevant writes (e.g. a mic
reading's aggregate updating), and the actual push send. Worth scoping
separately rather than folding into general Settings work — it's its own
feature, not a toggle-sized task.

## Needs content, not engineering

**Privacy Policy / Terms of Service / Open Source Licenses.** None of these
documents exist yet. This is legal-content creation, not something to draft
speculative text for — flagging so it doesn't get silently stubbed with
placeholder legal language. The Settings row is ready to link out to
wherever these end up hosted (a `flutter_web_content`/`url_launcher`
outbound link, or in-app static pages — either works, Caelan's call, not
urgent enough to block other work).

**"Report a problem."** Destination undecided. Simplest default: a
`mailto:` link via `url_launcher` to a support address, matching the
"nothing secret, no new backend" bar the rest of this pass tries to hold
to. A proper in-app feedback form (with a Supabase table to receive it)
is a reasonable upgrade later but isn't necessary to ship this.

**Version number.** Trivial once `package_info_plus` (or equivalent) is
added — reads the version straight from `pubspec.yaml` at build time
rather than being hand-typed and going stale.

## Blocked on Caelan — needs his own account/credentials

**Search Assistant (Haiku chat).** Flagged when first designed and still
true: this needs the real Anthropic API, and **the API key cannot live in
the Flutter client** — same reasoning as every other secret in this
project (Outscraper key, Supabase service-role equivalent). The correct
shape is a small backend proxy — a Supabase Edge Function is the natural
fit, matching how `pipeline_service`'s credentials are already scoped
server-side rather than shipped client-side. Needs from Caelan: an
Anthropic API key. Two screen states are mocked: the empty state
(illustration + prompt, before any message) and the populated
conversation — both are pure UI until the Edge Function exists; the chat
input can't actually call anything yet.

**Donate (Stripe).** Needs a real Stripe account, at least one Product/Price
configured, and a secure way to create a Checkout Session or PaymentIntent
— **the Stripe secret key has the same "never in the client" constraint**
as the Anthropic key above, so this is also a small Edge Function, not a
Flutter-only feature. Needs from Caelan: a Stripe account (his own, since
he's the one being donated to) and its API keys. Amount chips in the
mockup ($5/$10/$25/Other) are placeholder values, not confirmed pricing.

## Summary table

| Piece | Status |
|---|---|
| M3 theme, dark mode | Ready — Flutter theming only |
| Noise score display | Done — categorical bar (2026-08-17), `quietness_score` unchanged underneath |
| Google rating | Ready — data already exists, just needs rendering |
| Favorites | Ready — table + RLS applied 2026-08-17, needs Flutter wiring |
| Drawer overlay | Ready — is Flutter's default `Scaffold.drawer` behavior |
| Display/Location(UI)/Permissions(UI)/Logout settings | Ready — client-side |
| Push notifications | Not started — real scope, own feature |
| Legal docs | Blocked on content, not code |
| Report a problem | Needs a 1-line decision (default: mailto) |
| Version number | Ready — needs one package added |
| Search Assistant / Haiku | **Done, live-verified 2026-08-17** — Edge Function deployed, tested via curl and on a real Android emulator. Gated to signed-in accounts + 10k-token/5h rate limit added 2026-08-18. |
| Sign-in/sign-up screens (cal.com-style rework) | **Done, live-verified 2026-08-18** — chooser screens + real Google logo + dedicated email/password screens; not part of the original Figma pass this doc otherwise covers |
| Reading flow moved inline | **Done, live-verified 2026-08-18** — no more separate "Reading at X" screen; capture/submit happens on the detail screen via `MicReadingControl` |
| Loudness votes | **Done, live-verified end to end 2026-08-18** — replaces "Score breakdown"; vote → database row → pipeline → confidence score, all confirmed live |
| GPS venue guess | **Done, partially live-verified 2026-08-18** — permission flow and a found-and-fixed ANR risk confirmed live; the actual guess-resolves-to-a-venue path wasn't, see build-log.md |
| Donate / Stripe | Blocked on Caelan's Stripe account + an Edge Function — explicitly paused until closer to launch |

**Update, 2026-08-17:** Search Assistant moved from "blocked" to shipped —
Caelan added the Anthropic key to Supabase's Function Secrets (dashboard,
never shared in chat), the `search-assistant` Edge Function was deployed
and verified end-to-end (curl, then a real device). Two real bugs surfaced
only by running the app on-device — a premature microphone-permission
prompt and literal markdown asterisks in replies — both fixed and
reverified live. See build-log.md's "first real run" session entry for the
full account, including the Android emulator setup this all depended on.

**Update, 2026-08-18: gated to signed-in accounts, rate-limited.** Two
UI-visible states added on top of the existing empty/populated ones: signed
out shows an explanatory message + Sign in button instead of the composer,
and an account over its 10,000-token/5-hour budget shows "on a break,
available again in X" instead. Both enforced server-side in the Edge
Function, not just here. See `_config/decisions.md` "Account & Search
Assistant access" and build-log.md for the implementation and how it was
verified without spending the token budget on testing.

**Also 2026-08-18: reading flow moved inline, "Score breakdown" replaced by
loudness votes, and a GPS venue guess added.** Three related pieces from
the same session, all per Caelan, none part of the original Figma pass:

- **Reading flow moved inline.** The separate "Reading at X" screen
  (`TakeReadingScreen`) is gone — the whole capture-and-submit interaction
  now happens on the detail screen itself, via a new `MicReadingControl`.
  Tapping the mic button starts a fixed 5-second capture automatically (no
  manual "stop and save" step); the button's own color and pulsing state
  carry the phase instead of navigating anywhere: teal and pulsing when
  idle, solid red with the live dB number in place of the prompt text
  while recording, then grey and non-pulsing with a result message (the
  same success/rate-limit/error text the old screen showed, just inline
  instead of a SnackBar) once done, before resetting to idle after a few
  seconds. Verified live via a scripted rapid-screenshot sequence timed
  around the 5-second auto-stop, since a single before/after screenshot
  wasn't catching the transient states.
- **Loudness votes.** "Score breakdown" removed (see above); the detail
  screen now shows "How loud is this venue?" with three vote buttons
  (Quiet/Normal/Loud), feeding the same quietness score a mic reading
  does — see `_config/decisions.md` "Noise signals" and
  `ranking-spec.md` "Signals" for the scoring side. Verified live, fully
  end to end: voted, confirmed the row in `loudness_votes`, ran the
  pipeline, confirmed the confidence score updated.
- **GPS venue guess.** The Search Assistant screen's empty state (signed-in
  users only) now checks whether the device's location is within 100m of a
  loaded restaurant and, if so, shows "Are you at X?" instead of the normal
  splash — Yes opens that restaurant's detail screen, No sets a 30-minute
  "don't ask again" cooldown. Found and fixed a real crash risk while
  testing live (an unbounded native location call could hang the whole app
  hard enough to trigger an actual Android ANR); the "found a venue and
  showed the prompt" path itself wasn't confirmed live, since the test
  emulator's location backend never produced a real fix in that session —
  see build-log.md for the full account and what's still open.

**Also 2026-08-18: sign-in/sign-up screens redone**, this time from a
cal.com screenshot Caelan gave directly rather than the original Figma
pass — a separate, later design decision from everything else in this
file. `AuthScreen`/`CreateAccountScreen` became pure choosers (a
prominently-styled Google button with the real logo, plus an
"…with email" button), with the actual email/password fields moved to
their own screens (`SignInEmailScreen`, `CreateAccountEmailScreen`,
`CreateAccountPasswordScreen`). Full detail — including the real
keyboard-overflow bug this surfaced and fixed along the way — is in
build-log.md, not duplicated here since it wasn't part of the original
Figma-driven pass this document covers.
