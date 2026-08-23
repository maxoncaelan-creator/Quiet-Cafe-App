# Getting the Sentry key — the bit only Caelan can do

Sentry tells you when the app crashes on someone else's phone. Right now, if a
beta tester's app dies, you find out only if they bother to tell you.

The code is already written and waiting. It needs one thing from you: a **DSN**,
which is just a long web address Sentry gives you so the app knows where to send
crash reports.

**This takes about five minutes.** You need an account, and Claude is not allowed
to create accounts or type passwords, so this part is yours.

---

## Part 1 — Make the account

1. Go to **https://sentry.io/signup/**
2. Sign up. The free plan is enough — it covers 5,000 errors a month, and you
   will not come close during a closed beta.
3. When it asks what you want to monitor, choose **Flutter**.
   - If it doesn't ask, don't worry. You can pick it in the next part.

## Part 2 — Make a project

1. Once you're logged in, look for **Projects** in the left sidebar, then the
   **Create Project** button.
2. From the list of platforms, choose **Flutter**.
3. Name it `quiet-cafe-app` so it matches the repo.
4. Click **Create Project**.

## Part 3 — Copy the DSN

After creating the project, Sentry shows you a setup page with a block of code.
Somewhere in it is a line that looks like this:

```
dsn: 'https://abc123def456@o1234567.ingest.sentry.io/7654321'
```

**You want the part inside the quotes** — starting with `https://` and ending
with a number.

If you've clicked away from that page, you can always find it again:

> **Settings** → **Projects** → click `quiet-cafe-app` → **Client Keys (DSN)**

Or go straight there: **https://sentry.io/settings/projects/**

## Part 4 — Give it to me

Paste it into the chat and say "here's the Sentry DSN". I'll put it where it
needs to go.

**Is it safe to paste?** Yes. A Sentry DSN is not a password. It ships inside
every copy of the app you release, so it is public by design — anyone with your
app already has it. It only allows *sending* crash reports to your project, not
reading them. The thing you must never paste is your Sentry **auth token**,
which is a different item and is genuinely secret.

---

## What happens after that

I put the DSN into the build configuration rather than the source code, so it
stays out of GitHub. Three places need it:

| Where | Why |
|---|---|
| Local builds | So crashes on your own test devices report |
| Cloudflare Pages | So the live web app at `app.cafequiet.com` reports |
| GitHub Actions | Only if you want release tracking; optional |

Until you supply it, **nothing breaks**. The app is built so that with no DSN,
Sentry simply switches itself off. Tests, CI and the standalone demo build all
carry on exactly as now.

---

## Things worth knowing before you turn it on

**It will record errors you didn't know about.** That is the point, but the first
few days can look alarming. A burst of errors on day one usually means you are
finally *seeing* problems that were always there, not that something new broke.

**Turn off session replay if it's offered.** It records what users do on screen.
For a small beta it is more privacy exposure than it is worth, and it eats your
free quota fast.

**Your beta testers' data.** Sentry captures the state around a crash, which can
include what someone searched for. It does not need their email, and I will
configure it not to send one. If you later add Privacy Policy text, crash
reporting is worth a sentence in it.
