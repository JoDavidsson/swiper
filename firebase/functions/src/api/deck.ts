import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { applyExploration, PreferenceWeightsRanker, PersonalPlusPersonaRanker } from "../ranker";
import type { ItemCandidate, PersonaSignals, SessionContext } from "../ranker";
import { getPersonaSignals } from "../scheduled/persona_aggregation";

const DEFAULT_LIMIT = 20;

/** Default boost value for onboarding pick attributes (cold-start) */
const ONBOARDING_PICK_BOOST = 3;

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

  const [swipesSnap, _likesSnap, sessionSnap, weightsSnap, onboardingPicksSnap] = await Promise.all([
    db.collection("swipes").where("sessionId", "==", sessionId).orderBy("createdAt", "desc").limit(500).get(),
    db.collection("likes").where("sessionId", "==", sessionId).get(),
    db.collection("anonSessions").doc(sessionId).get(),
    db.collection("anonSessions").doc(sessionId).collection("preferenceWeights").doc("weights").get(),
    db.collection("onboardingPicks").doc(sessionId).get(),
  ]);

  // Start with existing preference weights
  let preferenceWeights = weightsSnap.exists
    ? (weightsSnap.data() as Record<string, number>) || {}
    : (sessionSnap.exists ? (sessionSnap.data()?.preferenceWeights as Record<string, number> | undefined) : undefined) || {};

  // Cold-start: if user has onboarding picks but few/no swipes, boost attributes from picked items
  const hasLimitedHistory = swipesSnap.size < 5;
  if (hasLimitedHistory && onboardingPicksSnap.exists) {
    const picksData = onboardingPicksSnap.data();
    const extractedAttributes = picksData?.extractedAttributes as {
      styleTags?: string[];
      materials?: string[];
      colorFamilies?: string[];
    } | undefined;

    if (extractedAttributes) {
      // Merge onboarding pick attributes as default preference weights (cold-start fallback)
      const coldStartWeights: Record<string, number> = {};

      // Add style tags
      if (Array.isArray(extractedAttributes.styleTags)) {
        for (const tag of extractedAttributes.styleTags) {
          coldStartWeights[tag] = ONBOARDING_PICK_BOOST;
        }
      }

      // Add materials with material: prefix
      if (Array.isArray(extractedAttributes.materials)) {
        for (const material of extractedAttributes.materials) {
          coldStartWeights[`material:${material}`] = ONBOARDING_PICK_BOOST;
        }
      }

      // Add color families with color: prefix
      if (Array.isArray(extractedAttributes.colorFamilies)) {
        for (const color of extractedAttributes.colorFamilies) {
          coldStartWeights[`color:${color}`] = ONBOARDING_PICK_BOOST;
        }
      }

      // Merge: existing weights take precedence over cold-start (user behavior > onboarding)
      preferenceWeights = { ...coldStartWeights, ...preferenceWeights };
    }
  }

  const seenItemIds = new Set<string>();
  swipesSnap.docs.forEach((d) => seenItemIds.add((d.data().itemId as string) || ""));

  let filters: Record<string, unknown> = {};
  if (filtersJson) {
    try {
      filters = JSON.parse(filtersJson) as Record<string, unknown>;
    } catch (e) {
      res.status(400).json({ error: "filters must be valid JSON" });
      return;
    }
  }

  // Apply budget filter from onboarding picks if available and no explicit price filter is set
  let budgetMin: number | undefined;
  let budgetMax: number | undefined;
  if (onboardingPicksSnap.exists && !filters.priceMin && !filters.priceMax) {
    const picksData = onboardingPicksSnap.data();
    if (typeof picksData?.budgetMin === "number") {
      budgetMin = picksData.budgetMin;
    }
    if (typeof picksData?.budgetMax === "number") {
      budgetMax = picksData.budgetMax;
    }
  }
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
    // Apply budget filter from onboarding picks
    const price = d.priceAmount as number | undefined;
    if (price != null) {
      if (budgetMin != null && price < budgetMin) continue;
      if (budgetMax != null && price > budgetMax) continue;
    }
    candidateDocs.push(doc);
  }

  const candidates: ItemCandidate[] = candidateDocs.map((doc) => ({ id: doc.id, ...doc.data() } as ItemCandidate));

  const sessionContext: SessionContext = { preferenceWeights };

  // Attempt to get persona signals for collaborative filtering
  let personaSignals: PersonaSignals | undefined;
  let usePersonaRanker = false;

  if (onboardingPicksSnap.exists) {
    const picksData = onboardingPicksSnap.data();
    const pickHash = picksData?.pickHash as string | undefined;

    if (pickHash) {
      const itemScoresFromSimilar = await getPersonaSignals(pickHash);
      if (itemScoresFromSimilar && Object.keys(itemScoresFromSimilar).length > 0) {
        personaSignals = {
          itemScoresFromSimilarSessions: itemScoresFromSimilar,
          popularAmongSimilar: Object.keys(itemScoresFromSimilar)
            .sort((a, b) => (itemScoresFromSimilar[b] || 0) - (itemScoresFromSimilar[a] || 0))
            .slice(0, 20),
        };
        usePersonaRanker = true;
      }
    }
  }

  // Use persona ranker if we have collaborative signals, otherwise use preference weights only
  const rankResult = usePersonaRanker
    ? PersonalPlusPersonaRanker.rank(sessionContext, candidates, { limit }, personaSignals)
    : PreferenceWeightsRanker.rank(sessionContext, candidates, { limit });

  const explorationRate = Math.min(0.1, Math.max(0, parseFloat(String(process.env.RANKER_EXPLORATION_RATE || "0")) || 0));
  const explorationSeed =
    process.env.RANKER_EXPLORATION_SEED != null
      ? parseInt(String(process.env.RANKER_EXPLORATION_SEED), 10)
      : hashSessionId(sessionId);

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
  const variantBase = usePersonaRanker ? "personal_plus_persona" : "personal_only";
  const variant = explorationRate > 0 ? `${variantBase}_exploration_${Math.round(explorationRate * 100)}` : variantBase;

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
