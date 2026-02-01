import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function eventsPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sessionId = body?.sessionId as string;
  const eventType = body?.eventType as string;
  const itemId = body?.itemId as string | undefined;
  const metadata = body?.metadata as Record<string, unknown> | undefined;

  if (!sessionId || !eventType) {
    res.status(400).json({ error: "sessionId and eventType required" });
    return;
  }

  const db = admin.firestore();
  await db.collection("events").add({
    sessionId,
    eventType,
    itemId: itemId || null,
    metadata: metadata || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  res.status(200).json({ ok: true });
}
