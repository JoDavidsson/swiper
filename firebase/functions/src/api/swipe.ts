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
        const weightsSnap = await weightsRef.get();
        const current = (weightsSnap.data() || {}) as Record<string, number>;

        const styleTags = Array.isArray(data.styleTags) ? data.styleTags : [];
        for (const t of styleTags) {
          if (typeof t === "string") current[t] = (current[t] || 0) + 1;
        }
        const material = typeof data.material === "string" ? data.material : undefined;
        if (material) current[`material:${material}`] = (current[`material:${material}`] || 0) + 1;
        const color = typeof data.colorFamily === "string" ? data.colorFamily : undefined;
        if (color) current[`color:${color}`] = (current[`color:${color}`] || 0) + 1;
        const sizeClass = typeof data.sizeClass === "string" ? data.sizeClass : undefined;
        if (sizeClass) current[`size:${sizeClass}`] = (current[`size:${sizeClass}`] || 0) + 1;

        batch.set(weightsRef, current);
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
