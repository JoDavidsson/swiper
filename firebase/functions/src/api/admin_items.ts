import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

export async function adminItemsGet(req: Request, res: Response): Promise<void> {
  const limitParam = req.query.limit as string | undefined;
  const limit = Math.min(
    parseInt(limitParam || String(DEFAULT_LIMIT), 10) || DEFAULT_LIMIT,
    MAX_LIMIT
  );

  const db = admin.firestore();
  const snap = await db
    .collection("items")
    .orderBy("lastUpdatedAt", "desc")
    .limit(limit)
    .get();

  const items = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  res.status(200).json({ items });
}
