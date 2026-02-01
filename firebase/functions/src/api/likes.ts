import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function likesTogglePost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sessionId = body?.sessionId as string;
  const itemId = body?.itemId as string;

  if (!sessionId || !itemId) {
    res.status(400).json({ error: "sessionId and itemId required" });
    return;
  }

  const db = admin.firestore();
  const likeQuery = await db.collection("likes").where("sessionId", "==", sessionId).where("itemId", "==", itemId).limit(1).get();

  let liked: boolean;
  if (likeQuery.empty) {
    await db.collection("likes").add({
      sessionId,
      itemId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection("anonSessions").doc(sessionId).collection("likes").doc(itemId).set({
      addedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection("events").add({
      sessionId,
      eventType: "add_like",
      itemId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    liked = true;
  } else {
    const doc = likeQuery.docs[0];
    await doc.ref.delete();
    await db.collection("anonSessions").doc(sessionId).collection("likes").doc(itemId).delete();
    await db.collection("events").add({
      sessionId,
      eventType: "remove_like",
      itemId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    liked = false;
  }

  await db.collection("anonSessions").doc(sessionId).update({
    lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  res.status(200).json({ liked });
}
