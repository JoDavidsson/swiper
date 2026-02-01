import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { nanoid } from "nanoid";

const DEFAULT_LIMIT = 20;
const ALGORITHM_VERSION = "preference_weights_v1";

export async function deckGet(req: Request, res: Response): Promise<void> {
  const sessionId = req.query.sessionId as string;
  const limit = Math.min(parseInt(String(req.query.limit || DEFAULT_LIMIT), 10) || DEFAULT_LIMIT, 50);
  const filtersJson = req.query.filters as string | undefined;

  if (!sessionId) {
    res.status(400).json({ error: "sessionId required" });
    return;
  }

  const rankerRunId = nanoid(12);
  const db = admin.firestore();

  const [swipesSnap, _likesSnap, sessionSnap] = await Promise.all([
    db.collection("swipes").where("sessionId", "==", sessionId).orderBy("createdAt", "desc").limit(500).get(),
    db.collection("likes").where("sessionId", "==", sessionId).get(),
    db.collection("anonSessions").doc(sessionId).get(),
  ]);

  const seenItemIds = new Set<string>();
  swipesSnap.docs.forEach((d) => seenItemIds.add((d.data().itemId as string) || ""));

  const filters = filtersJson ? (JSON.parse(filtersJson) as Record<string, unknown>) : {};
  const itemsSnap = await db
    .collection("items")
    .where("isActive", "==", true)
    .orderBy("lastUpdatedAt", "desc")
    .limit(limit * 5)
    .get();

  const items: admin.firestore.DocumentSnapshot[] = [];
  for (const doc of itemsSnap.docs) {
    if (items.length >= limit) break;
    if (seenItemIds.has(doc.id)) continue;
    const d = doc.data();
    if (filters.sizeClass && d.sizeClass !== filters.sizeClass) continue;
    if (filters.colorFamily && d.colorFamily !== filters.colorFamily) continue;
    if (filters.newUsed && d.newUsed !== filters.newUsed) continue;
    items.push(doc);
  }

  const preferenceWeights = sessionSnap.exists ? (sessionSnap.data()?.preferenceWeights as Record<string, number> | undefined) || {} : {};
  items.sort((a, b) => {
    const ad = a.data()!;
    const bd = b.data()!;
    const aScore = scoreItem(ad, preferenceWeights);
    const bScore = scoreItem(bd, preferenceWeights);
    return bScore - aScore;
  });

  const sliced = items.slice(0, limit);
  const result = sliced.map((doc) => ({ id: doc.id, ...doc.data() }));
  const itemScores: Record<string, number> = {};
  sliced.forEach((doc) => {
    const d = doc.data()!;
    itemScores[doc.id] = scoreItem(d, preferenceWeights);
  });

  res.status(200).json({
    items: result,
    rank: { rankerRunId, algorithmVersion: ALGORITHM_VERSION },
    itemScores,
  });
}

function scoreItem(data: admin.firestore.DocumentData, weights: Record<string, number>): number {
  let score = 0;
  const tags = (data.styleTags as string[]) || [];
  tags.forEach((t: string) => {
    score += weights[t] ?? 0;
  });
  const material = data.material as string | undefined;
  if (material) score += weights[`material:${material}`] ?? 0;
  const color = data.colorFamily as string | undefined;
  if (color) score += weights[`color:${color}`] ?? 0;
  const sizeClass = data.sizeClass as string | undefined;
  if (sizeClass) score += weights[`size:${sizeClass}`] ?? 0;
  return score;
}
