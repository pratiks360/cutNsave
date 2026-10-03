<p align="center">
  <h1 align="center">📰✂️ cutNsave</h1>
  <p align="center">
    <strong>Scan newspaper clippings, OCR and translate them, and share them with the family — built in Marathi and English.</strong>
  </p>
  <p align="center">
    <a href="https://github.com/pratiks360/cutNsave/releases/latest"><img src="https://img.shields.io/badge/📲_Latest_Release-Download_APK-e11d48?style=for-the-badge" alt="Latest Release"></a>
    <img src="https://img.shields.io/badge/Flutter-3.47-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
    <img src="https://img.shields.io/badge/Backend-Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase">
    <img src="https://img.shields.io/github/last-commit/pratiks360/cutNsave?style=for-the-badge&label=Last+Commit" alt="Last Commit">
  </p>
</p>

---

## 📋 Table of Contents

- [What Is This?](#-what-is-this)
- [Features](#-features)
- [Screenshots](#-screenshots)
- [Quick Start](#-quick-start)
- [How It Works](#-how-it-works)
- [One-Time Setup](#-one-time-setup-new-deployment)
- [Settings Reference](#️-settings-reference)
- [Tech Stack](#️-tech-stack)
- [Security Notes](#-security-notes)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)

---

## ✨ What Is This?

**cutNsave** is an Android app built for one family to digitize newspaper clippings — recipes, articles, anything worth keeping. Point the camera at a clipping, it reads the text (on-device or via Cloud Vision), translates Marathi/Hindi to English on request, and files it away in a category everyone in the family can search, browse, and share as a PDF or photo. Everything syncs through a shared Supabase backend, so a clipping saved on one phone shows up on everyone else's.

> 🇮🇳 **Marathi-first UI** — defaults to Marathi, toggles to English in Settings.

---

## 🎯 Features

| Feature | Description |
|---|---|
| 📷 **Scan & OCR** | Camera capture → Cloud Vision OCR (primary) with automatic on-device ML Kit fallback when offline or over quota |
| 🌐 **Translate** | Marathi/Hindi → English via on-device ML Kit first, free-tier OpenRouter models as cloud fallback |
| 🗂️ **Categories** | Create, rename, and delete categories; case-insensitive dedup keeps everyone's categories in sync |
| 🔄 **Offline-first sync** | Full read/write while offline; syncs to Supabase automatically when back online, with per-row retry isolation so one bad row never blocks the rest |
| 🔎 **Search** | Full-text search across original and translated text |
| 📤 **Share** | Share a clipping as a formatted PDF (image + original + English text); automatically falls back to sharing the photo directly if PDF rendering fails on a given device |
| 👪 **Shared family library** | One Supabase project, allow-listed by email — every member's phone sees the same clippings |
| 📊 **Quota tracking** | Live view of remaining monthly Cloud OCR/translation quota, so cloud features degrade gracefully instead of failing silently |
| 🔁 **Self-updating** | Settings → Check for updates pulls the latest signed APK straight from GitHub Releases — no Play Store needed |

---

## 📸 Screenshots

> Add a screenshot or screen-recording here — e.g. `![Home screen](docs/screenshot-home.png)`

---

## 🚀 Quick Start

### Option A · Install the App (Zero Setup)

1. Go to **[Releases](https://github.com/pratiks360/cutNsave/releases/latest)** and download `cutnsave.apk` on your phone.
2. Allow "install unknown apps" for your browser/file manager when prompted.
3. Open the app, sign in with the Google account your family library owner allow-listed.
4. From then on, **Settings → Check for updates** keeps the app current — no need to re-download manually.

### Option B · Run Locally (Development)

**Prerequisites:** [Flutter 3.47+](https://docs.flutter.dev/get-started/install), an Android SDK, and a configured Supabase project (see [One-Time Setup](#-one-time-setup-new-deployment)).

```bash
git clone https://github.com/pratiks360/cutNsave.git
cd cutNsave
cp env.example.json env.json   # fill in your own Supabase/Google values
flutter pub get
flutter run --dart-define-from-file=env.json
flutter test
```

---

## 🧩 How It Works

```
┌───────────────┐   scan / save    ┌───────────────┐   OCR / translate   ┌─────────────────────┐
│               │ ───────────────► │               │ ──────────────────► │  Cloud Vision API    │
│  Flutter App  │                  │  Supabase     │                     │  OpenRouter (:free)  │
│  (per phone)  │ ◄─────────────── │  Edge Funcs   │ ◄────────────────── │  (quota-gated)        │
│               │   sync pull      └───────┬───────┘                     └─────────────────────┘
└───────────────┘                          │
        ▲                          Postgres + RLS
        │                          (shared family library)
        └──────────── offline-first local SQLite, reconciled on next sync ────────────┘
```

1. **Scan** — the camera captures a photo; it's OCR'd immediately (Cloud Vision first, ML Kit fallback) and saved locally.
2. **Edit & categorize** — adjust the text, pick/translate the language, file it under a category.
3. **Sync** — a background sync pushes local changes to Supabase and pulls everyone else's, with last-write-wins conflict resolution and per-row retry so one bad row doesn't stall the rest.
4. **Share** — generate a PDF (image + text) or fall back to sharing the raw photo if PDF rendering isn't available on that device.

---

## 🔧 One-Time Setup (New Deployment)

<details>
<summary>Click to expand full setup instructions for deploying your own instance</summary>

### 1. Release keystore
```bash
keytool -genkeypair -v -keystore cutnsave-release.jks -alias cutnsave -keyalg RSA -keysize 2048 -validity 10000
keytool -list -v -keystore cutnsave-release.jks -alias cutnsave   # note the SHA-1
base64 -w0 cutnsave-release.jks > keystore.b64                    # for GitHub secret
```
Back up the `.jks` and its passwords somewhere safe — losing it means users must uninstall to update.

### 2. Google Cloud
1. Create a project; enable **billing** (required even for free-tier Cloud Vision usage — the app caps usage well within the free limits, but Google still requires a billing account attached).
2. Enable **Cloud Vision API**.
3. Create an **API key**, restrict it to Cloud Vision. This goes in Supabase secrets only — never in the app.
4. OAuth consent screen: External, add family members' Google accounts as test users (or publish).
5. Create OAuth clients: **Web** (note the client ID) and **Android** (package `com.cutnsave.cutnsave`, SHA-1 from step 1; add a second Android client for your debug keystore's SHA-1 if you run debug builds).

### 3. OpenRouter (cloud translation)
1. Create a free account at [openrouter.ai](https://openrouter.ai) and generate an API key.
2. No payment method needed — the app only uses `:free`-tier models.

### 4. Supabase
1. Create a project. Auth → Providers → **Google**: enable, paste the Web client ID(s), comma-separated, no spaces.
2. ```bash
   supabase link --project-ref <ref>
   supabase db push
   supabase secrets set GOOGLE_API_KEY=<key from step 2.3>
   supabase secrets set OPENROUTER_API_KEY=<key from step 3>
   supabase functions deploy ocr translate
   ```
3. Note the Project URL and anon key (Settings → API).

### 5. GitHub
1. Repo must be **public** (or the in-app update checker and release APK download will 404 for an unauthenticated client — see [Troubleshooting](#-troubleshooting)).
2. Settings → Secrets → Actions: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` (`cutnsave`), `KEY_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`.

### Releasing
```bash
git tag v1.0.0 && git push origin v1.0.0
```
The Release workflow builds a signed APK and attaches `cutnsave.apk`. Installed apps pick it up via **Settings → Check for updates**.

</details>

---

## ⚙️ Settings Reference

| Setting | What It Does |
|---|---|
| **App language** | Toggles the UI between Marathi (default) and English |
| **Cloud quota (this month)** | Shows remaining Cloud OCR calls and translation characters for the family library |
| **Members** | Add/remove allow-listed family emails who can join the shared library |
| **Check for updates** | Pulls the latest release tag from GitHub, downloads and installs the signed APK in-app |
| **Sign out** | Signs out of Google; local data stays cached for offline access until next sign-in |

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **App** | Flutter 3.47, Dart |
| **Local storage** | SQLite (`sqflite`), offline-first |
| **Backend** | Supabase (Postgres + Row Level Security, Edge Functions on Deno) |
| **OCR** | Google Cloud Vision (primary) + ML Kit on-device text recognition (fallback) |
| **Translation** | ML Kit on-device (primary) + OpenRouter free-tier LLMs (fallback) |
| **Auth** | Google Sign-In → Supabase Auth, email allow-list per family library |
| **PDF generation** | `printing` (WebView-rendered, for Devanagari conjunct shaping) with automatic photo-share fallback |
| **Distribution** | GitHub Releases + in-app self-updater (no Play Store) |
| **CI** | GitHub Actions (test on every push, signed release build on tag push) |

---

## 🔒 Security Notes

- All third-party API keys (Google Cloud Vision, OpenRouter, Supabase service role) live **server-side only**, as Supabase Edge Function secrets — never embedded in the app or committed to the repo.
- The app only ever holds the Supabase **anon key**, which is safe to ship publicly — all real authorization happens via Postgres Row Level Security and per-request JWTs.
- Cloud OCR/translation calls are quota-gated server-side per family library, so a compromised or buggy client can't run up usage beyond the configured cap.
- The repo must be public for the in-app updater to work without embedding a GitHub token in the client (see [Troubleshooting](#-troubleshooting)) — make sure nothing sensitive ever lands in the repo itself.

---

## 🐛 Troubleshooting

**Q: Share PDF hangs on "Preparing PDF…" forever, or fails with an error.**
A: Some devices' platform WebView can't complete `printing`'s HTML-to-PDF render. The app bounds this with a timeout and automatically falls back to sharing the original photo + text directly — if you still see a hang with no fallback, you're likely on an older build; update via Settings → Check for updates.

**Q: Cloud OCR says "no internet" / fails even though the phone has internet.**
A: Cloud Vision requires a Google Cloud **billing account** attached to the project — even though usage stays within the free tier. Enable billing on the project (Google will prompt with a direct link if it's missing) and retry.

**Q: Settings → Check for updates always says "up to date" even after a new release.**
A: The GitHub Releases API returns 404 for unauthenticated requests against a **private** repo, which the updater silently treats as "nothing found." The repo (and therefore its releases) must be public for self-update to work without embedding a token in the app.

**Q: A newly installed debug build won't install over a release build (or vice versa).**
A: Debug and release builds are signed with different keys; Android refuses to update in place across a signature mismatch. Uninstall the existing app first, then install the other build — this clears local data, but anything already synced comes back from Supabase on next sign-in.

**Q: Bottom buttons (Share, Save) are overlapped by the Android gesture/nav bar.**
A: Devices on Android 15+ (`targetSdk` 35+) enforce edge-to-edge rendering by default. Fixed app-wide via a `SafeArea` wrapper in `MaterialApp.builder` — if you still see this, update to the latest release.

---

## 🤝 Contributing

This is a personal project built for one family, but issues and PRs are welcome if you find a bug or want to adapt it for your own family library.

---

## 📄 License

No formal license has been chosen yet — this is a personal/family project. Reach out to [@pratiks360](https://github.com/pratiks360) before reusing substantial parts of it.

---

<p align="center">
  <sub>Built with ❤️ for a mom who keeps every good recipe clipped from the newspaper.</sub>
</p>
