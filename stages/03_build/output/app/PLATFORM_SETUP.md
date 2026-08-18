# Platform setup

**Status as of 2026-08-16:** `flutter create .` has been run — `android/`,
`ios/`, and the other native platform folders exist, generated without
touching any hand-written file under `lib/` (verified). The default
`test/widget_test.dart` template it also generates was removed — it
references a `MyApp` counter widget from Flutter's stock template that
doesn't exist in this app and would fail immediately if left in.

The microphone permission entries below are **already applied** to the
real generated files, not just described here:
- Android: `<uses-permission android:name="android.permission.RECORD_AUDIO" />` added to `android/app/src/main/AndroidManifest.xml`.
- iOS: `NSMicrophoneUsageDescription` added to `ios/Runner/Info.plist`.

Both platforms require a specific, honest purpose string for App Store /
Play Store review — the wording used is below; adjust to match whatever
final in-app copy gets settled on, but keep it specific rather than
generic:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Quiet Restaurant Finder uses your microphone to measure ambient noise level at the restaurant you're at. No audio is recorded or stored.</string>
```

**Location permission, added 2026-08-18** for the GPS venue guess (`services/location_service.dart`) — also already applied to the real generated files:
- Android: `ACCESS_COARSE_LOCATION` and `ACCESS_FINE_LOCATION` added to `android/app/src/main/AndroidManifest.xml`.
- iOS: `NSLocationWhenInUseUsageDescription` added to `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Quiet Restaurant Finder uses your location to guess which restaurant you're at, so you don't have to search for it.</string>
```
Only "when in use" — this feature has no need for background location.
`geolocator` (^13.0.0) is the package. **Known real risk, found live**: an
unbounded native location request can hang the whole app hard enough to
trigger a genuine Android ANR on a poor/absent location fix — `getCurrentPosition()`
must always be called with an explicit `timeLimit` in `LocationSettings`
itself, not just a Dart-side `.timeout()` wrapper (which can't interrupt
work already in flight on the platform side). See build-log.md and
`MISTAKES.md`'s `unbounded-native-async-call` entry.

**Resolved 2026-08-16:** Caelan enabled Windows Developer Mode
(`ms-settings:developers`), which had been blocking `flutter pub get`
("Building with plugins requires symlink support"). After that:
- `flutter pub get` — all dependencies resolved, no errors.
- `flutter analyze` — found 2 real issues on the first pass (an unnecessary null-aware operator in `auth_screen.dart`, a deprecated `anonKey` param in `supabase_service.dart` — supabase_flutter renamed it to `publishableKey`). Both fixed. Now: **0 issues**.
- `flutter test` — **2/2 passed** (`test/restaurant_test.dart`).

Not yet done: `flutter run` on an actual device or emulator — analyze/test
confirm the code is statically correct and the model logic works, not that
the UI renders and behaves correctly on screen. iOS specifically can't be
built or run from Windows at all — that step needs a Mac regardless of
anything else here.

**Update, 2026-08-17: the account-gated flow is now verified end to end
on-device**, not just reasoned about — real signup, real email confirmation
(via the actual `quietrestaurantfinder://login-callback` redirect, not a
fallback), real sign-in, real mic capture on the `Pixel_API_36` emulator,
real submission confirmed in the database, real pipeline aggregation into
the restaurant's score. See build-log.md "real sign-in + mic-reading
verified on-device" for the full account. Also found and fixed a real bug
this way that no static check caught: the List screen's Cuisine filter
overflowed on real (long) Google Places category strings —
`DropdownButtonFormField` needed `isExpanded: true`, which the old short
sample data never exercised.

## Supabase
The app reads the ranked restaurant list from Supabase and submits mic
readings to it when `SUPABASE_URL`/`SUPABASE_ANON_KEY` are provided at run
time — see `lib/services/supabase_service.dart`. Without them, it silently
falls back to the bundled sample data in `assets/data/restaurants.json` and
reading submission is disabled (Take a Reading still runs the mic capture,
just shows "not submitted" instead of sending it).

Use the **anon** key here — the anon role is what Row Level Security in
`supabase/migrations/0001_init.sql` is written for (public read on
`restaurants`, insert-only on `mic_readings`). The pipeline connects
separately, as its own scoped `pipeline_service` role — see
`supabase/migrations/0002_pipeline_role.sql`.

Real values for the live project created 2026-08-15 (`quiet-restaurant-finder`,
ap-southeast-2 / Sydney — migration applied, RLS verified, security advisor
clean):

```
flutter run \
  --dart-define=SUPABASE_URL=https://aesorixtfasfuvcqrvem.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFlc29yaXh0ZmFzZnV2Y3FydmVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3MTYxMjcsImV4cCI6MjEwMjI5MjEyN30.3zOZdQtis-p_iBNQmWeLipv-g7MbnSVK2BoBDbTGp0c
```

The anon key is safe to keep in plain text like this — it's meant for
client-side use and RLS is what actually restricts what it can do, not
secrecy of the key itself.

**Password policy** (Authentication → Providers → Email → Password
Requirements, in the same dashboard): currently set to require an
uppercase letter, a lowercase letter, a number, and a special character —
confirmed intentional with Caelan 2026-08-18, this is dashboard
configuration, not anything in this app's code or migrations. If you ever
change it, the app's own copy (the hint text under every "new password"
field, and the friendly rejection message in
`lib/utils/friendly_auth_error.dart`) won't update itself — keep them in
sync by hand.

## Google and Apple Sign-In

`AuthScreen` (`lib/screens/auth_screen.dart`, sign-in) and
`CreateAccountScreen` (`lib/screens/create_account_screen.dart`, sign-up)
both have Google and Apple sign-in buttons wired up in code — the actual
Google/Apple/Facebook mechanics live in `lib/services/oauth_service.dart`,
shared between the two screens since signing in and signing up via OAuth
are the same Supabase call. Both need real credentials from **your own**
developer accounts before they'll work — this agent can't create either
account for you. Neither is required for the app to run: without them, the
buttons just don't appear (Google) or aren't shown on this platform (Apple
only shows on iOS), and email/password (via "Sign in with email" /
"Sign up with email") still works.

### Google — free

**Status as of 2026-08-18: confirmed working end to end on Android.** Web
and Android OAuth clients both created; verified live on the
`Pixel_API_36` emulator — real Google account picker scoped to the app,
real credential entry (Caelan's own), successful sign-in, session
persisted. iOS client ID not created yet — the button will stay Android/Web
-only until that's done (see step 3).

1. A Google Cloud account (your normal Google account is enough).
2. Go to **console.cloud.google.com** → create or pick a project → **APIs & Services → Credentials** → **Create Credentials → OAuth client ID**.
3. Create two client IDs:
   - **Web application** — no redirect URI needed for this flow. This becomes `GOOGLE_WEB_CLIENT_ID`.
   - **iOS** — needs your app's Bundle ID. Already set: `com.quietrestaurantfinder.quietRestaurantFinder` (from `flutter create .`, run 2026-08-16 — see `ios/Runner.xcodeproj/project.pbxproj` if you ever change it). This becomes `GOOGLE_IOS_CLIENT_ID`.
   - **Android** — needs the app's package name and a SHA-1 signing fingerprint. Both already known, generated 2026-08-17 (`cd android && ./gradlew signingReport`, `JAVA_HOME` needed pointing at Android Studio's bundled JBR — not on PATH by default in this environment):
     - Package name: `com.quietrestaurantfinder.quiet_restaurant_finder`
     - SHA-1 (debug keystore): `E3:68:E9:E5:08:76:1D:D6:E7:30:30:4F:68:05:75:05:7E:BA:79:8B`
     - This is the **debug** keystore's fingerprint — fine for testing on the emulator/a device via `flutter run`, but a real release build (Play Store) signs with a different key and will need its own Android client ID with that release fingerprint, later.
4. In your [Supabase dashboard](https://supabase.com/dashboard/project/aesorixtfasfuvcqrvem/auth/providers) → **Authentication → Providers → Google**, enable it and paste in the **Web** client ID. **Done 2026-08-18** — Google shows Enabled in the dashboard.
5. In `ios/Runner/Info.plist`, add a `CFBundleURLTypes` entry containing your iOS client ID *reversed* (Google's console shows you the exact reversed string to copy). Not yet done — iOS client ID not created yet.
6. Run with both IDs:
   ```
   flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=335462034836-93k0vrqkqha1kmaf87j5ne05t1vaafvc.apps.googleusercontent.com --dart-define=GOOGLE_IOS_CLIENT_ID=...
   ```

### Apple — activated 2026-08-16

Originally deferred (2026-08-15), then activated alongside Google and
Facebook. The implementation is unchanged (`_signInWithApple` in
`auth_screen.dart`); only the visibility default flipped:

```dart
const _appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED', defaultValue: true);
```

The button now shows by default on iOS builds (still never on web/Android —
that gate is unrelated and unchanged: `!kIsWeb && Platform.isIOS`). Turn it
back off with `flutter run --dart-define=APPLE_SIGN_IN_ENABLED=false` if you
want to hide it again without a code change. Two honest caveats stand
regardless of the flag, unaffected by activating it:
- Whether "Sign in with Apple" actually works under a free **Personal Team** in Xcode is genuinely inconsistent across sources — some say the capability attaches fine for local device testing, others tie it to a paid account. This needs an actual Mac + Xcode to answer, which isn't available in the environment this was built in.
- Regardless of the answer, **shipping to the App Store requires the paid $99/year Developer Program membership no matter what** — that's a separate, unconditional requirement, not specific to Sign in with Apple. So this free path only tells you whether the button *works on your own phone*, not whether you can skip paying eventually.

**Steps to test free (whenever you're ready):**
1. Open `ios/Runner.xcworkspace` in Xcode (`flutter create .` has already been run, so this exists).
2. Xcode → Settings → Accounts → sign in with your normal Apple ID (no payment). Xcode creates a **Personal Team** automatically.
3. Select the Runner target → Signing & Capabilities → set Team to your Personal Team.
4. Click **+ Capability** → add **Sign in with Apple**.
   - If Xcode lets you add it without complaint: proceed to step 5.
   - If Xcode errors or greys it out for your Personal Team: that's your answer — free doesn't cover it, skip to the paid steps below whenever you're ready.
5. Connect a real iOS device (Sign in with Apple typically needs a real device, not the simulator, since it goes through Face ID/Touch ID/passcode) and run with the flag on: `flutter run --dart-define=APPLE_SIGN_IN_ENABLED=true`.
6. Sign out of anything already signed in, tap **Take a reading here**, then the Apple button, and see whether the native Apple sign-in sheet appears and completes.
7. **You still need to register something in Supabase for the token exchange to succeed** — in the [Supabase dashboard](https://supabase.com/dashboard/project/aesorixtfasfuvcqrvem/auth/providers) → Authentication → Providers → Apple, enable it and add your app's Bundle ID as a Client ID (this part doesn't require a paid account either, since it's just registering an identifier string, not creating one through Apple's paid-gated App ID system — though this too is worth confirming as you go, since Apple's dashboard is the ultimate authority here, not this doc).

**Once you decide to pay** (App Store submission, or the free path didn't work and you want it anyway):
1. Enroll at **developer.apple.com/programs/enroll**. $99 USD/year.
2. In the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list) → **Identifiers**, create a proper **App ID** matching your Bundle ID, with **Sign in with Apple** enabled — this is the fully-supported, unambiguous path Apple's own docs describe.
3. Re-confirm the Supabase provider registration from step 7 above now points at this real App ID.
4. No dart-define needed for Apple either way — the identity token already carries the right audience once the identifier is registered with Supabase.

### Facebook — free, added 2026-08-16

Unlike Google/Apple, Facebook sign-in here goes through Supabase's
redirect-based OAuth (`signInWithOAuth`), not a native SDK, so there's no
Flutter-side client ID to pass via `--dart-define`. Everything provider-side
is configured on the Supabase dashboard.

1. Go to **developers.facebook.com** → create an app (type: **Consumer**, or
   whichever Meta's current flow labels as the one that supports Facebook
   Login).
2. Add the **Facebook Login** product.
3. Under **Facebook Login → Settings**, add this to **Valid OAuth Redirect
   URIs**:
   ```
   https://aesorixtfasfuvcqrvem.supabase.co/auth/v1/callback
   ```
   (This is Supabase's own callback, not the app's — Supabase completes the
   OAuth dance with Facebook first, then redirects into the app separately;
   see "Deep link redirect" below.)
4. Copy the **App ID** and **App Secret** from the app's Basic Settings.
5. In the [Supabase dashboard](https://supabase.com/dashboard/project/aesorixtfasfuvcqrvem/auth/providers) → **Authentication → Providers → Facebook**, enable it and paste both in.
6. Run with the flag on:
   ```
   flutter run --dart-define=FACEBOOK_SIGN_IN_ENABLED=true
   ```

Facebook's own review process only matters once you're requesting
permissions beyond basic login (email, public profile) or going live for
the general public — worth reading Meta's current App Review requirements
before shipping, but not a blocker for testing with your own account.

### Deep link redirect — added 2026-08-16

Facebook sign-in and email confirmation links both need the app to receive
a redirect after the user finishes something in a browser. Both now point
at:
```
quietrestaurantfinder://login-callback
```

Already done, not something you need to set up again:
- **Native config**, already in the generated projects: an `<intent-filter>` for this scheme/host in `android/app/src/main/AndroidManifest.xml`, and a `CFBundleURLTypes` entry in `ios/Runner/Info.plist`.
- **App code**: `auth_screen.dart` passes this as `redirectTo` for Facebook sign-in and `emailRedirectTo` for sign-up confirmation (both skipped on web, which redirects to Supabase's own origin instead).

**Still needed from you:** register the same URL in Supabase's dashboard →
[Authentication → URL Configuration](https://supabase.com/dashboard/project/aesorixtfasfuvcqrvem/auth/url-configuration)
→ **Redirect URLs**, add:
```
quietrestaurantfinder://login-callback
```
Without this, Supabase will refuse the redirect and fall back to its
default hosted page — the exact `otp_expired`-page symptom noted in the
build log, just for a different reason (unregistered redirect vs. a
re-clicked link).

**Not yet verified live.** This relies on `supabase_flutter`'s built-in
deep-link handling (registered automatically once `Supabase.initialize()`
runs, given the native config above) — that's documented, stable package
behavior, not something this environment can exercise end-to-end without a
real installed build on a device or emulator. If Facebook sign-in or a
confirmation link doesn't route back into the app when you test it, start
by checking the Supabase redirect URL registration above before assuming
the code is wrong.

### Universal Links / App Links — domain confirmed, still blocked on two other things (2026-08-17)

The domain is **`cafequiet.com`** — confirmed purchased by Caelan
2026-08-17. Checked directly (not assumed): it currently resolves to Crazy
Domains' (the registrar's) infrastructure, not any real hosting yet — a
plain `curl`/fetch gets a certificate mismatch against
`*.crazydomains.com`. Nothing is hosted at `cafequiet.com` yet, which
matters below since the AASA file has to live on real hosting.

Caelan asked to use it to move sign-in redirects off `localhost`/a bare
custom scheme and onto real HTTPS-verified links. Current redirect
(`quietrestaurantfinder://login-callback`) keeps working either way — this
is an upgrade, not a fix for something broken.

**Immediate, unblocked fix**: Supabase's Auth **Site URL** is still
`http://localhost:3000` — the fallback used whenever a request doesn't
specify a redirect (only the web/`flutter run -d edge` testing path today,
but a real trap for any future flow, like password reset, that forgets to
pass one explicitly). This should become `https://cafequiet.com` now — no
other blockers apply to just this field. Still a dashboard-only change,
same as the redirect URL registration earlier — noted below.

**Why it's worth doing**: a custom URL scheme (`quietrestaurantfinder://`)
can technically be registered by more than one app on a device — nothing
stops another app claiming the same scheme. Universal Links (iOS) / App
Links (Android) are HTTPS URLs cryptographically verified against a domain
only this app controls, which a scheme can't guarantee.

**Blocked on more than just the domain** — checked Supabase's current docs
directly (2026-08-17, not assumed) rather than a stale mental model:

**iOS (Universal Links) — well-documented by Supabase**:
1. Add **Associated Domains** capability in Xcode: `applinks:cafequiet.com`.
2. Host `https://cafequiet.com/.well-known/apple-app-site-association` —
   must be JSON, HTTPS, no redirects, `Content-Type: application/json`, no
   file extension. **Supabase explicitly does not host this file — it has
   to live on your own infrastructure.** The marketing site is the natural
   place for it once `cafequiet.com` has real hosting behind it (it
   currently doesn't — see above).
   ```json
   {"applinks":{"apps":[],"details":[{"appID":"TEAM_ID.BUNDLE_ID","paths":["*"]}]}}
   ```
   `BUNDLE_ID` is already known: `com.quietrestaurantfinder.quietRestaurantFinder`.
   `TEAM_ID` is not — it only exists once you've enrolled in the **paid**
   Apple Developer Program (see "Apple" above; still not done). So this is
   blocked on real hosting for the domain plus that enrollment, not just
   owning the domain name.
3. Once both exist, add `https://cafequiet.com/...` as an Additional
   Redirect URL in Supabase, alongside the working custom scheme.

**Android (App Links) — Supabase's Flutter docs don't actually cover this.**
Checked directly rather than assumed: Supabase's current native-deep-linking
guide only documents the basic (unverified) custom-scheme intent-filter for
Android/Flutter — no `assetlinks.json`/`autoVerify` walkthrough. Real Android
App Link verification is a standard Android platform feature, independent of
Supabase, and needs:
- `android:autoVerify="true"` on an intent-filter with an `https` `<data>`
  entry (in addition to, not instead of, the existing custom-scheme filter).
- Hosting `https://cafequiet.com/.well-known/assetlinks.json` containing
  the package name (already known: `com.quietrestaurantfinder.quiet_restaurant_finder`)
  and the **SHA-256 fingerprint of the app's release signing certificate** —
  this doesn't exist yet either; no release keystore has been generated in
  this project so far. See
  [developer.android.com/training/app-links](https://developer.android.com/training/app-links)
  for the exact format once that exists.

**Net effect**: this needs real hosting on `cafequiet.com` (not just owning
it), the paid Apple Developer Program enrollment, and an Android release
signing key — none of which exist yet. Nothing to build now without redoing
it once those show up. Revisit once the domain has somewhere real to point;
the working `quietrestaurantfinder://login-callback` scheme isn't broken
and doesn't need replacing before then.

### What this agent needs back from you
Mostly nothing secret. Client IDs (Google) aren't secret and are meant to
live in build commands/native config files, not hidden — just run the app
with them as shown above, or tell me the values and I'll wire them into a
`--dart-define` snippet for you. Anything genuinely secret (Apple's private
key if you ever add the Android/web OAuth flow; **Facebook's App Secret**)
goes directly into the Supabase dashboard, never into chat or this
codebase — same pattern as the Outscraper API key and the Supabase service
role key earlier.

## Web

Added 2026-08-18 (yet another continuation). The app builds and runs for
web (`flutter run -d chrome` / `flutter build web --release`), targeting
`app.cafequiet.com` as a subdomain — the root `cafequiet.com` stays
reserved for the separate marketing site.

**Routing.** The app moved from a plain `MaterialApp` (no router, one
`home:` screen) to `go_router` (`lib/router.dart`), so every screen has a
real, bookmarkable URL — e.g. `/list`, `/restaurant/:placeId`,
`/settings/permissions`. `/restaurant/:placeId` fetches the restaurant by
id (`SupabaseService.fetchRestaurantByPlaceId`) when opened directly
(a URL paste or browser refresh, with no in-memory `Restaurant` object
available) rather than only working when navigated to in-app.

**Persistent nav shell.** `lib/widgets/app_shell.dart` wraps *every*
route via a root `ShellRoute` — above `kWideLayoutBreakpoint` (840,
`lib/utils/breakpoints.dart`) it shows a `NavigationRail`
(`lib/widgets/app_nav_rail.dart`) beside whatever screen is active,
including auth/detail/settings sub-screens, not just the 5 top-level
destinations. Below that width, each screen keeps its own `Drawer`
exactly as before — mobile/native visuals are unchanged.
`lib/widgets/app_nav_destinations.dart` is the single source of truth
for the 5 destinations, shared by the drawer and the rail. Non-drawer
screens get a `MaxWidthContent` wrap (`lib/widgets/max_width_content.dart`,
640px) or ride `CenteredScrollForm`'s 480px max-width (auth screens) so
nothing stretches edge-to-edge on wide viewports.

**What's gated off web, and why**:
- **Mic-based decibel readings** — `noise_meter`/`audio_streamer` don't
  work on web (confirmed by testing, see `mic_service.dart`'s comments).
  `restaurant_detail_screen.dart` swaps the "Take a reading here" button
  for a "Take a reading in the app" prompt on web
  (`kIsWeb`, `lib/widgets/get_app_prompt.dart`). The Permissions screen's
  Microphone toggle is hidden (not disabled) on web for the same reason.
- **Voice search** (`speech_to_text`, `widgets/voice_search_bar.dart`) is
  **not** gated — it has its own real web implementation via the Web
  Speech API, a separate feature from mic decibel metering.

**"Get the app" banner** (`lib/widgets/download_app_banner.dart`) shows
once, globally, only when `kIsWeb` and `defaultTargetPlatform` is iOS or
Android (Flutter web derives this from the browser's own UA — no extra
package). Store links (`lib/utils/store_links.dart`) are **placeholders**
— the app isn't published to either store yet. Replace them once it is;
tracked as an open item in the workspace's `build-log.md`, not something
to chase down speculatively.

**Cloudflare Pages deployment** — `.github/workflows/deploy-web.yml`
(this repo's first CI pipeline) builds and deploys on every push to
`main`. None of the following is done — dashboard/account access wasn't
available in the session that added this:
1. Cloudflare → API Tokens → create one scoped to `Pages: Edit`.
2. Note the Cloudflare Account ID (Workers & Pages → Overview).
3. GitHub repo → Settings → Secrets → Actions → add `CLOUDFLARE_API_TOKEN`,
   `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the last
   two because CI has no local `--dart-define`s — without them the
   deployed build silently falls back to sample data with submission
   disabled, an easy failure to miss).
4. Push to `main` (via the usual branch+PR flow) — first run auto-creates
   the `quiet-restaurant-finder` Pages project.
5. Cloudflare → that Pages project → Custom domains → add `app.cafequiet.com`.
6. Supabase → Authentication → URL Configuration → add
   `https://app.cafequiet.com` to Redirect URLs.

**Open conflict, not resolved here**: the "Universal Links / App Links"
section above says Supabase's Auth **Site URL** should become
`https://cafequiet.com` (the root domain, for iOS/Android link
verification once that's built). This Web section's redirect needs
`https://app.cafequiet.com` (the subdomain the web app actually lives
at). Site URL is a single value — these two asks need reconciling once
the marketing site's own hosting is real, not picked silently here.
`web/_redirects` (`/* /index.html 200`) is already in place for
Cloudflare Pages' SPA fallback, and `usePathUrlStrategy()` is called in
`main.dart` so URLs are plain paths (`/restaurant/abc`), not
hash-prefixed (`/#/restaurant/abc`) — both needed for direct-URL loads
and refreshes to actually work once deployed, not just in-app navigation.

## Verify
```
flutter run
```

As of 2026-08-16, `flutter create .` has been run and the native projects
exist, but `flutter pub get`/`analyze`/`test`/`run` haven't succeeded yet —
blocked on Windows Developer Mode, see "Currently blocked on" above. See
the main [README.md](README.md) for the full, current list of what's
verified vs. not.
