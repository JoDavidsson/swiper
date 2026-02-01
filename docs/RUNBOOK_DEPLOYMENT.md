# Swiper – Deployment runbook

## Firebase project setup

1. Create project in Firebase Console.
2. Enable Firestore, Storage, Authentication (optional), Hosting.
3. `firebase login` and `firebase use <project-id>`.
4. `cd apps/Swiper_flutter && flutterfire configure` to generate Flutter Firebase config.

## Deploy Functions + Hosting

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

- **Functions**: `ADMIN_PASSWORD`, `SUPPLY_ENGINE_URL` (Cloud Run URL). Set in Firebase Console or `firebase functions:config:set`.
- **Supply Engine**: `GOOGLE_APPLICATION_CREDENTIALS` or service account in Secret Manager; `SOURCES_JSON` or load from Firestore later.

## Post-deploy

1. Ingest seed data: run Supply Engine `POST /run/sample_feed` or use script with production Firestore.
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
