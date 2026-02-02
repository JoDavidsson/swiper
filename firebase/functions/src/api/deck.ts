import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { applyExploration, PreferenceWeightsRanker } from "../ranker";
import type { ItemCandidate, SessionContext } from "../ranker";

const DEFAULT_LIMIT = 20;

function hashSessionId(sessionId: string): number {
  let h = 0;
  for (let i = 0; i < sessionId.length; i++) {
    h = (h << 5) - h + sessionId.charCodeAt(i);
    h = h & h;
  }
  return Math.abs(h);
}

const MAX_LIMIT = parseInt(String(process.env.DECK_RESPONSE_LIMIT || "500"), 10) || 500;

export async function deckGet(req: Request, res: Response): Promise<void> {
  const sessionId = req.query.sessionId as string;
  const requested = parseInt(String(req.query.limit || DEFAULT_LIMIT), 10) || DEFAULT_LIMIT;
  const limit = Math.min(Math.max(0, requested), MAX_LIMIT);
  const filtersJson = req.query.filters as string | undefined;

  if (!sessionId) {
    res.status(400).json({ error: "sessionId required" });
    return;
  }

  const db = admin.firestore();

  const [swipesSnap, _likesSnap, sessionSnap, weightsSnap] = await Promise.all([
    db.collection("swipes").where("sessionId", "==", sessionId).orderBy("createdAt", "desc").limit(500).get(),
    db.collection("likes").where("sessionId", "==", sessionId).get(),
    db.collection("anonSessions").doc(sessionId).get(),
    db.collection("anonSessions").doc(sessionId).collection("preferenceWeights").doc("weights").get(),
  ]);

  const preferenceWeights = weightsSnap.exists
    ? (weightsSnap.data() as Record<string, number>) || {}
    : (sessionSnap.exists ? (sessionSnap.data()?.preferenceWeights as Record<string, number> | undefined) : undefined) || {};

  const seenItemIds = new Set<string>();
  swipesSnap.docs.forEach((d) => seenItemIds.add((d.data().itemId as string) || ""));

  const filters = filtersJson ? (JSON.parse(filtersJson) as Record<string, unknown>) : {};
  const itemsFetchLimit =
    process.env.DECK_ITEMS_FETCH_LIMIT != null
      ? parseInt(String(process.env.DECK_ITEMS_FETCH_LIMIT), 10) || limit * 5
      : limit * 5;
  const candidateCap =
    process.env.DECK_CANDIDATE_CAP != null
      ? parseInt(String(process.env.DECK_CANDIDATE_CAP), 10) || limit * 2
      : limit * 2;

  const itemsSnap = await db
    .collection("items")
    .where("isActive", "==", true)
    .orderBy("lastUpdatedAt", "desc")
    .limit(itemsFetchLimit)
    .get();

  const candidateDocs: admin.firestore.DocumentSnapshot[] = [];
  for (const doc of itemsSnap.docs) {
    if (candidateDocs.length >= candidateCap) break;
    if (seenItemIds.has(doc.id)) continue;
    const d = doc.data();
    if (filters.sizeClass && d.sizeClass !== filters.sizeClass) continue;
    if (filters.colorFamily && d.colorFamily !== filters.colorFamily) continue;
    if (filters.newUsed && d.newUsed !== filters.newUsed) continue;
    candidateDocs.push(doc);
  }

  const candidates: ItemCandidate[] = candidateDocs.map((doc) => ({ id: doc.id, ...doc.data() } as ItemCandidate));

  const sessionContext: SessionContext = { preferenceWeights };
  const rankResult = PreferenceWeightsRanker.rank(sessionContext, candidates, { limit });

  const explorationRate = Math.min(0.1, Math.max(0, parseFloat(String(process.env.RANKER_EXPLORATION_RATE || "0")) || 0));
  const explorationSeed = process.env.RANKER_EXPLORATION_SEED != null ? parseInt(String(process.env.RANKER_EXPLORATION_SEED), 10) : undefined;

  const exploredIds = applyExploration(rankResult.itemIds, candidates, {
    explorationRate,
    limit,
    seed: explorationSeed,
  });

  const idToCandidate = new Map<string | number, ItemCandidate>();
  candidates.forEach((c) => idToCandidate.set(c.id, c));

  const items = exploredIds
    .map((id) => idToCandidate.get(id))
    .filter((c): c is ItemCandidate => c != null)
    .map((c) => ({ ...c }));

  const itemScores: Record<string, number> = {};
  exploredIds.forEach((id) => {
    if (rankResult.itemScores[id] != null) itemScores[id] = rankResult.itemScores[id];
  });

  const variantBucket = hashSessionId(sessionId) % 100;
  const variant = explorationRate > 0 ? `personal_only_exploration_${Math.round(explorationRate * 100)}` : "personal_only";

  res.status(200).json({
    items,
    rank: {
      rankerRunId: rankResult.runId,
      algorithmVersion: rankResult.algorithmVersion,
      variant,
      variantBucket,
    },
    itemScores,
  });
}
