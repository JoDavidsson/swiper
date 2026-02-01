import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function itemsBatchGet(req: Request, res: Response): Promise<void> {
  const idsParam = req.query.ids as string;
  if (!idsParam) {
    res.status(400).json({ error: "ids required (comma-separated)" });
    return;
  }
  const ids = idsParam.split(",").map((s) => s.trim()).filter(Boolean);
  if (ids.length === 0 || ids.length > 20) {
    res.status(400).json({ error: "ids must be 1-20 item ids" });
    return;
  }

  const db = admin.firestore();
  const items: admin.firestore.DocumentData[] = [];
  for (const id of ids) {
    const snap = await db.collection("items").doc(id).get();
    if (snap.exists) {
      items.push({ id: snap.id, ...snap.data() });
    }
  }

  res.status(200).json({ items });
}
