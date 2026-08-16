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

## Google and Apple Sign-In

`AuthScreen` (`lib/screens/auth_screen.dart`) has Google and Apple sign-in
buttons wired up in code, but both need real credentials from **your own**
developer accounts before they'll work — this agent can't create either
account for you. Neither is required for the app to run: without them, the
buttons just don't appear (Google) or aren't shown on this platform (Apple
only shows on iOS), and email/password still works.

### Google — free
1. A Google Cloud account (your normal Google account is enough).
2. Go to **console.cloud.google.com** → create or pick a project → **APIs & Services → Credentials** → **Create Credentials → OAuth client ID**.
3. Create two client IDs:
   - **Web application** — no redirect URI needed for this flow. This becomes `GOOGLE_WEB_CLIENT_ID`.
   - **iOS** — needs your app's Bundle ID. Already set: `com.quietrestaurantfinder.quietRestaurantFinder` (from `flutter create .`, run 2026-08-16 — see `ios/Runner.xcodeproj/project.pbxproj` if you ever change it). This becomes `GOOGLE_IOS_CLIENT_ID`.
   - (Add an **Android** client ID too when you're ready to test on Android — needs the app's package name and a SHA-1 signing fingerprint, which only exists once you've built the Android project at least once: `cd android && ./gradlew signingReport`.)
4. In your [Supabase dashboard](https://supabase.com/dashboard/project/aesorixtfasfuvcqrvem/auth/providers) → **Authentication → Providers → Google**, enable it and paste in the **Web** client ID.
5. In `ios/Runner/Info.plist`, add a `CFBundleURLTypes` entry containing your iOS client ID *reversed* (Google's console shows you the exact reversed string to copy).
6. Run with both IDs:
   ```
   flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
   ```

### Apple — skipped for now (2026-08-15)

Caelan decided to hold off entirely rather than test the free-account path
right now. The implementation is done and untouched (`_signInWithApple` in
`auth_screen.dart`) — only the button's visibility is gated, off by
default:

```dart
const _appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED');
```

The button simply doesn't render until you opt in with
`flutter run --dart-define=APPLE_SIGN_IN_ENABLED=true` — no code change
needed to pick this back up later. Whenever that day comes, here's what
testing free first looks like, kept for reference. Two honest caveats
going in, so a failure isn't confusing:
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

### What this agent needs back from you
Nothing secret. Client IDs (Google) aren't secret and are meant to live in
build commands/native config files, not hidden — just run the app with
them as shown above, or tell me the values and I'll wire them into a
`--dart-define` snippet for you. Anything genuinely secret (Apple's
private key, if you ever add the Android/web OAuth flow) goes directly
into the Supabase dashboard, never into chat or this codebase — same
pattern as the Outscraper API key and the Supabase service role key
earlier.

## Verify
```
flutter run
```

As of 2026-08-16, `flutter create .` has been run and the native projects
exist, but `flutter pub get`/`analyze`/`test`/`run` haven't succeeded yet —
blocked on Windows Developer Mode, see "Currently blocked on" above. See
the main [README.md](README.md) for the full, current list of what's
verified vs. not.
