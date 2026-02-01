import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { nanoid } from "nanoid";

export async function shortlistsCreatePost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sessionId = body?.sessionId as string;
  const itemIds = (body?.itemIds as string[]) || [];

  if (!sessionId) {
    res.status(400).json({ error: "sessionId required" });
    return;
  }

  const shareToken = nanoid(12);
  const db = admin.firestore();

  const shortlistRef = db.collection("shortlists").doc();
  const batch = db.batch();

  batch.set(shortlistRef, {
    ownerSessionId: sessionId,
    shareToken,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  itemIds.forEach((itemId) => {
    batch.set(shortlistRef.collection("items").doc(itemId), {
      addedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();

  await db.collection("events").add({
    sessionId,
    eventType: "share_shortlist",
    metadata: { shortlistId: shortlistRef.id },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  res.status(200).json({ shortlistId: shortlistRef.id, shareToken });
}

export async function shortlistsByTokenGet(req: Request, res: Response, shareToken: string): Promise<void> {
  if (!shareToken) {
    res.status(400).json({ error: "shareToken required" });
    return;
  }

  const db = admin.firestore();
  const shortlistsSnap = await db.collection("shortlists").where("shareToken", "==", shareToken).limit(1).get();

  if (shortlistsSnap.empty) {
    res.status(404).json({ error: "Shortlist not found" });
    return;
  }

  const shortlistDoc = shortlistsSnap.docs[0];
  const shortlistData = shortlistDoc.data();
  const itemsSnap = await shortlistDoc.ref.collection("items").get();
  const itemIds = itemsSnap.docs.map((d) => d.id);

  const items: admin.firestore.DocumentData[] = [];
  for (const itemId of itemIds) {
    const itemSnap = await db.collection("items").doc(itemId).get();
    if (itemSnap.exists) {
      items.push({ id: itemSnap.id, ...itemSnap.data() });
    }
  }

  res.status(200).json({
    shortlistId: shortlistDoc.id,
    shareToken: shortlistData.shareToken,
    createdAt: shortlistData.createdAt,
    itemIds,
    items,
  });
}
