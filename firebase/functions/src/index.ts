import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import { apiHandler } from "./api";
import { goHandler } from "./go";
import { computePersonaSignals } from "./scheduled/persona_aggregation";
import { calculateConfidenceScores } from "./scheduled/confidence_score";

if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({ region: "europe-west1" });

export const api = onRequest(
  { cors: true },
  apiHandler
);

export const go = onRequest(goHandler);

// Scheduled function for collaborative filtering
export { computePersonaSignals };

// Scheduled function for confidence score calculation (hourly)
export { calculateConfidenceScores };
