import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { nanoid } from "nanoid";

export async function sessionPost(req: Request, res: Response): Promise<void> {
  const sessionId = nanoid(24);
  const db = admin.firestore();

  await db.collection("anonSessions").doc(sessionId).set({
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  res.status(200).json({ sessionId });
}
