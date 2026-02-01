# Swiper – Deployment runbook

## Firebase project setup

1. Create project in Firebase Console.
2. Enable Firestore, Storage, **Authentication** (enable "Google" sign-in for admin), Hosting.
3. `firebase login` and `firebase use <project-id>`.
4. `cd apps/Swiper_flutter && flutterfire configure` to generate Flutter Firebase config.

## Deploy Functions + Hosting

One-command staging deploy (builds Flutter web + Functions, then deploys):

```bash
./scripts/deploy_staging.sh
```

Or manually:

```bash
cd firebase/functions
npm ci && npm run build
cd ../..
firebase deploy --only functions,hosting,firestore:rules,firestore:indexes
```

Hosting will serve Flutter web from `apps/Swiper_flutter/build/web`. Build before deploy:

```bash
cd apps/Swiper_flutter && flutter build web
cd ../..
firebase deploy --only hosting
```

## Deploy Supply Engine (Cloud Run)

```bash
cd services/supply_engine
gcloud run deploy swiper-supply-engine --source . --region europe-west1 --allow-unauthenticated
# Set env: FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS, SOURCES_JSON, etc.
```

Or build and push Docker image:

```bash
docker build -t gcr.io/<project>/supply-engine .
docker push gcr.io/<project>/supply-engine
gcloud run deploy swiper-supply-engine --image gcr.io/<project>/supply-engine ...
```

## Secrets / env

- **Functions**: `ADMIN_PASSWORD` (legacy; optional), `SUPPLY_ENGINE_URL` (Cloud Run URL). Set in Firebase Console or `firebase functions:config:set`.
- **Supply Engine**: `GOOGLE_APPLICATION_CREDENTIALS` or service account in Secret Manager; `SOURCES_JSON` or load from Firestore later.

## Set up full admin access

**Current:** Admin uses **password only** (no Google Sign-In). Set `ADMIN_PASSWORD` in `.env` or Functions config; open `/admin`, enter the password, and you get full access (dashboard, sources, runs, items, import, QA). The backend accepts either a Bearer token (Google + allowlist) or the `X-Admin-Password` header matching `ADMIN_PASSWORD`.

**Optional (paused):** To use Sign in with Google later, do the steps below.

### 1. Enable Google sign-in (Firebase Console)

1. Open [Firebase Console](https://console.firebase.google.com) → your project.
2. Go to **Build** → **Authentication** → **Sign-in method**.
3. Click **Google** → toggle **Enable** → set **Project support email** → **Save**.

### 1b. Web client ID (required for “Sign in with Google” on web)

The Flutter web app needs an **OAuth 2.0 Web client ID** or the Google Sign-In button will error.

1. Open [Google Cloud Console](https://console.cloud.google.com) → same project as Firebase.
2. Go to **APIs & Services** → **Credentials**.
3. Under **OAuth 2.0 Client IDs**, find or create a client of type **Web application** (Firebase often creates one when you enable Google sign-in).
4. Copy the **Client ID** (e.g. `123456789-xxx.apps.googleusercontent.com`).
5. For local dev, run the app with the client ID (use **KEY=VALUE**; the key must be `GOOGLE_SIGN_IN_WEB_CLIENT_ID`):
   ```bash
   cd apps/Swiper_flutter
   flutter run -d chrome --dart-define=GOOGLE_SIGN_IN_WEB_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com
   ```
   Example: `flutter run -d chrome --dart-define=GOOGLE_SIGN_IN_WEB_CLIENT_ID=503757220152-xxxx.apps.googleusercontent.com`
6. For production build:
   ```bash
   flutter build web --dart-define=GOOGLE_SIGN_IN_WEB_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com
   ```
7. **Authorized URIs (required to fix redirect_uri_mismatch):** In Google Cloud Console, open that OAuth 2.0 Web client and add:
   - **Authorized JavaScript origins:**  
     - For local dev: `http://localhost` and `http://localhost:PORT` (use the port Flutter shows in the terminal, e.g. `http://localhost:12345`). If you use 127.0.0.1, also add `http://127.0.0.1:PORT`.  
     - For prod: `https://yourdomain.com`.
   - **Authorized redirect URIs:**  
     - For local dev: `http://localhost:PORT/` and `http://localhost/` (and `http://127.0.0.1:PORT/` if you use that).  
     - For prod: `https://yourdomain.com/`.  
   If you see **Error 400: redirect_uri_mismatch**, click “Error details” on the Google error page and copy the **redirect_uri** shown there, then add that exact URI to **Authorized redirect URIs** and save. Re-run the app and try again.

### 2. Add your email to the admin allowlist

Use the **exact email** you use for Google sign-in (e.g. `you@gmail.com`).

**Option A – Script (recommended)**

From the repo root, with `GOOGLE_APPLICATION_CREDENTIALS` set to your service account JSON path:

```bash
./scripts/add_admin_allowlist.sh you@example.com
```

For the **Firestore emulator** (local), set the emulator host first:

```bash
export FIRESTORE_EMULATOR_HOST=localhost:8180
./scripts/add_admin_allowlist.sh you@example.com
```

**Option B – Firebase Console**

1. Go to **Build** → **Firestore Database**.
2. **Start collection** (or add to existing): collection ID `adminAllowlist`.
3. **Document ID**: your Google email (e.g. `you@example.com`).
4. You can leave fields empty or add e.g. `addedAt` (timestamp). Save.

### 3. Sign in

1. Open your app → go to **/admin** (admin login).
2. Click **Sign in with Google** and sign in with the same email you added.
3. You should land on the admin dashboard; stats, sources, runs, items, import, and QA will work.

## Post-deploy

1. Ingest seed data: run Supply Engine `POST /run/sample_feed` or `POST /run/demo_feed` (or use script with production Firestore). Config has two sources: `sample_feed` (CSV) and `demo_feed` (JSON). For production, add a source with a real feed URL in config or (later) Firestore.
2. Verify `/go/:itemId` redirect and UTM params.
3. Verify admin login and QA/stats endpoints.

## Post-deploy smoke test (first production deploy)

Run through this checklist after deploying to confirm the app works end-to-end:

1. **App loads** – Open the Hosting URL in a browser. Splash screen appears; tap "Get started" or "Skip to swipe".
2. **Session** – Deck or onboarding loads; no "No session" error. (Session is created via POST /api/session.)
3. **Deck** – If seed data was ingested, cards appear. Swipe left/right; deck updates. Tap filter icon; apply size/color/condition; deck refreshes.
4. **Detail** – Tap a card; detail sheet opens. Close sheet; no console errors.
5. **Likes** – Swipe right on an item; go to Likes from nav; item appears. Compare (select 2–4, Compare) works.
6. **Go redirect** – From detail, tap "View on site"; redirect to outbound URL with UTM (or placeholder). Check network for 302 from `/go/:itemId`.
7. **Profile** – Profile and Data & Privacy screens load.
8. **Admin** – Open `/admin`; log in with ADMIN_PASSWORD; dashboard and Sources/Runs/Items/Import/QA load without 500s.
9. **Shared shortlist** – Create shortlist from Likes (share); open `/s/:token` in new tab; shortlist page loads.
