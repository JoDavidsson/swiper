import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";

export async function adminSourcesGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection("sources").orderBy("name").get();
  const sources = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  res.status(200).json({ sources });
}

export async function adminSourcesPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  if (!body) {
    res.status(400).json({ error: "Body required" });
    return;
  }
  const db = admin.firestore();
  const ref = await db.collection("sources").add({
    ...body,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  res.status(200).json({ id: ref.id });
}

export async function adminSourceGet(req: Request, res: Response, sourceId: string): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection("sources").doc(sourceId).get();
  if (!snap.exists) {
    res.status(404).json({ error: "Source not found" });
    return;
  }
  res.status(200).json({ id: snap.id, ...snap.data() });
}

export async function adminSourcePut(req: Request, res: Response, sourceId: string): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  if (!body) {
    res.status(400).json({ error: "Body required" });
    return;
  }
  const db = admin.firestore();
  await db.collection("sources").doc(sourceId).update({
    ...body,
    updatedAt: FieldValue.serverTimestamp(),
  });
  res.status(200).json({ ok: true });
}

export async function adminSourceDelete(req: Request, res: Response, sourceId: string): Promise<void> {
  const db = admin.firestore();
  await db.collection("sources").doc(sourceId).delete();
  res.status(200).json({ ok: true });
}
