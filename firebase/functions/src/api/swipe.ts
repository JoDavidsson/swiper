import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";

export async function swipePost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sessionId = body?.sessionId as string;
  const itemId = body?.itemId as string;
  const direction = body?.direction as string;
  const positionInDeck = (body?.positionInDeck as number) ?? 0;

  if (!sessionId || !itemId || !direction || !["left", "right"].includes(direction)) {
    res.status(400).json({ error: "sessionId, itemId, direction (left|right) required" });
    return;
  }

  const db = admin.firestore();
  const batch = db.batch();

  batch.set(db.collection("swipes").doc(), {
    sessionId,
    itemId,
    direction,
    positionInDeck,
    createdAt: FieldValue.serverTimestamp(),
  });

  batch.set(db.collection("events").doc(), {
    sessionId,
    eventType: direction === "right" ? "swipe_right" : "swipe_left",
    itemId,
    metadata: { positionInDeck },
    createdAt: FieldValue.serverTimestamp(),
  });

  if (direction === "right") {
    try {
      const itemSnap = await db.collection("items").doc(itemId).get();
      if (itemSnap.exists) {
        const data = itemSnap.data()!;
        const sessionRef = db.collection("anonSessions").doc(sessionId);
        const weightsRef = sessionRef.collection("preferenceWeights").doc("weights");

        // Atomic, merge-only increments to avoid read-modify-write races across fast swipes.
        const increments: Record<string, unknown> = {};
        const styleTags = Array.isArray(data.styleTags) ? data.styleTags : [];
        for (const t of styleTags) {
          if (typeof t === "string") increments[t] = FieldValue.increment(1);
        }
        const material = typeof data.material === "string" ? data.material : undefined;
        if (material) increments[`material:${material}`] = FieldValue.increment(1);
        const color = typeof data.colorFamily === "string" ? data.colorFamily : undefined;
        if (color) increments[`color:${color}`] = FieldValue.increment(1);
        const sizeClass = typeof data.sizeClass === "string" ? data.sizeClass : undefined;
        if (sizeClass) increments[`size:${sizeClass}`] = FieldValue.increment(1);

        if (Object.keys(increments).length > 0) {
          batch.set(weightsRef, increments, { merge: true });
        }
      }
    } catch (e) {
      console.warn("swipe: preferenceWeights update skipped", e);
      // Swipe and event are still committed below
    }
  }

  await batch.commit();
  // Use set with merge so we don't throw if the session doc was never created (e.g. emulator restart).
  await db.collection("anonSessions").doc(sessionId).set(
    { lastSeenAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  res.status(200).json({ ok: true });
}
