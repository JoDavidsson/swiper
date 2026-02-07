import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";

const REQUIRED_TOP_LEVEL = ["schemaVersion", "eventId", "eventName", "sessionId", "clientSeq", "createdAtClient", "app"] as const;
const REQUIRED_APP = ["platform", "appVersion", "locale", "timezoneOffsetMinutes", "screenBucket"] as const;

function asObject(value: unknown): Record<string, unknown> | null {
  if (value == null || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function hasString(value: unknown): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

function hasNumber(value: unknown): boolean {
  return typeof value === "number" && Number.isFinite(value);
}

function hasInteger(value: unknown): boolean {
  return typeof value === "number" && Number.isInteger(value);
}

function isValidEvent(raw: unknown): raw is Record<string, unknown> {
  const e = asObject(raw);
  if (!e) return false;
  for (const key of REQUIRED_TOP_LEVEL) {
    if (e[key] === undefined) return false;
  }
  const a = asObject(e.app);
  if (!a) return false;
  for (const key of REQUIRED_APP) {
    if (a[key] === undefined) return false;
  }
  return true;
}

function validateCriticalPayload(event: Record<string, unknown>): string | null {
  const eventName = event.eventName;
  if (typeof eventName !== "string") return "eventName must be a string";

  const item = asObject(event.item);
  const interaction = asObject(event.interaction);
  const impression = asObject(event.impression);
  const rank = asObject(event.rank);
  const filters = asObject(event.filters);
  const outbound = asObject(event.outbound);

  if (eventName === "deck_response") {
    if (!rank) return "deck_response requires rank";
    if (!hasString(rank.rankerRunId) || !hasString(rank.algorithmVersion)) {
      return "deck_response rank requires rankerRunId and algorithmVersion";
    }
    if (!Array.isArray(rank.itemIds) || !rank.itemIds.every(hasString)) {
      return "deck_response rank requires itemIds array";
    }
    if (rank.requestId !== undefined && !hasString(rank.requestId)) {
      return "deck_response rank.requestId must be a string";
    }
    if (rank.candidateCount !== undefined && !hasInteger(rank.candidateCount)) {
      return "deck_response rank.candidateCount must be an integer";
    }
    if (rank.rankWindow !== undefined && !hasInteger(rank.rankWindow)) {
      return "deck_response rank.rankWindow must be an integer";
    }
    if (
      rank.retrievalQueues !== undefined &&
      (!Array.isArray(rank.retrievalQueues) || !rank.retrievalQueues.every(hasString))
    ) {
      return "deck_response rank.retrievalQueues must be an array of strings";
    }
  }

  if (eventName === "card_impression_start") {
    if (!item || !hasString(item.itemId) || !hasNumber(item.positionInDeck)) {
      return "card_impression_start requires item.itemId and item.positionInDeck";
    }
    if (!impression || !hasString(impression.impressionId)) {
      return "card_impression_start requires impression.impressionId";
    }
  }

  if (eventName === "card_impression_end") {
    if (!item || !hasString(item.itemId) || !hasNumber(item.positionInDeck)) {
      return "card_impression_end requires item.itemId and item.positionInDeck";
    }
    if (
      !impression ||
      !hasString(impression.impressionId) ||
      !hasNumber(impression.visibleDurationMs) ||
      !hasString(impression.endReason)
    ) {
      return "card_impression_end requires impressionId, visibleDurationMs, and endReason";
    }
  }

  if (eventName === "swipe_left" || eventName === "swipe_right") {
    if (!item || !hasString(item.itemId) || !hasNumber(item.positionInDeck)) {
      return `${eventName} requires item.itemId and item.positionInDeck`;
    }
    if (!interaction || !hasString(interaction.gesture) || !hasString(interaction.direction)) {
      return `${eventName} requires interaction.gesture and interaction.direction`;
    }
  }

  if (eventName === "filters_apply") {
    if (!filters || asObject(filters.active) == null) {
      return "filters_apply requires filters.active";
    }
  }

  if (eventName === "outbound_click") {
    if (!item || !hasString(item.itemId)) return "outbound_click requires item.itemId";
    if (!outbound || !hasString(outbound.destinationDomain)) {
      return "outbound_click requires outbound.destinationDomain";
    }
  }

  return null;
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
    const payloadError = validateCriticalPayload(e);
    if (payloadError) {
      res.status(400).json({ error: `events[${i}] ${payloadError}` });
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
