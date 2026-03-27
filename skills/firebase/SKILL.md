# Firebase Development

Reusable skill for Firebase — Cloud Functions, Firestore, Hosting, Auth.

## Triggers

- "add a Firebase Function"
- "change the Firestore schema"
- "set up Firebase Auth"
- "deploy to Firebase"

## Actions

1. Functions live in `firebase/functions/src/`
2. Emulators: `firebase emulators:start` (or `./scripts/run_emulators.sh`)
3. Deploy: `firebase deploy --only functions,hosting`
4. Firestore rules: `firebase/firestore.rules`
5. On schema change: update `docs/DATA_MODEL.md` and `docs/DECISIONS.md`

## API Routes

| Route | Handler |
|-------|---------|
| `POST /api/session` | Create session |
| `GET /api/items/deck` | Ranked deck |
| `POST /api/swipe` | Record swipe + update weights |
| `POST /api/likes/toggle` | Add/remove like |
| `POST /api/shortlists/create` | Create shareable shortlist |
| `GET /s/:token` | Shared shortlist page |
| `GET /go/:itemId` | Outbound redirect with UTM |

## Security Rules

- Anonymous sessions: read/write own session only
- Items: public read
- Shortlists: read via share token, no write
- Admin: authenticated admin only
- See `firebase/firestore.rules` and `docs/SECURITY.md`

## Files

- `firebase/functions/src/api/` — API handlers
- `firebase/firestore.rules`
- `docs/SECURITY.md`
- `docs/DATA_MODEL.md`
