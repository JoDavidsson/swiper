import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function likesGet(req: Request, res: Response): Promise<void> {
  const sessionId = req.query.sessionId as string;
  if (!sessionId) {
    res.status(400).json({ error: "sessionId required" });
    return;
  }

  const db = admin.firestore();
  const likesSnap = await db.collection("likes").where("sessionId", "==", sessionId).orderBy("createdAt", "desc").get();
  const itemIds = likesSnap.docs.map((d) => d.data().itemId as string).filter(Boolean);

  const items: admin.firestore.DocumentData[] = [];
  for (const itemId of itemIds) {
    const itemSnap = await db.collection("items").doc(itemId).get();
    if (itemSnap.exists) {
      items.push({ id: itemSnap.id, ...itemSnap.data() });
    }
  }

  res.status(200).json({ items });
}
