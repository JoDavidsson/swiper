import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { applyExploration, PreferenceWeightsRanker, PersonalPlusPersonaRanker } from "../ranker";
import type { ItemCandidate, PersonaSignals, SessionContext } from "../ranker";
import { getPersonaSignals } from "../scheduled/persona_aggregation";

const DEFAULT_LIMIT = 30;
const MIN_ITEMS_FETCH_LIMIT = 240;
const MIN_CANDIDATE_CAP = 120;
const MIN_RANK_WINDOW = 120;
const MIN_SOURCE_FETCH = 60;
const MAX_PERSONA_RETRIEVAL_IDS = 120;

/** Default boost value for onboarding pick attributes (cold-start) */
const ONBOARDING_PICK_BOOST = 3;

const MAX_LIMIT = parseInt(String(process.env.DECK_RESPONSE_LIMIT || "500"), 10) || 500;

type QueueName =
  | "fresh_promoted"
  | "fresh_catalog"
  | "preference_match"
  | "persona_similar"
  | "long_tail"
  | "serendipity";

const QUEUE_ORDER: QueueName[] = [
  "preference_match",
  "persona_similar",
  "fresh_promoted",
  "fresh_catalog",
  "long_tail",
  "serendipity",
];

/**
 * Pass-2 backfill order when quota pass cannot fill candidateCap.
 * Keep promoted near the end so overflow does not collapse variety.
 */
const BACKFILL_QUEUE_ORDER: QueueName[] = [
  "preference_match",
  "persona_similar",
  "fresh_catalog",
  "long_tail",
  "serendipity",
  "fresh_promoted",
];

function hashSessionId(sessionId: string): number {
  let h = 0;
  for (let i = 0; i < sessionId.length; i++) {
    h = (h << 5) - h + sessionId.charCodeAt(i);
    h = h & h;
  }
  return Math.abs(h);
}

function createDeckRequestId(sessionId: string): string {
  const now = Date.now().toString(36);
  const sid = hashSessionId(sessionId).toString(36).slice(0, 6);
  return `deck_${now}_${sid}`;
}

function asFiniteNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function normalizeToken(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

function getStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((v) => normalizeToken(v)).filter((v): v is string => v != null);
}

function toPriceBucket(amount: unknown): string | null {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount < 0) return null;
  if (amount <= 3000) return "budget";
  if (amount <= 8000) return "affordable";
  if (amount <= 15000) return "mid";
  if (amount <= 30000) return "premium";
  return "luxury";
}

function getTopPositivePreferenceKeys(weights: Record<string, number>, maxKeys: number): string[] {
  return Object.entries(weights)
    .filter(([, value]) => typeof value === "number" && value > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, maxKeys)
    .map(([key]) => key);
}

function preferenceOverlapScore(data: Record<string, unknown> | undefined, preferredKeys: Set<string>): number {
  if (!data || preferredKeys.size === 0) return 0;

  let overlap = 0;

  const styleTags = getStringArray(data.styleTags);
  for (const tag of styleTags) {
    if (preferredKeys.has(tag)) overlap += 2;
  }

  const material = normalizeToken(data.material);
  if (material && preferredKeys.has(`material:${material}`)) overlap += 2;

  const color = normalizeToken(data.colorFamily);
  if (color && preferredKeys.has(`color:${color}`)) overlap += 2;

  const sizeClass = normalizeToken(data.sizeClass);
  if (sizeClass && preferredKeys.has(`size:${sizeClass}`)) overlap += 1;

  const brand = normalizeToken(data.brand);
  if (brand && preferredKeys.has(`brand:${brand}`)) overlap += 1;

  const delivery = normalizeToken(data.deliveryComplexity);
  if (delivery && preferredKeys.has(`delivery:${delivery}`)) overlap += 1;

  const condition = normalizeToken(data.newUsed);
  if (condition && preferredKeys.has(`condition:${condition}`)) overlap += 1;

  const ecoTags = getStringArray(data.ecoTags);
  for (const ecoTag of ecoTags) {
    if (preferredKeys.has(`eco:${ecoTag}`)) overlap += 1;
  }

  if (data.smallSpaceFriendly === true && preferredKeys.has("feature:small_space")) {
    overlap += 1;
  }
  if (data.modular === true && preferredKeys.has("feature:modular")) {
    overlap += 1;
  }

  const priceBucket = toPriceBucket(data.priceAmount);
  if (priceBucket && preferredKeys.has(`price_bucket:${priceBucket}`)) overlap += 1;

  return overlap;
}

function interleaveDocs(
  sources: Array<admin.firestore.DocumentSnapshot[]>,
  maxItems: number
): admin.firestore.DocumentSnapshot[] {
  const output: admin.firestore.DocumentSnapshot[] = [];
  const cursors = sources.map(() => 0);
  while (output.length < maxItems) {
    let madeProgress = false;
    for (let i = 0; i < sources.length; i++) {
      if (output.length >= maxItems) break;
      const source = sources[i];
      const cursor = cursors[i];
      if (cursor >= source.length) continue;
      output.push(source[cursor]);
      cursors[i] += 1;
      madeProgress = true;
    }
    if (!madeProgress) break;
  }
  return output;
}

function buildQueueTargets(candidateCap: number, hasPreferences: boolean, hasPersona: boolean): Record<QueueName, number> {
  const baseRatios: Record<QueueName, number> = hasPreferences
    ? {
        fresh_promoted: 0.22,
        fresh_catalog: 0.18,
        preference_match: 0.30,
        persona_similar: hasPersona ? 0.20 : 0,
        long_tail: 0.07,
        serendipity: 0.03,
      }
    : {
        fresh_promoted: 0.24,
        fresh_catalog: 0.33,
        preference_match: 0,
        persona_similar: hasPersona ? 0.27 : 0,
        long_tail: 0.28,
        serendipity: 0.15,
      };

  const ratioSum = Object.values(baseRatios).reduce((sum, ratio) => sum + ratio, 0) || 1;

  const targets: Record<QueueName, number> = {
    fresh_promoted: 0,
    fresh_catalog: 0,
    preference_match: 0,
    persona_similar: 0,
    long_tail: 0,
    serendipity: 0,
  };

  for (const queue of QUEUE_ORDER) {
    const ratio = baseRatios[queue] / ratioSum;
    if (ratio <= 0) continue;
    targets[queue] = Math.max(1, Math.floor(candidateCap * ratio));
  }

  const initial = Object.values(targets).reduce((sum, value) => sum + value, 0);
  let remaining = Math.max(0, candidateCap - initial);
  let cursor = 0;
  while (remaining > 0) {
    const queue = QUEUE_ORDER[cursor % QUEUE_ORDER.length];
    if (baseRatios[queue] > 0) {
      targets[queue] += 1;
      remaining -= 1;
    }
    cursor += 1;
  }

  return targets;
}

async function getDocsByIds(
  db: admin.firestore.Firestore,
  collectionName: string,
  ids: string[]
): Promise<admin.firestore.DocumentSnapshot[]> {
  if (ids.length === 0) return [];
  const refs = ids.map((id) => db.collection(collectionName).doc(id));
  return db.getAll(...refs);
}

export async function deckGet(req: Request, res: Response): Promise<void> {
  const sessionId = req.query.sessionId as string;
  const requested = parseInt(String(req.query.limit || DEFAULT_LIMIT), 10) || DEFAULT_LIMIT;
  const limit = Math.min(Math.max(0, requested), MAX_LIMIT);
  const filtersJson = req.query.filters as string | undefined;
  const debugMode = req.query.debug === "true";
  const providedRequestId = typeof req.query.requestId === "string" ? req.query.requestId.trim() : "";
  const requestId = providedRequestId.length > 0 ? providedRequestId : createDeckRequestId(sessionId || "unknown");

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
      const coldStartWeights: Record<string, number> = {};

      if (Array.isArray(extractedAttributes.styleTags)) {
        for (const tag of extractedAttributes.styleTags) {
          coldStartWeights[tag] = ONBOARDING_PICK_BOOST;
        }
      }

      if (Array.isArray(extractedAttributes.materials)) {
        for (const material of extractedAttributes.materials) {
          coldStartWeights[`material:${material}`] = ONBOARDING_PICK_BOOST;
        }
      }

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

  const sizeClassFilter = typeof filters.sizeClass === "string" ? filters.sizeClass : undefined;
  const colorFamilyFilter = typeof filters.colorFamily === "string" ? filters.colorFamily : undefined;
  const newUsedFilter = typeof filters.newUsed === "string" ? filters.newUsed : undefined;
  const explicitPriceMin = asFiniteNumber(filters.priceMin);
  const explicitPriceMax = asFiniteNumber(filters.priceMax);

  // Apply budget filter from onboarding picks if available and no explicit price filter is set
  let budgetMin: number | undefined;
  let budgetMax: number | undefined;
  if (onboardingPicksSnap.exists && explicitPriceMin == null && explicitPriceMax == null) {
    const picksData = onboardingPicksSnap.data();
    if (typeof picksData?.budgetMin === "number") budgetMin = picksData.budgetMin;
    if (typeof picksData?.budgetMax === "number") budgetMax = picksData.budgetMax;
  }
  const minPriceFilter = explicitPriceMin ?? budgetMin;
  const maxPriceFilter = explicitPriceMax ?? budgetMax;

  const dynamicFetchLimit = Math.max(limit * 18, MIN_ITEMS_FETCH_LIMIT);
  const dynamicCandidateCap = Math.max(limit * 10, MIN_CANDIDATE_CAP);
  const itemsFetchLimit =
    process.env.DECK_ITEMS_FETCH_LIMIT != null
      ? parseInt(String(process.env.DECK_ITEMS_FETCH_LIMIT), 10) || dynamicFetchLimit
      : dynamicFetchLimit;
  const candidateCap =
    process.env.DECK_CANDIDATE_CAP != null
      ? parseInt(String(process.env.DECK_CANDIDATE_CAP), 10) || dynamicCandidateCap
      : dynamicCandidateCap;
  const sourceFetchLimit = Math.max(MIN_SOURCE_FETCH, Math.floor(itemsFetchLimit * 0.7));
  const secondaryFetchLimit = Math.max(MIN_SOURCE_FETCH, Math.floor(itemsFetchLimit * 0.55));

  // Prepare collaborative signals first, then use top persona IDs as one retrieval queue.
  let personaSignals: PersonaSignals | undefined;
  let usePersonaRanker = false;
  let personaCandidateIds: string[] = [];
  if (onboardingPicksSnap.exists) {
    const picksData = onboardingPicksSnap.data();
    const pickHash = picksData?.pickHash as string | undefined;

    if (pickHash) {
      const itemScoresFromSimilar = await getPersonaSignals(pickHash);
      if (itemScoresFromSimilar && Object.keys(itemScoresFromSimilar).length > 0) {
        const sortedPersonaIds = Object.keys(itemScoresFromSimilar).sort(
          (a, b) => (itemScoresFromSimilar[b] || 0) - (itemScoresFromSimilar[a] || 0)
        );
        personaSignals = {
          itemScoresFromSimilarSessions: itemScoresFromSimilar,
          popularAmongSimilar: sortedPersonaIds.slice(0, Math.max(20, Math.min(MAX_PERSONA_RETRIEVAL_IDS * 2, limit * 12))),
        };
        personaCandidateIds = sortedPersonaIds.slice(0, MAX_PERSONA_RETRIEVAL_IDS);
        usePersonaRanker = true;
      }
    }
  }

  // Multi-queue retrieval sources: promoted feed + recency feed (+ persona item IDs).
  const useGold = process.env.DECK_USE_GOLD !== "false";
  const [goldSnapOrNull, catalogSnap] = await Promise.all([
    useGold
      ? db
          .collection("goldItems")
          .where("isActive", "==", true)
          .orderBy("promotedAt", "desc")
          .limit(sourceFetchLimit)
          .get()
      : Promise.resolve(null),
    db
      .collection("items")
      .where("isActive", "==", true)
      .orderBy("lastUpdatedAt", "desc")
      .limit(useGold ? secondaryFetchLimit : itemsFetchLimit)
      .get(),
  ]);

  const freshPromotedDocs = goldSnapOrNull?.docs ?? [];
  const freshCatalogDocs = catalogSnap.docs;
  const interleavedRecentDocs = interleaveDocs([freshPromotedDocs, freshCatalogDocs], itemsFetchLimit);

  let personaDocs: admin.firestore.DocumentSnapshot[] = [];
  if (personaCandidateIds.length > 0) {
    const personaLookupIds = personaCandidateIds.slice(0, Math.max(limit * 8, 80));
    const [personaGoldDocs, personaCatalogDocs] = await Promise.all([
      useGold ? getDocsByIds(db, "goldItems", personaLookupIds) : Promise.resolve([]),
      getDocsByIds(db, "items", personaLookupIds),
    ]);

    const personaById = new Map<string, admin.firestore.DocumentSnapshot>();
    for (const doc of personaGoldDocs) {
      const data = doc.data();
      if (doc.exists && data && data.isActive === true) {
        personaById.set(doc.id, doc);
      }
    }
    for (const doc of personaCatalogDocs) {
      const data = doc.data();
      if (doc.exists && data && data.isActive === true && !personaById.has(doc.id)) {
        personaById.set(doc.id, doc);
      }
    }
    personaDocs = personaLookupIds
      .map((id) => personaById.get(id))
      .filter((doc): doc is admin.firestore.DocumentSnapshot => doc != null);
  }

  const topPreferenceKeys = getTopPositivePreferenceKeys(preferenceWeights, 14);
  const preferredKeySet = new Set(topPreferenceKeys);

  const scoredRecent = interleavedRecentDocs.map((doc, index) => {
    const data = (doc.data() || {}) as Record<string, unknown>;
    return {
      doc,
      index,
      overlap: preferenceOverlapScore(data, preferredKeySet),
      randomKey: hashSessionId(`${requestId}:${doc.id}`),
    };
  });

  const preferenceQueueDocs = scoredRecent
    .filter((entry) => entry.overlap > 0)
    .sort((a, b) => b.overlap - a.overlap || a.index - b.index)
    .map((entry) => entry.doc);

  const longTailStart = Math.min(scoredRecent.length, Math.floor(scoredRecent.length * 0.35));
  const longTailQueueDocs = scoredRecent.slice(longTailStart).map((entry) => entry.doc);

  const serendipityQueueDocs = scoredRecent
    .filter((entry) => entry.overlap === 0)
    .sort((a, b) => a.randomKey - b.randomKey)
    .map((entry) => entry.doc);

  const queueDocs: Record<QueueName, admin.firestore.DocumentSnapshot[]> = {
    fresh_promoted: freshPromotedDocs,
    fresh_catalog: freshCatalogDocs,
    preference_match: preferenceQueueDocs,
    persona_similar: personaDocs,
    long_tail: longTailQueueDocs,
    serendipity: serendipityQueueDocs,
  };

  const queueTargets = buildQueueTargets(candidateCap, preferredKeySet.size > 0, personaDocs.length > 0);
  const queueContributions: Record<QueueName, number> = {
    fresh_promoted: 0,
    fresh_catalog: 0,
    preference_match: 0,
    persona_similar: 0,
    long_tail: 0,
    serendipity: 0,
  };
  const queueState = new Map<QueueName, { docs: admin.firestore.DocumentSnapshot[]; cursor: number }>();
  for (const queue of QUEUE_ORDER) {
    queueState.set(queue, { docs: queueDocs[queue], cursor: 0 });
  }

  const acceptedIds = new Set<string>();
  const seenCanonicals = new Set<string>();
  const candidateDocs: admin.firestore.DocumentSnapshot[] = [];
  const candidateQueueById = new Map<string, QueueName>();

  const tryAcceptCandidate = (doc: admin.firestore.DocumentSnapshot, queue: QueueName): boolean => {
    if (!doc.exists) return false;
    if (candidateDocs.length >= candidateCap) return false;
    if (seenItemIds.has(doc.id)) return false;
    if (acceptedIds.has(doc.id)) return false;

    const data = (doc.data() || {}) as Record<string, unknown>;
    if (sizeClassFilter && data.sizeClass !== sizeClassFilter) return false;
    if (colorFamilyFilter && data.colorFamily !== colorFamilyFilter) return false;
    if (newUsedFilter && data.newUsed !== newUsedFilter) return false;

    const price = asFiniteNumber(data.priceAmount);
    if (price != null) {
      if (minPriceFilter != null && price < minPriceFilter) return false;
      if (maxPriceFilter != null && price > maxPriceFilter) return false;
    }

    const canonical = typeof data.canonicalUrl === "string" ? data.canonicalUrl.trim() : "";
    if (canonical && seenCanonicals.has(canonical)) return false;

    acceptedIds.add(doc.id);
    if (canonical) seenCanonicals.add(canonical);
    candidateDocs.push(doc);
    candidateQueueById.set(doc.id, queue);
    queueContributions[queue] += 1;
    return true;
  };

  // Pass 1: hit per-queue quotas.
  let madeProgress = true;
  while (candidateDocs.length < candidateCap && madeProgress) {
    madeProgress = false;
    for (const queue of QUEUE_ORDER) {
      if (queueContributions[queue] >= queueTargets[queue]) continue;
      const state = queueState.get(queue)!;
      while (state.cursor < state.docs.length) {
        const doc = state.docs[state.cursor++];
        if (tryAcceptCandidate(doc, queue)) {
          madeProgress = true;
          break;
        }
      }
    }
  }

  // Pass 2: fill remaining slots by priority.
  for (const queue of BACKFILL_QUEUE_ORDER) {
    if (candidateDocs.length >= candidateCap) break;
    const state = queueState.get(queue)!;
    while (state.cursor < state.docs.length && candidateDocs.length < candidateCap) {
      const doc = state.docs[state.cursor++];
      tryAcceptCandidate(doc, queue);
    }
  }

  const candidates: ItemCandidate[] = candidateDocs.map((doc) => ({ id: doc.id, ...doc.data() } as ItemCandidate));
  const sessionContext: SessionContext = { preferenceWeights };

  const rankWindow = Math.min(candidates.length, Math.max(limit * 12, MIN_RANK_WINDOW));
  const rankResult = usePersonaRanker
    ? PersonalPlusPersonaRanker.rank(sessionContext, candidates, { limit: rankWindow }, personaSignals)
    : PreferenceWeightsRanker.rank(sessionContext, candidates, { limit: rankWindow });

  const explorationRate = Math.min(
    0.2,
    Math.max(0, parseFloat(String(process.env.RANKER_EXPLORATION_RATE || "0.08")) || 0)
  );
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
    .map((c) => {
      const queue = candidateQueueById.get(String(c.id));
      const fromPromotedQueue = queue === "fresh_promoted";
      if (!fromPromotedQueue) return { ...c };

      // Explicit featured flag for client rendering and analytics.
      return {
        ...c,
        isFeatured: true,
        featuredLabel: "Featured",
      };
    });

  const itemScores: Record<string, number> = {};
  exploredIds.forEach((id) => {
    if (rankResult.itemScores[id] != null) itemScores[id] = rankResult.itemScores[id];
  });

  const variantBucket = hashSessionId(sessionId) % 100;
  const variantBase = usePersonaRanker ? "personal_plus_persona" : "personal_only";
  const retrievalMode = personaDocs.length > 0 ? "multi_queue_persona" : "multi_queue_personal";
  const variant =
    explorationRate > 0
      ? `${variantBase}_${retrievalMode}_exploration_${Math.round(explorationRate * 100)}`
      : `${variantBase}_${retrievalMode}`;

  const allScores = Object.values(rankResult.itemScores);
  const nonZeroScores = allScores.filter((s) => s > 0);
  const scoreStats = {
    total: allScores.length,
    nonZero: nonZeroScores.length,
    zeroCount: allScores.length - nonZeroScores.length,
    min: allScores.length > 0 ? Math.min(...allScores) : 0,
    max: allScores.length > 0 ? Math.max(...allScores) : 0,
    avg: allScores.length > 0 ? allScores.reduce((a, b) => a + b, 0) / allScores.length : 0,
  };

  const retrievalQueuesUsed = QUEUE_ORDER.filter((queue) => queueContributions[queue] > 0);

  const response: Record<string, unknown> = {
    requestId,
    items,
    rank: {
      requestId,
      rankerRunId: rankResult.runId,
      algorithmVersion: rankResult.algorithmVersion,
      candidateSetId: `${rankResult.runId}:${candidates.length}`,
      candidateCount: candidates.length,
      rankWindow,
      retrievalQueues: retrievalQueuesUsed,
      itemIds: exploredIds,
      variant,
      variantBucket,
      explorationPolicy: explorationRate > 0 ? "sample_from_top_2limit" : "none",
      scoreStats,
    },
    itemScores,
  };

  if (debugMode) {
    const hasWeights = Object.keys(preferenceWeights).length > 0;
    const weightKeys = Object.keys(preferenceWeights);
    response.debug = {
      requestId,
      preferenceWeights: hasWeights ? preferenceWeights : "none",
      weightCount: weightKeys.length,
      topPreferenceKeys,
      candidatesConsidered: candidates.length,
      seenItemsExcluded: seenItemIds.size,
      hasPersonaSignals: usePersonaRanker,
      explorationRate,
      budgetFilter: minPriceFilter != null || maxPriceFilter != null ? { min: minPriceFilter, max: maxPriceFilter } : "none",
      sourceFetchCounts: {
        freshPromoted: freshPromotedDocs.length,
        freshCatalog: freshCatalogDocs.length,
        personaById: personaDocs.length,
      },
      queueTargets,
      queueContributions,
      queueSizes: {
        fresh_promoted: freshPromotedDocs.length,
        fresh_catalog: freshCatalogDocs.length,
        preference_match: preferenceQueueDocs.length,
        persona_similar: personaDocs.length,
        long_tail: longTailQueueDocs.length,
        serendipity: serendipityQueueDocs.length,
      },
      topItemsWithScores: items.slice(0, 5).map((item) => ({
        id: item.id,
        title: (item as Record<string, unknown>).title || "untitled",
        score: itemScores[item.id as string] ?? 0,
        styleTags: (item as Record<string, unknown>).styleTags || [],
        colorFamily: (item as Record<string, unknown>).colorFamily || null,
        material: (item as Record<string, unknown>).material || null,
      })),
    };
  }

  res.status(200).json(response);
}
