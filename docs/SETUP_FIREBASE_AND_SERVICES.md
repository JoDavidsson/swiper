# Swiper – What to set up (Firebase + optional services)

## 1. What we need from Firebase

### A) Project ID (you already have this)

- From Firebase Console: **Project settings** → **Project ID** (e.g. `swiper-prod-abc123`).
- **Where it’s used:**  
  - Locally: `firebase use <project-id>` and `flutterfire configure` (see below).  
  - No need to paste it into a file by hand; the CLI and Flutter config use it.

### B) Service account key (for Supply Engine + optional admin)

- **What:** A JSON key so the Supply Engine (and optionally other backends) can read/write Firestore.
- **How to get it:**  
  1. Firebase Console → **Project settings** (gear) → **Service accounts**.  
  2. **Generate new private key** (creates a `.json` file).  
  3. Save it somewhere **outside** the repo (e.g. `~/keys/swiper-firebase-adminsdk.json`).  
- **Where to “add” it:**  
  - **Do not commit this file.** It’s already in `.gitignore` (`*serviceAccount*.json`, `*firebase-adminsdk*.json`).  
  - **Local:** Set the path in your **`.env`** (see below).  
  - **Production (e.g. Cloud Run):** Set the path or contents via Secret Manager / env (see runbook).

### C) Admin password (for admin console)

- **What:** A legacy password fallback for admin login. Hosted admin should use Google Sign-In + Firestore `adminAllowlist`; password login is mainly for local/emulator use unless you explicitly enable it in production.  
- **Where to add it:**  
  - **Local:** In **`.env`** as `ADMIN_PASSWORD=your-secure-password`.  
  - **Production:** Only if you intentionally want hosted password fallback, set both `ADMIN_PASSWORD` and `ALLOW_LEGACY_ADMIN_PASSWORD=true` in your deployment env (see runbook).

---

## 2. Where to add things (local)

Create a **`.env`** file in the **repo root** (copy from `.env.example`). Only this file holds secrets; it is gitignored.

| What | Env variable | Example value |
|------|----------------|---------------|
| Firebase project | (used by `firebase use` and Flutter; no env var required) | — |
| Service account key path | `GOOGLE_APPLICATION_CREDENTIALS` | `/Users/you/keys/swiper-firebase-adminsdk.json` |
| Admin password | `ADMIN_PASSWORD` | `your-admin-password` |
| Legacy password fallback toggle | `ALLOW_LEGACY_ADMIN_PASSWORD` | `true` |
| Google Sign-In web client ID | `GOOGLE_SIGN_IN_WEB_CLIENT_ID` | `123456789-xxx.apps.googleusercontent.com` |
| API base URL (Flutter, if not using emulator) | `API_BASE_URL` | `https://YOUR_PROJECT.web.app` |
| Supply Engine URL (production) | `SUPPLY_ENGINE_URL` | `https://swiper-supply-engine-xxx.run.app` |

**Example `.env` (local, real Firebase project):**

```bash
# Firebase – path to service account JSON (Supply Engine + scripts)
GOOGLE_APPLICATION_CREDENTIALS=/Users/johannesdavidsson/keys/swiper-firebase-adminsdk.json

# Admin console password
ADMIN_PASSWORD=your-secure-password

# Enable hosted password fallback only if you intentionally need it.
# ALLOW_LEGACY_ADMIN_PASSWORD=true

# Required for Google Sign-In on Flutter web
# GOOGLE_SIGN_IN_WEB_CLIENT_ID=123456789-xxx.apps.googleusercontent.com

# Flutter – only if app talks to deployed Functions (not emulator)
# API_BASE_URL=https://YOUR_PROJECT_ID.web.app

# Supply Engine – only for production / deployed Functions
# SUPPLY_ENGINE_URL=https://swiper-supply-engine-xxx.run.app
```

Notes:

- Flutter’s Firebase config (API URL, project ID, etc.) comes from **FlutterFire**, not from `.env`. You run `flutterfire configure` once (see below).
- Functions config (e.g. `ADMIN_PASSWORD`, `SUPPLY_ENGINE_URL`) is set in Firebase / your deployment pipeline for **production**; for **local** you can keep them in `.env` and point your scripts/tooling at it if you add that support, or set them in the emulator/Functions config as per Firebase docs.

---

## 3. One-time Firebase + Flutter setup (after account is ready)

**Done for you in the repo:** Default Firebase project is set to `swiper-95482` in `.firebaserc`.

**You do once (in your terminal, where Flutter is installed):**

1. **Re-login to Firebase** (fixes expired tokens so the CLI can see your project):
   ```bash
   firebase login
   ```
   Complete the browser sign-in if prompted.

2. **Run the FlutterFire setup script** (installs FlutterFire CLI if needed, runs `flutterfire configure`):
   ```bash
   cd "/Users/johannesdavidsson/Cursor Projects/Swiper"
   chmod +x scripts/setup_flutter_firebase.sh
   ./scripts/setup_flutter_firebase.sh
   ```
   When prompted, select **swiper-95482** and the platforms you want (e.g. Web, iOS, Android).

After this, the Flutter app has `lib/firebase_options.dart` and can talk to your Firebase project (or emulators when you use them).

---

## 4. Other services (optional for MVP)

| Service | Needed for MVP? | When / why |
|--------|------------------|------------|
| **Firebase** (Firestore, Functions, Hosting, Auth optional) | **Yes** | Core backend and web app. You’ve set up the account. |
| **Google Cloud (same project)** | **Only if you deploy Supply Engine** | Supply Engine runs on **Cloud Run**. Same GCP project as Firebase; no extra “account,” just enable Cloud Run and optionally Secret Manager. |
| **Affiliate / product feed URLs** | Optional | When you add real feeds (CSV/JSON/XML), you’ll add URLs in `config/sources.json` or later in Firestore. No separate “service” signup required for MVP. |
| **LLM / AI extraction** | No | Optional; behind `ENABLE_LLM_EXTRACTOR` and `LLM_API_KEY` in `.env` if you add it later. |

So: **no other accounts are required** for the MVP besides Firebase (and the same GCP project for Cloud Run when you deploy the Supply Engine).

---

## 5. Push to a private Git repo (one-time)

Create a **private** repository on GitHub (or GitLab, etc.); do **not** initialize it with a README. Then from the repo root:

```bash
./scripts/push_to_remote.sh <YOUR_REPO_URL>
```

Example (GitHub SSH):

```bash
./scripts/push_to_remote.sh git@github.com:yourusername/Swiper.git
```

If you prefer to add the remote yourself:

```bash
git remote add origin <YOUR_REPO_URL>
git push -u origin main
```

---

## 6. Quick checklist

- [ ] Firebase project created and Project ID noted.
- [ ] Service account key downloaded; path set in **`.env`** as `GOOGLE_APPLICATION_CREDENTIALS`.
- [ ] **`.env`** created from `.env.example` with `ADMIN_PASSWORD` for local fallback, and `GOOGLE_SIGN_IN_WEB_CLIENT_ID` if you want hosted admin login on web.
- [ ] `firebase use YOUR_PROJECT_ID` and `flutterfire configure` run once.
- [ ] (Later) Enable Cloud Run in the same GCP project when you deploy the Supply Engine; no extra signup.

If you tell me your Project ID and where you saved the service account JSON (e.g. path), I can give you the exact `.env` lines to add (without you pasting the JSON contents).

---

## Troubleshooting

### "Found 0 Firebase projects" / "Failed to list Firebase projects" / 401 Unauthenticated

Your Firebase CLI **stored credentials are invalid** (token refresh returns 400). Fix it by logging out and logging back in so the CLI gets fresh OAuth tokens:

```bash
firebase logout
firebase login
```

Complete the browser sign-in with **johannesdavidsson@gmail.com** (the account that owns project `swiper-95482`). Then run:

```bash
./scripts/setup_flutter_firebase.sh
```

If you see the same error after re-login, check `apps/Swiper_flutter/firebase-debug.log` for details. You can also try clearing the Firebase CLI config and logging in again: `rm -rf ~/.config/firebase` then `firebase login` (this removes all stored projects/tokens).

### "Invalid project selection, please verify project ... exists and you have access"

1. Log in with the Google account that owns the Firebase project:
   ```bash
   firebase login
   ```
2. List your projects and check the **exact** project ID:
   ```bash
   firebase projects:list
   ```
3. Use that exact ID (e.g. `swiper-95482` or whatever appears in the list):
   ```bash
   firebase use swiper-95482
   ```
   If the project doesn’t appear, create it in [Firebase Console](https://console.firebase.google.com/) or use the account that owns it.

### "command not found: flutterfire"

FlutterFire CLI is a separate tool. Install it and ensure the global pub-cache is on your PATH:

```bash
dart pub global activate flutterfire_cli
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

Then from the **repo root**:

```bash
cd apps/Swiper_flutter
flutter pub get
flutterfire configure
```

(Permanent PATH: add `export PATH="$PATH":"$HOME/.pub-cache/bin"` to your `~/.zshrc` and run `source ~/.zshrc`, or use the same `export` in the same terminal before running `flutterfire configure`.)

### "command not found: flutter"

Install Flutter and add it to your PATH (see [Flutter install](https://docs.flutter.dev/get-started/install)). On macOS you can use `brew install flutter` or download the SDK and add e.g. `export PATH="$PATH:$HOME/flutter/bin"` to `~/.zshrc`. Then run `./scripts/setup_flutter_firebase.sh` again.

### Manual `firebase_options.dart` (if CLI auth still fails)

If `firebase login` doesn’t fix the 401 and you want to run the app against the real Firebase project:

1. In [Firebase Console](https://console.firebase.google.com/) open project **swiper-95482** → **Project settings** (gear) → **Your apps**.
2. If there’s no Web app, click **Add app** → **Web** (</>), register the app, and copy the `firebaseConfig` object.
3. Create `apps/Swiper_flutter/lib/firebase_options.dart` using the template in `docs/firebase_options_template.dart` (in this repo). Fill in `apiKey`, `appId`, `projectId`, `authDomain`, `storageBucket`, etc. from the Console.
4. In `main.dart` call `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);` before `runApp`.

Prefer fixing CLI auth with `firebase logout` and `firebase login` so `flutterfire configure` works for all platforms.
