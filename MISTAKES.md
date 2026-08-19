# Mistakes - quiet-restaurant-finder

Record one the moment it is apparent, not at the end of the project - the small
repeated ones are exactly what a retrospective loses, and the count is the
signal. What counts as a mistake, and what does not, is in
`_system/mistakes.md`.

```
bin/icm mistake quiet-restaurant-finder --class <slug> --stage <NN_stage> --caught self \
  --what "what happened, specifically" \
  --standard "the rule this fell short of" \
  --fix "what was done about it"
```

## keyboard-overflow-unhandled

Built UI without accounting for the keyboard shrinking the viewport, causing a real layout overflow.

### 2026-08-18 | 03_build | caught: user
Auth screens (auth_screen.dart, create_account_screen.dart, and others) were built with a fixed Column(mainAxisAlignment: center) and no scroll fallback. Caelan hit a real RenderFlex overflow (109px) when the keyboard opened on Create account, caught via a screenshot of the yellow/black overflow banner.
**Standard:** Forms with text fields need to handle a keyboard-shrunk viewport (a scrollable container), not assume content always fits the available height.
**Fix:** Wrapped every auth screen's form in a shared CenteredScrollForm widget (LayoutBuilder + SingleChildScrollView + ConstrainedBox), then verified live by forcing the emulator's soft keyboard on and confirming no overflow.

## incomplete-verification-build-flags

Reported a verification as passing without using the full documented run configuration, hiding a config gap as a false bug report.

### 2026-08-18 | 03_build | caught: user
Verified the auth-flow restructuring live on the emulator without passing --dart-define=GOOGLE_WEB_CLIENT_ID. The Google/Apple sign-in buttons correctly hid themselves per existing design (missing config = hide, not error), but I reported the check as 'Verified live on the emulator' without noticing they were absent from my own screenshots. Caelan reported it as a removed feature before it was traced back to the incomplete test config.
**Standard:** A 'verified live' claim should use the full documented run configuration (PLATFORM_SETUP.md's dart-define flags), and screenshots taken as evidence should be checked for what's missing, not just what's present.
**Fix:** Confirmed via git diff that no OAuth code had actually changed, then rebuilt with the complete flag set and reverified; used the full flag set in every subsequent rebuild this session.

## raw-backend-error-shown-to-user

Displayed a raw backend error message to the user instead of a written one, causing real confusion about what was actually wrong.

### 2026-08-18 | 03_build | caught: user
Password-related AuthException messages, including Supabase's verbose policy rejection ('Password should contain at least one character of each: abcdefghijklm...ABCDEFG...0123456789...!@#$%^&...'), were shown to users verbatim instead of translated into plain language. This directly caused Caelan to misdiagnose the underlying password policy itself as wrong ('it is obviously wrong'), which he then corrected himself ('I made a bit of an error, but it was caused by the wording of the red words').
**Standard:** User-facing error text should be written for users, not passed through raw from a backend API — a general UX baseline, not something project-specific that needed to be told to me.
**Fix:** Added utils/friendly_auth_error.dart to detect this specific rejection and rewrite it as one plain sentence, wired into every screen that can hit it. Left the actual policy untouched in Supabase's settings since it was correct all along — only the display was wrong.

## unscoped-filesystem-search

Ran a search across the whole filesystem instead of scoping it, hitting the tool's timeout.

### 2026-08-18 | - | caught: self
While checking whether the GitHub CLI was installed, ran find / -iname "gh.exe" across the entire filesystem root instead of scoping to likely install locations. The command hit the 2-minute tool timeout and had to be abandoned mid-search.
**Standard:** A search across an entire filesystem root is known to be slow/expensive; scope to plausible locations (PATH, Program Files, known install dirs) first.
**Fix:** Switched to targeted checks (where/Get-Command, known install paths), which confirmed gh wasn't installed in seconds.

## unintended-tool-call-not-disclosed

An unexplained tool call with a real side effect fired mid-session and was not disclosed to the user.

### 2026-08-18 | - | caught: self
A call to mcp__ccd_directory__request_directory fired mid-session, granting access to an unrelated folder (C:\Users\maxon\New folder) with nothing to do with the task. Noticed internally that it looked anomalous/unintended at the time but never surfaced it to Caelan or investigated further -- just moved on silently.
**Standard:** An action with a real side effect (granting filesystem access) that the agent doesn't recognize as its own intentional choice should be disclosed to the user, not silently ignored -- regardless of whether the root cause was the agent or the harness. Arguable: unclear whether this was a genuine agent-issued call or a harness artifact, but the disclosure standard applies either way.
**Fix:** Flagging it here on full-conversation review, per Caelan's request. No further action was taken on the granted access itself since it was never used for anything.

## mistakes-not-logged-contemporaneously

Mistakes happened during the session but weren't recorded until asked for at the very end, despite AGENTS.md requiring recording as they happen.

### 2026-08-18 | - | caught: self
None of the five mistakes above were recorded in this workspace's MISTAKES.md at the point they actually happened. All five (plus this one) were only written after Caelan explicitly asked for a full-conversation review at the end of the session.
**Standard:** This workspace's AGENTS.md: 'record it in this workspace's MISTAKES.md as it happens, not at the end.'
**Fix:** Logged the full backlog now via this review. Going forward, log at the point of discovery instead of batching to the end.

### 2026-08-18 | 03_build | caught: self
Second occurrence: none of this session's work (Google/password fix, list-screen and reading-flow redesign, loudness votes, GPS venue guess, the unbounded-native-async-call ANR) was logged to MISTAKES.md as it happened, despite this exact failure already being recorded once before. Only written now because Caelan asked at the end of the session, again.
**Standard:** This workspace's AGENTS.md: 'record it in this workspace's MISTAKES.md as it happens, not at the end.'
**Fix:** Logged now via full-conversation review. Still within the 1-2 occurrence 'incident' band per _system/mistakes.md's threshold table, so no guard is required yet -- but a third occurrence would cross into 'approaching' and call for one.

## unbounded-native-async-call

Called Geolocator.getCurrentPosition() for the venue-guess feature with only a Dart-side .timeout() wrapper, no platform-level time bound. Live-tested on the emulator: the default FusedLocationProvider path could retry a network-based fix indefinitely; an interim fix attempt (forceLocationManager: true, tried without researching it first) hung even harder, producing a real Android ANR (confirmed via adb logcat: 'ANR in system', 80-100%+ kernel CPU) that required force-closing the app.

### 2026-08-18 | 03_build | caught: self
Called Geolocator.getCurrentPosition() for the venue-guess feature with only a Dart-side .timeout() wrapper, no platform-level time bound. Live-tested on the emulator: the default FusedLocationProvider path could retry a network-based fix indefinitely; an interim fix attempt (forceLocationManager: true, tried without researching it first) hung even harder, producing a real Android ANR (confirmed via adb logcat: 'ANR in system', 80-100%+ kernel CPU) that required force-closing the app.
**Standard:** An async platform-channel call to a service that can genuinely stall (network-based location resolution) needs its bound set at the native/platform level (geolocator's own timeLimit), not just wrapped in a Dart Future.timeout() that can't interrupt work already in flight on the platform side.
**Fix:** Reverted forceLocationManager. Added timeLimit: Duration(seconds: 8) directly to LocationSettings. Re-tested live: the same underlying system dialog reappeared but the app stayed fully responsive, confirming the native bound was the actual fix.

## workflow-file-placed-in-wrong-repo-root

Placed .github/workflows/deploy-web.yml inside app/.github/workflows/ instead of the true git repo root's .github/workflows/. This workspace and the app share one git repository (the outer ICM workspace is the actual repo root, app/ is a subdirectory several levels down), so GitHub Actions never saw the workflow file at all -- the Actions tab showed the 'Get started' onboarding page instead of the workflow, which is how Caelan caught it.

### 2026-08-19 | 03_build | caught: user
Placed .github/workflows/deploy-web.yml inside app/.github/workflows/ instead of the true git repo root's .github/workflows/. This workspace and the app share one git repository (the outer ICM workspace is the actual repo root, app/ is a subdirectory several levels down), so GitHub Actions never saw the workflow file at all -- the Actions tab showed the 'Get started' onboarding page instead of the workflow, which is how Caelan caught it.
**Standard:** Before adding any repo-root-relative config file (.github/workflows, .gitignore-adjacent tooling, etc.) to a nested project directory, verify where the actual git repository root is (git rev-parse --show-toplevel) rather than assuming the project directory (app/) is the repo root.
**Fix:** Moved deploy-web.yml to the true root .github/workflows/, added a job-level working-directory default (stages/03_build/output/app) for the run: steps, and kept the wrangler-action's build/web path as a full path from repo root since 'uses:' steps don't inherit the working-directory default. Documented the correct location explicitly in PLATFORM_SETUP.md.

## cloudflare-pages-project-assumed-auto-created

PLATFORM_SETUP.md and deploy-web.yml assumed 'wrangler pages deploy' auto-creates the Cloudflare Pages project on first run. It does not -- Caelan's live deploy failed with 'Project not found ... [code: 8000007]' since the project genuinely did not exist yet. Caught by Caelan running the actual deploy and pasting the GitHub Actions error log.

### 2026-08-19 | 03_build | caught: user
PLATFORM_SETUP.md and deploy-web.yml assumed 'wrangler pages deploy' auto-creates the Cloudflare Pages project on first run. It does not -- Caelan's live deploy failed with 'Project not found ... [code: 8000007]' since the project genuinely did not exist yet. Caught by Caelan running the actual deploy and pasting the GitHub Actions error log.
**Standard:** Don't document or build around an assumed CLI/API behavior (auto-creation, idempotency, defaults) without verifying it against the tool's actual docs or a real run -- especially for a step that's expensive to get wrong (a failed production deploy).
**Fix:** Added a continue-on-error 'wrangler pages project create' step before the deploy step in deploy-web.yml, so the project is created explicitly on first run and the create step becomes a harmless no-op on every run after. Corrected PLATFORM_SETUP.md's claim.

## cloudflare-token-permission-incomplete

PLATFORM_SETUP.md told Caelan to scope the Cloudflare API token to only 'Pages: Edit'. Wrangler's own auth check also needs 'User -> User Details -> Read' -- without it, every wrangler command fails with Authentication error [code: 10000] before even reaching the Pages API. Caught by Caelan running the actual deploy and pasting the GitHub Actions error log; he had already created the token with only the originally-documented permission.

### 2026-08-19 | 03_build | caught: user
PLATFORM_SETUP.md told Caelan to scope the Cloudflare API token to only 'Pages: Edit'. Wrangler's own auth check also needs 'User -> User Details -> Read' -- without it, every wrangler command fails with Authentication error [code: 10000] before even reaching the Pages API. Caught by Caelan running the actual deploy and pasting the GitHub Actions error log; he had already created the token with only the originally-documented permission.
**Standard:** When documenting a third-party token's required scopes from general knowledge/docs rather than a verified working example, flag it as unverified, or better, verify by actually exercising the token before handing off setup instructions.
**Fix:** Corrected PLATFORM_SETUP.md to list both required permissions and to note Cloudflare's token template gallery has no dedicated Pages template (use Create Custom Token).

## shell-special-chars-unquoted-for-remote-shell

Opened the first Supabase confirmation-link URL on the Android emulator via 'adb shell am start ... -d "<url>"' with the URL only protected by local bash double-quotes. adb shell re-parses the assembled command line through the DEVICE's own remote shell, which treated the URL's unescaped '&' characters as its own job-control operator, silently truncating the command before 'type=signup' -- Supabase responded 'Verify requires a verification type' instead of confirming the account. Self-caught immediately by reading the response, fixed within the same tool-call sequence by re-wrapping the URL in single quotes for the remote shell.

### 2026-08-19 | 03_build | caught: self
Opened the first Supabase confirmation-link URL on the Android emulator via 'adb shell am start ... -d "<url>"' with the URL only protected by local bash double-quotes. adb shell re-parses the assembled command line through the DEVICE's own remote shell, which treated the URL's unescaped '&' characters as its own job-control operator, silently truncating the command before 'type=signup' -- Supabase responded 'Verify requires a verification type' instead of confirming the account. Self-caught immediately by reading the response, fixed within the same tool-call sequence by re-wrapping the URL in single quotes for the remote shell.
**Standard:** When constructing a command that's passed through two shells (local, then a remote one via adb/ssh/etc.), quote for the shell that will actually parse special characters (&, |, ;, etc.) in the final string, not just the local one.
**Fix:** Rebuilt the command as adb shell "am start ... -d '$URL'" (single-quoted for the device's remote shell), retried, and got the correct deep-link handoff. No lasting effect -- the first attempt didn't corrupt any state, just returned an error.

## edge-function-not-deployed

Edited supabase/functions/places-search/index.ts locally (addressComponents field mask + pagination) but never deployed it before running the live pipeline. The live Edge Function still ran the old code, so the suburb fix produced 0/1221 suburbs and pagination never engaged.

### 2026-08-19 | 03_build | caught: self
Edited supabase/functions/places-search/index.ts locally (addressComponents field mask + pagination) but never deployed it before running the live pipeline. The live Edge Function still ran the old code, so the suburb fix produced 0/1221 suburbs and pagination never engaged.
**Standard:** A code change to a Supabase Edge Function isn't live until it's actually deployed — editing the local file is not enough, and this should be verified (redeploy, or check the deployed version) before running the live/paid job that depends on it.
**Fix:** Deployed the corrected function via the Supabase MCP deploy_edge_function tool (now version 5), confirmed the field mask includes addressComponents and nextPageToken. Flagged the wasted ~63 Places API requests to Caelan and held off re-running the pipeline until he confirms.

## deploy-workflow-missing-dart-define

deploy-web.yml's flutter build web step only ever passed SUPABASE_URL/SUPABASE_ANON_KEY as dart-defines, never GOOGLE_WEB_CLIENT_ID. The app is designed to hide (not error on) an unconfigured sign-in option, so this produced a silently missing Google sign-in button on the live deployed site rather than a build failure — Caelan caught it from a live screenshot of the Sign In screen.

### 2026-08-19 | 03_build | caught: user
deploy-web.yml's flutter build web step only ever passed SUPABASE_URL/SUPABASE_ANON_KEY as dart-defines, never GOOGLE_WEB_CLIENT_ID. The app is designed to hide (not error on) an unconfigured sign-in option, so this produced a silently missing Google sign-in button on the live deployed site rather than a build failure — Caelan caught it from a live screenshot of the Sign In screen.
**Standard:** A deploy workflow's build-time flags need to include every dart-define a feature's own config-check depends on, not just the ones needed for the build to succeed at all — 'builds successfully' and 'ships a working feature' aren't the same check when a feature is designed to fail silent.
**Fix:** Added --dart-define=GOOGLE_WEB_CLIENT_ID=... to deploy-web.yml (the value is a public OAuth client ID, not a secret, so hardcoded directly rather than added as a GitHub secret). Verified locally: rebuilding with the same flag makes 'Sign in with Google'/'Sign up with Google' appear in the compiled bundle where they were absent before.

## google-signin-reinitialized-per-call

OAuthService.signInWithGoogle() called GoogleSignIn.instance.initialize() fresh on every invocation instead of once per app lifetime. google_sign_in's own doc comment is explicit: 'Clients must call this method exactly once... Calling this method more than once will result in undefined behavior.' Worked on the very first attempt (nothing had ever actually exercised a second attempt, since the button itself was missing on web until this session's earlier fix), then threw 'Bad state: init() has already been called' on any retry - caught live by Caelan tapping the newly-visible button.

### 2026-08-19 | 03_build | caught: user
OAuthService.signInWithGoogle() called GoogleSignIn.instance.initialize() fresh on every invocation instead of once per app lifetime. google_sign_in's own doc comment is explicit: 'Clients must call this method exactly once... Calling this method more than once will result in undefined behavior.' Worked on the very first attempt (nothing had ever actually exercised a second attempt, since the button itself was missing on web until this session's earlier fix), then threw 'Bad state: init() has already been called' on any retry - caught live by Caelan tapping the newly-visible button.
**Standard:** A third-party SDK's own documented lifecycle contract (init-exactly-once, singleton clients, etc.) has to be honored structurally (memoized/guarded), not just called correctly once and hoped to only run once.
**Fix:** Memoized the initialize() call behind a cached Future (_googleInitialization), not just a bool guard, so concurrent calls before the first resolves also share the one real initialize() rather than racing. Also clears the memoized future on failure so a transient error doesn't permanently brick Google sign-in for the rest of the session.

## google-signin-blocked-on-optional-access-token

signInWithGoogle() let a failure requesting the Google access token (authorizationForScopes/authorizeScopes) abort the entire sign-in, even though Supabase's signInWithIdToken only requires the ID token (accessToken is nullable) and nothing else in the app uses the access token. Surfaced live as 'Null check operator used on a null value' - traced to a real bug in google_sign_in_web 1.1.3 itself (gis_client.dart's token-client response handler does response.expires_in! with no null guard), not app code, but the app's own code is what let that upstream failure block sign-in entirely.

### 2026-08-19 | 03_build | caught: user
signInWithGoogle() let a failure requesting the Google access token (authorizationForScopes/authorizeScopes) abort the entire sign-in, even though Supabase's signInWithIdToken only requires the ID token (accessToken is nullable) and nothing else in the app uses the access token. Surfaced live as 'Null check operator used on a null value' - traced to a real bug in google_sign_in_web 1.1.3 itself (gis_client.dart's token-client response handler does response.expires_in! with no null guard), not app code, but the app's own code is what let that upstream failure block sign-in entirely.
**Standard:** When a third-party call is fetching data this app doesn't strictly need for the operation to succeed, a failure in that call shouldn't be allowed to fail the whole operation - especially when the dependency (here: an unpatchable upstream package bug) is outside this codebase's control.
**Fix:** Wrapped the authorizationForScopes/authorizeScopes call in try/catch, falling back to accessToken: null on any failure. Verified nothing else in the app reads the Google access token before making this change.

## google-signin-wrong-param-for-web-client-id

The web client ID was passed to GoogleSignIn.instance.initialize() as serverClientId (correct on iOS/Android, where it sets the ID token's audience to match Supabase's configured Google provider), but google_sign_in_web's own init() implementation only ever reads params.clientId - it ignores serverClientId entirely and asserts it must be null on web. With clientId left null on web (only conditionally set for iOS), the package's own unguarded appClientId! threw 'Null check operator used on a null value'. The previous fix that session (making the separate access-token step non-fatal) was a real, correct fix for a different bug in the same package, but didn't address this one - so Caelan retried after that deploy and hit the exact same error message, which read as 'the fix didn't work' when actually a second, unrelated null-check bug in the same auth flow was still live.

### 2026-08-19 | 03_build | caught: user
The web client ID was passed to GoogleSignIn.instance.initialize() as serverClientId (correct on iOS/Android, where it sets the ID token's audience to match Supabase's configured Google provider), but google_sign_in_web's own init() implementation only ever reads params.clientId - it ignores serverClientId entirely and asserts it must be null on web. With clientId left null on web (only conditionally set for iOS), the package's own unguarded appClientId! threw 'Null check operator used on a null value'. The previous fix that session (making the separate access-token step non-fatal) was a real, correct fix for a different bug in the same package, but didn't address this one - so Caelan retried after that deploy and hit the exact same error message, which read as 'the fix didn't work' when actually a second, unrelated null-check bug in the same auth flow was still live.
**Standard:** When the same symptom (a generic error message) persists after a targeted fix, don't assume the fix failed without re-deriving the failure from source again - a second, unrelated bug producing an identical-looking error is a real possibility, especially in a third-party package with more than one unguarded null-check in the same code path.
**Fix:** Split the initialize() call by platform: clientId on web (what google_sign_in_web actually reads), serverClientId on iOS/Android (unchanged, still correct there). Verified by reading google_sign_in_web's init() source directly (appClientId = params.clientId ?? autoDetectedClientId) and its README's documented web setup (a <meta name="google-signin-client_id"> tag this app never had), not by guessing.

## google-signin-never-verified-on-web

OAuthService.signInWithGoogle() (custom pill button calling GoogleSignIn.instance.authenticate()) was built mobile-first and never actually re-verified once web became a first-class platform (2026-08-18). Surfaced live 2026-08-19 as a self-explanatory error: 'UnimplementedError: authenticate is not supported on the web. Instead, use renderButton to create a sign-in widget.' This is google_sign_in_web's documented, intentional design (Google's GIS SDK only allows its own rendered UI to start a web sign-in), not a bug - the gap was assuming the same imperative custom-button flow that works on iOS/Android would also work on web, which it structurally cannot.

### 2026-08-19 | 03_build | caught: user
OAuthService.signInWithGoogle() (custom pill button calling GoogleSignIn.instance.authenticate()) was built mobile-first and never actually re-verified once web became a first-class platform (2026-08-18). Surfaced live 2026-08-19 as a self-explanatory error: 'UnimplementedError: authenticate is not supported on the web. Instead, use renderButton to create a sign-in widget.' This is google_sign_in_web's documented, intentional design (Google's GIS SDK only allows its own rendered UI to start a web sign-in), not a bug - the gap was assuming the same imperative custom-button flow that works on iOS/Android would also work on web, which it structurally cannot.
**Standard:** A shared OAuth abstraction built against one platform's SDK constraints needs re-checking against each new platform's own constraints before assuming it 'just works' there too - especially for a package whose own README already documents the web behavior being different (found on the second read, after the crash, not the first).
**Fix:** Split into a platform-conditional GoogleAuthButton (widgets/google_auth_button.dart): mobile keeps the existing custom pill button + authenticate() flow unchanged; web renders Google's own GIS button (renderButton() from google_sign_in_web/web_only.dart) and completes sign-in via a listener on GoogleSignIn.instance.authenticationEvents instead of an awaited call. Shared the actual Supabase-completion logic (ID token, best-effort access token) between both paths via OAuthService.completeGoogleSignIn() so it isn't duplicated.

## branch-not-reverified-before-commit

Created feature/marketing-site, then built the site over many tool calls while a concurrent session was demonstrably active in the same repo (two 'File has been modified since read' errors on build-log.md, and the branch's first open item changed twice under me). That session merged PR #15, created fix/google-oauth-redirect-to, and switched the working tree to it. I ran git add and git commit without re-checking the branch, so the marketing-site commit landed on the other session's OAuth branch instead of mine.

### 2026-08-19 | 03_build | caught: self
Created feature/marketing-site, then built the site over many tool calls while a concurrent session was demonstrably active in the same repo (two 'File has been modified since read' errors on build-log.md, and the branch's first open item changed twice under me). That session merged PR #15, created fix/google-oauth-redirect-to, and switched the working tree to it. I ran git add and git commit without re-checking the branch, so the marketing-site commit landed on the other session's OAuth branch instead of mine.
**Standard:** Re-check the current branch immediately before staging or committing, especially with positive evidence of a concurrent session in the same working tree. git branch --show-current is one cheap command and the evidence of concurrency was already in hand.
**Fix:** Commit is unpushed (ahead 1), so it is recoverable by moving feature/marketing-site to it and rewinding fix/google-oauth-redirect-to to 084d488. That command was blocked by the permission classifier and is awaiting Caelan's decision. Going forward: verify branch right before the commit, not only at branch-creation time.

