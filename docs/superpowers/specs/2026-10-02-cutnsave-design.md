# cutNsave — Design Spec

Date: 2026-10-02
Status: Draft for review

## 1. Purpose

Android app for the user's mother to digitise newspaper cutouts (mostly Marathi, also Hindi and English). She scans an article, the app saves the photo, extracts the text (OCR), optionally translates it to English, files it in a category, and lets her search and share it (as a PDF, e.g. via WhatsApp). Library is shared with family members.

## 2. Decisions

| Area | Decision |
|---|---|
| Platform | Android only (v1) |
| Framework | Flutter |
| Backend | Supabase (Auth, Postgres, Storage, Edge Functions) |
| Sign-in | Google, via Supabase Auth |
| OCR | ML Kit on-device first; fallback to Google Cloud Vision (via Edge Function) when result is empty/low confidence |
| Translation | ML Kit on-device first; fallback to Google Cloud Translation (via Edge Function) |
| Categorising | Manual only; user can create new categories |
| Connectivity | Offline-first (local SQLite is source of truth, syncs to Supabase) |
| Accounts | Shared family library; members added by email allowlist |
| Share | Generated PDF through Android share sheet |
| UI language | Marathi (default) + English toggle; large text/buttons |
| Build/Release | GitHub Actions builds signed APK on tag, publishes to GitHub Release |
| Updates | In-app "Check for updates" reads latest GitHub Release, downloads and installs APK |

## 3. Architecture

### Units

| Unit | Responsibility | Depends on |
|---|---|---|
| `auth` | Google sign-in, Supabase session, membership check | Supabase |
| `scan` | Camera/gallery capture, preview, retake | device camera |
| `ocr` | ML Kit text recognition; cloud fallback decision | `quota`, Edge Function `ocr` |
| `translate` | ML Kit translation; cloud fallback | `quota`, Edge Function `translate` |
| `library` | Articles and categories CRUD on local DB | local DB |
| `search` | FTS5 query over original + English text | local DB |
| `sync` | Push/pull local ↔ Supabase, image upload | `library`, Supabase |
| `quota` | Read monthly usage; show remaining | Supabase |
| `pdf` | Build article PDF | `library`, bundled font |
| `share` | Hand PDF to Android share sheet | `pdf` |
| `updater` | GitHub Releases check, APK download/install | GitHub API |
| `i18n` | Marathi/English UI strings | — |

### Rules

- Cloud API keys exist only in Supabase Edge Functions, never in the APK.
- Edge Functions verify the caller's Supabase JWT and library membership, increment quota atomically, and **reject** calls once the monthly free quota is reached (prevents Google billing).
- Release APK is signed with one fixed keystore (stored as GitHub secret). Same signature is required for in-place updates, and its SHA-1 is registered in the Google OAuth client for sign-in.

## 4. Data model

### Supabase (Postgres), RLS: row visible only if caller is a member of the row's library

- `libraries` (id, name, owner_id)
- `library_members` (library_id, email, user_id nullable, role `owner|member`). On first sign-in, a row matching the user's email gets `user_id` set.
- `categories` (id, library_id, name, created_at, updated_at, deleted_at)
- `articles` (id, library_id, category_id, image_path, original_text, original_lang `mr|hi|en`, english_text nullable, scanned_at, created_by, updated_at, deleted_at)
- `quota_usage` (library_id, month, ocr_calls, translate_chars)
- Storage bucket `articles`, path `{library_id}/{article_id}.jpg`, same membership rule.

Seeded default categories: Recipes, Health, Stories, Poems, Other.

### Local SQLite

Mirror of `categories` and `articles`, plus `sync_state` (pending ops, last pull time) and an FTS5 virtual table over `original_text` and `english_text`. Images stored in app files directory.

## 5. Flows

### Scan → save
1. Home → large **Scan** button → camera (or gallery).
2. Preview → **Retake** or **Use**.
3. OCR: ML Kit (Devanagari + Latin). If empty or low confidence, and online with quota left, call Cloud Vision; otherwise keep the ML Kit result.
4. Detect language (Marathi / Hindi / English).
5. Edit screen: editable text field, category picker (with **New category**), **Translate** toggle.
6. Translate to English: ML Kit first, Cloud fallback. Skipped if the original is English.
7. **Save**: written to local DB immediately, queued for sync. Stored: image, original text + language, English text.

### Browse / search
- Home: category chips + article list (thumbnail, text snippet, scanned date).
- Search bar: local FTS over original + English text, optional category filter. Works offline.
- Article view: image, original text, English text, **Share PDF**, edit text, change category, delete (soft).

### Share PDF
PDF contains: scan date, article image, original-language text, then English text. Uses a bundled Noto Sans Devanagari font so Marathi/Hindi render correctly. Opened via Android share sheet (WhatsApp, Gmail, Drive, etc.).

### Sync
- Last-write-wins by `updated_at`; deletes are soft (`deleted_at`).
- Push pending changes when online; pull on app open and pull-to-refresh. Image uploads after the row.

### Quota display
Card on Home/Settings: "Cloud OCR: N of 1,000 left · Translate: N of 500k chars left", monthly reset. Read from `quota_usage`. At the cap the Edge Function rejects; app falls back to ML Kit result and shows "limit reached, resets <date>".

### Family / membership
- Settings → Members (owner only): add a Google email.
- Sign-in with an email not in `library_members` → screen "Ask <owner> to add you".
- First-ever user creates a library and becomes owner.

### Updater
Settings → **Check for updates**: query GitHub Releases API (latest), compare to installed version, download APK asset, open Android installer (one-time "install unknown apps" permission prompt). Repo should be public so no token is embedded in the app.

## 6. Error handling

- Offline: scan, ML Kit OCR, ML Kit translation, browse and search all work; cloud fallbacks skipped with small note; sync retries later.
- ML Kit translation model not downloaded: prompt one-time download (~30 MB per language). If offline and no model, save without English and flag "translate later".
- Cloud quota exhausted: use ML Kit result, show reset date.
- Non-member sign-in: friendly "ask owner to add you" screen.
- Updater failure: show error, app stays usable.

## 7. Testing

- Unit: language detection, quota logic, sync merge, PDF builder.
- Edge Functions: quota cap enforced, unauthenticated/non-member rejected.
- RLS: SQL tests proving a non-member reads nothing.
- Manual device checklist with real Marathi/Hindi/English clippings. OCR quality on dense newspaper print is the biggest risk; compare ML Kit vs Cloud Vision early.

## 8. Build and release

- Push tag `vX.Y.Z` → GitHub Actions: set up Flutter, decode keystore from secrets, `flutter build apk --release`, attach APK to a GitHub Release.
- Secrets: keystore (base64), keystore/key passwords. Supabase URL and anon key are public-safe and compiled in.
- App version comes from `pubspec.yaml`; updater compares it to the release tag.

## 9. One-time setup (owner)

Google Cloud project (Vision + Translation APIs enabled, OAuth clients with release SHA-1), Supabase project (schema, RLS, Edge Functions, secrets), public GitHub repo, release keystore. Exact steps go in the implementation plan.

## 10. Out of scope (v1)

Image crop/rotate, multi-page articles, titles/notes, category auto-suggestion, iOS, Hindi UI language.
