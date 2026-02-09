import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";
import { toPriceBucket } from "../ranker/scoreItem";

const RIGHT_SWIPE_WEIGHT_DELTA = 1;
const LEFT_SWIPE_WEIGHT_DELTA = -0.35;

function normalizeToken(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return normalized.length > 0 ? normalized : null;
}

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
    const likeId = `${sessionId}_${itemId}`;
    batch.set(
      db.collection("likes").doc(likeId),
      { sessionId, itemId, createdAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    batch.set(
      db.collection("anonSessions").doc(sessionId).collection("likes").doc(itemId),
      { addedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }

  try {
    let itemSnap = await db.collection("items").doc(itemId).get();
    if (!itemSnap.exists) {
      itemSnap = await db.collection("goldItems").doc(itemId).get();
    }

    if (itemSnap.exists) {
      const data = itemSnap.data()!;
      const sessionRef = db.collection("anonSessions").doc(sessionId);
      const weightsRef = sessionRef.collection("preferenceWeights").doc("weights");
      const delta = direction === "right" ? RIGHT_SWIPE_WEIGHT_DELTA : LEFT_SWIPE_WEIGHT_DELTA;
      const counts: Record<string, number> = {};
      const addCount = (key: string, amount: number = 1) => {
        counts[key] = (counts[key] || 0) + amount;
      };

      const styleTags = Array.isArray(data.styleTags) ? data.styleTags : [];
      for (const t of styleTags) {
        const normalized = normalizeToken(t);
        if (normalized) addCount(normalized);
      }

      const material = normalizeToken(data.material);
      if (material) addCount(`material:${material}`);

      const color = normalizeToken(data.colorFamily);
      if (color) addCount(`color:${color}`);

      const sizeClass = normalizeToken(data.sizeClass);
      if (sizeClass) addCount(`size:${sizeClass}`);

      const brand = normalizeToken(data.brand);
      if (brand) addCount(`brand:${brand}`);

      const deliveryComplexity = normalizeToken(data.deliveryComplexity);
      if (deliveryComplexity) addCount(`delivery:${deliveryComplexity}`);

      const condition = normalizeToken(data.newUsed);
      if (condition) addCount(`condition:${condition}`);

      const ecoTags = Array.isArray(data.ecoTags) ? data.ecoTags : [];
      for (const ecoTag of ecoTags) {
        const normalized = normalizeToken(ecoTag);
        if (normalized) addCount(`eco:${normalized}`);
      }

      if (data.smallSpaceFriendly === true) addCount("feature:small_space");
      if (data.modular === true) addCount("feature:modular");

      // Sub-category signal (e.g., "subcat:3_seater", "subcat:corner_sofa")
      const subCategory = normalizeToken(data.subCategory);
      if (subCategory) addCount(`subcat:${subCategory}`);

      // Room-type signals (e.g., "room:living_room", "room:outdoor")
      const roomTypes = Array.isArray(data.roomTypes) ? data.roomTypes : [];
      for (const roomType of roomTypes) {
        const normalized = normalizeToken(roomType);
        if (normalized) addCount(`room:${normalized}`);
      }

      const priceAmount = typeof data.priceAmount === "number" ? data.priceAmount : undefined;
      const priceBucket = toPriceBucket(priceAmount);
      if (priceBucket) addCount(`price_bucket:${priceBucket}`);

      // Rich furniture spec signals
      const seatCount = data.seatCount;
      if (typeof seatCount === "number" && seatCount > 0 && seatCount <= 20) {
        addCount(`seats:${seatCount}`);
      }

      const coverMaterial = normalizeToken(data.coverMaterial);
      if (coverMaterial) addCount(`cover:${coverMaterial}`);

      const frameMaterial = normalizeToken(data.frameMaterial);
      if (frameMaterial) addCount(`frame:${frameMaterial}`);

      const legMaterial = normalizeToken(data.legMaterial);
      if (legMaterial) addCount(`legs:${legMaterial}`);

      const cushionFilling = normalizeToken(data.cushionFilling);
      if (cushionFilling) addCount(`filling:${cushionFilling}`);

      const updates: Record<string, ReturnType<typeof FieldValue.increment>> = {};
      for (const [key, amount] of Object.entries(counts)) {
        updates[key] = FieldValue.increment(amount * delta);
      }
      if (Object.keys(updates).length > 0) {
        batch.set(weightsRef, updates, { merge: true });
      }
    }
  } catch (e) {
    console.warn("swipe: preferenceWeights update skipped", e);
    // Swipe, event, and likes are still committed below
  }

  await batch.commit();
  // Use set with merge so we don't throw if the session doc was never created (e.g. emulator restart).
  await db.collection("anonSessions").doc(sessionId).set(
    { lastSeenAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  res.status(200).json({ ok: true });
}
