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
