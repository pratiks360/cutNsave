# cutNsave

Android app for scanning newspaper cutouts (Marathi / Hindi / English): saves the photo, OCRs it, translates to English, files it in a category, and shares it as PDF. Family-shared library on Supabase.

## One-time setup

### 1. Release keystore
```bash
keytool -genkeypair -v -keystore cutnsave-release.jks -alias cutnsave -keyalg RSA -keysize 2048 -validity 10000
keytool -list -v -keystore cutnsave-release.jks -alias cutnsave   # note the SHA-1
base64 -w0 cutnsave-release.jks > keystore.b64                    # for GitHub secret
```
Back up the `.jks` and its passwords somewhere safe. Losing it means users must uninstall to update.

### 2. Google Cloud
1. Create a project; enable **billing** (required by Google even for the free tier; the app caps usage at the free limits).
2. Enable **Cloud Vision API** and **Cloud Translation API**.
3. Create an **API key**, restrict it to those two APIs. This goes in Supabase secrets only.
4. OAuth consent screen: External, add your and your mom's Google accounts as test users (or publish).
5. Create OAuth clients: **Web** (note client ID + secret) and **Android** (package `com.cutnsave.cutnsave`, SHA-1 from step 1; add another Android client for your debug keystore SHA-1 if you run debug builds).

### 3. Supabase
1. Create project. Auth → Providers → **Google**: enable, paste Web client ID + secret, enable **Skip nonce checks**.
2. ```bash
   supabase link --project-ref <ref>
   supabase db push
   supabase secrets set GOOGLE_API_KEY=<key from step 2.3>
   supabase functions deploy ocr translate
   ```
3. Note Project URL and anon key (Settings → API).

### 4. GitHub
1. Create a **public** repo `cutNsave`, push this code.
2. Settings → Secrets → Actions: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` (`cutnsave`), `KEY_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`.

## Local development
```bash
cp env.example.json env.json   # fill in values
flutter run --dart-define-from-file=env.json
flutter test
```

## Releasing
```bash
git tag v1.0.0 && git push origin v1.0.0
```
The Release workflow builds a signed APK and attaches `cutnsave.apk`. Installed apps pick it up via Settings → Check for updates.

First install: open the release page on the phone, download `cutnsave.apk`, allow "install unknown apps" for the browser.
