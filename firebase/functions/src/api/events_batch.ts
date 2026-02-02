import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";

const REQUIRED_TOP_LEVEL = ["schemaVersion", "eventId", "eventName", "sessionId", "clientSeq", "createdAtClient", "app"] as const;
const REQUIRED_APP = ["platform", "appVersion", "locale", "timezoneOffsetMinutes", "screenBucket"] as const;

function isValidEvent(raw: unknown): raw is Record<string, unknown> {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) return false;
  const e = raw as Record<string, unknown>;
  for (const key of REQUIRED_TOP_LEVEL) {
    if (e[key] === undefined) return false;
  }
  const app = e.app;
  if (app == null || typeof app !== "object" || Array.isArray(app)) return false;
  const a = app as Record<string, unknown>;
  for (const key of REQUIRED_APP) {
    if (a[key] === undefined) return false;
  }
  return true;
}

export async function eventsBatchPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const eventsRaw = body?.events;

  if (!Array.isArray(eventsRaw)) {
    res.status(400).json({ error: "events array required" });
    return;
  }

  const db = admin.firestore();
  const collection = db.collection("events_v1");
  const BATCH_LIMIT = 500; // Firestore max writes per batch

  for (let i = 0; i < eventsRaw.length; i++) {
    const raw = eventsRaw[i];
    if (!isValidEvent(raw)) {
      res.status(400).json({ error: `events[${i}] missing required fields` });
      return;
    }

    const e = raw as Record<string, unknown>;
    const eventId = e.eventId as string;
    if (typeof eventId !== "string" || eventId.length < 8) {
      res.status(400).json({ error: `events[${i}] invalid eventId` });
      return;
    }
  }

  for (let offset = 0; offset < eventsRaw.length; offset += BATCH_LIMIT) {
    const chunk = eventsRaw.slice(offset, offset + BATCH_LIMIT);
    const batch = db.batch();
    for (let i = 0; i < chunk.length; i++) {
      const e = chunk[i] as Record<string, unknown>;
      const eventId = e.eventId as string;
      const doc = collection.doc(eventId);
      const docData: Record<string, unknown> = {
        ...e,
        createdAtServer: FieldValue.serverTimestamp(),
      };
      batch.set(doc, docData, { merge: true });
    }
    await batch.commit();
  }

  res.status(200).json({ ok: true, count: eventsRaw.length });
}
