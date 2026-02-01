import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import { apiHandler } from "./api";
import { goHandler } from "./go";

if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({ region: "europe-west1" });

export const api = onRequest(
  { cors: true },
  apiHandler
);

export const go = onRequest(goHandler);
