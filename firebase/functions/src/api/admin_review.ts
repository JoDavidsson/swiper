import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

function parseLimit(value: unknown, fallback = 50, max = 200): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(1, Math.min(max, Math.trunc(parsed)));
}

function asString(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function shuffle<T>(arr: T[]): T[] {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function sample<T>(arr: T[], count: number): T[] {
  if (count >= arr.length) return [...arr];
  return shuffle(arr).slice(0, count);
}

function toNumber(value: unknown, fallback = 0.5): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function normalizeToken(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9åäö]+/g, " ")
    .trim();
}

function tokenizeText(value: string): string[] {
  return normalizeToken(value)
    .split(/\s+/)
    .filter((token) => token.length >= 3 && token.length <= 24);
}

const TOKEN_STOPWORDS = new Set<string>([
  "och",
  "med",
  "for",
  "utan",
  "the",
  "and",
  "for",
  "som",
  "att",
  "this",
  "that",
  "from",
  "till",
  "hos",
  "www",
  "se",
]);

function chunked<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    out.push(arr.slice(i, i + size));
  }
  return out;
}

export async function adminReviewQueueGet(req: Request, res: Response): Promise<void> {
  try {
    const db = admin.firestore();
    const status = asString(req.query.status, "pending") || "pending";
    const limit = parseLimit(req.query.limit, 50, 200);

    const queueSnap = await db
      .collection("reviewQueue")
      .where("status", "==", status)
      .limit(limit)
      .get();

    const ids = queueSnap.docs.map((doc) => doc.id);
    const itemDocs = await Promise.all(ids.map((id) => db.collection("items").doc(id).get()));
    const itemById = new Map<string, FirebaseFirestore.DocumentSnapshot>(
      itemDocs.map((doc) => [doc.id, doc]),
    );

    const items = queueSnap.docs.map((doc) => {
      const data = doc.data() || {};
      const itemDoc = itemById.get(doc.id);
      const itemData = itemDoc?.exists ? itemDoc.data() || {} : {};
      return {
        ...data,
        id: doc.id,
        item: {
          title: itemData.title,
          brand: itemData.brand,
          images: Array.isArray(itemData.images) ? itemData.images.slice(0, 2) : [],
          priceAmount: itemData.priceAmount,
          canonicalUrl: itemData.canonicalUrl,
          breadcrumbs: Array.isArray(itemData.breadcrumbs) ? itemData.breadcrumbs : [],
          productType: itemData.productType,
          sourceId: itemData.sourceId,
          classification: itemData.classification || null,
        },
      };
    });

    res.status(200).json({ items, count: items.length });
  } catch (e) {
    console.error("[adminReviewQueueGet]", e);
    res.status(500).json({ error: `review-queue failed: ${String(e)}` });
  }
}

type ItemTuple = { id: string; data: Record<string, unknown> };

type SamplingMix = {
  primaryCandidates: number;
  nearMissCandidates: number;
  selectedPrimary: number;
  selectedNearMiss: number;
  selectedBackfill: number;
};

type SamplingReason = "primary" | "near_miss" | "backfill" | "general";
type SamplingCandidate = { item: ItemTuple; reason: SamplingReason };

const TARGET_CATEGORY_HINTS: Record<string, string[]> = {
  sofa: [
    "soffa",
    "sofa",
    "couch",
    "modulsoffa",
    "u-soffa",
    "hörnsoffa",
    "corner sofa",
    "divansoffa",
  ],
};

function predictedCategoryOf(tuple: ItemTuple): string {
  const cls = tuple.data.classification as Record<string, unknown> | undefined;
  return asString(cls?.primaryCategory, asString(cls?.predictedCategory)).trim().toLowerCase();
}

function sourceIdOf(tuple: ItemTuple): string {
  return asString(tuple.data.sourceId, "unknown").trim() || "unknown";
}

function itemSamplingText(tuple: ItemTuple): string {
  const breadcrumbs = Array.isArray(tuple.data.breadcrumbs) ? tuple.data.breadcrumbs : [];
  const parts: string[] = [
    asString(tuple.data.title),
    asString(tuple.data.productType),
    breadcrumbs.map((x) => asString(x)).join(" "),
    asString(tuple.data.canonicalUrl),
  ];
  return normalizeToken(parts.join(" "));
}

function hasTargetHints(tuple: ItemTuple, targetCategory: string): boolean {
  const hints = TARGET_CATEGORY_HINTS[targetCategory] || [];
  if (hints.length === 0) return false;
  const text = itemSamplingText(tuple);
  return hints.some((hint) => {
    const normalizedHint = normalizeToken(hint);
    return normalizedHint.length > 0 && text.includes(normalizedHint);
  });
}

function categoryProbabilities(tuple: ItemTuple): number[] {
  const cls = tuple.data.classification as Record<string, unknown> | undefined;
  const probs = cls?.categoryProbabilities;
  if (!probs || typeof probs !== "object") return [];
  const values = Object.values(probs)
    .map((value) => (typeof value === "number" && Number.isFinite(value) ? value : null))
    .filter((value): value is number => value != null && value >= 0);
  return values;
}

function topTwo(values: number[]): [number, number] {
  if (values.length === 0) return [0.5, 0.0];
  let first = 0;
  let second = 0;
  for (const value of values) {
    if (value >= first) {
      second = first;
      first = value;
    } else if (value > second) {
      second = value;
    }
  }
  return [first, second];
}

function entropy(values: number[]): number {
  if (values.length <= 1) return 0;
  const total = values.reduce((sum, value) => sum + value, 0);
  if (total <= 0) return 0;
  let h = 0;
  for (const value of values) {
    const p = value / total;
    if (p <= 0) continue;
    h += -p * Math.log(p);
  }
  return h / Math.log(values.length);
}

function uncertaintyScore(tuple: ItemTuple): number {
  const cls = tuple.data.classification as Record<string, unknown> | undefined;
  const probs = categoryProbabilities(tuple);
  const [top1, top2] = topTwo(probs);
  const conf = toNumber(cls?.top1Confidence, top1 || 0.5);
  const marginFromCls = toNumber(cls?.top1Top2Margin, top1 - top2);
  const margin = Math.max(0, Math.min(1, marginFromCls));
  const normalizedEntropy = Math.max(0, Math.min(1, entropy(probs)));

  const confidenceCenterDistance = Math.abs(conf - 0.5) * 2; // 0(best uncertain) .. 1(very certain)
  const confidenceUncertainty = 1 - Math.max(0, Math.min(1, confidenceCenterDistance));
  const marginUncertainty = 1 - margin;

  return (normalizedEntropy * 0.55) + (marginUncertainty * 0.35) + (confidenceUncertainty * 0.10);
}

function buildSamplingCandidates(
  allItems: ItemTuple[],
  strategy: string,
  limit: number,
): ItemTuple[] {
  if (allItems.length === 0) return [];

  if (strategy === "uncertain") {
    return [...allItems]
      .sort((a, b) => uncertaintyScore(b) - uncertaintyScore(a))
      .slice(0, limit);
  }

  if (strategy === "diverse") {
    const byCategory = new Map<string, ItemTuple[]>();
    for (const tuple of allItems) {
      const cls = tuple.data.classification as Record<string, unknown> | undefined;
      const cat =
        asString(cls?.primaryCategory, asString(cls?.predictedCategory, "unclassified")) ||
        "unclassified";
      const bucket = byCategory.get(cat) || [];
      bucket.push(tuple);
      byCategory.set(cat, bucket);
    }

    const categories = [...byCategory.keys()];
    if (categories.length === 0) return sample(allItems, limit);

    const perCategory = Math.max(1, Math.floor(limit / categories.length));
    const selected: ItemTuple[] = [];

    for (const category of categories) {
      const group = byCategory.get(category) || [];
      selected.push(...sample(group, Math.min(perCategory, group.length)));
    }

    if (selected.length < limit) {
      const selectedIds = new Set(selected.map((x) => x.id));
      const remaining = allItems.filter((x) => !selectedIds.has(x.id));
      selected.push(...sample(remaining, Math.min(limit - selected.length, remaining.length)));
    }

    return selected.slice(0, limit);
  }

  return shuffle(allItems).slice(0, Math.min(limit, allItems.length));
}

function selectWithSourceCap(
  rankedPool: ItemTuple[],
  count: number,
  selectedIds: Set<string>,
  sourceCounts: Map<string, number>,
  sourceCap: number,
): ItemTuple[] {
  if (count <= 0 || rankedPool.length === 0) return [];

  const chosen: ItemTuple[] = [];

  for (const item of rankedPool) {
    if (chosen.length >= count) break;
    if (selectedIds.has(item.id)) continue;

    const sourceId = sourceIdOf(item);
    const currentCount = sourceCounts.get(sourceId) || 0;
    if (currentCount >= sourceCap) continue;

    chosen.push(item);
    selectedIds.add(item.id);
    sourceCounts.set(sourceId, currentCount + 1);
  }

  // Backfill if source cap is too strict for available pool.
  if (chosen.length < count) {
    for (const item of rankedPool) {
      if (chosen.length >= count) break;
      if (selectedIds.has(item.id)) continue;

      const sourceId = sourceIdOf(item);
      const currentCount = sourceCounts.get(sourceId) || 0;
      chosen.push(item);
      selectedIds.add(item.id);
      sourceCounts.set(sourceId, currentCount + 1);
    }
  }

  return chosen;
}

function buildTargetAwareSamplingCandidates(
  allItems: ItemTuple[],
  strategy: string,
  limit: number,
  targetCategory: string,
): { candidates: SamplingCandidate[]; mix: SamplingMix | null } {
  if (!targetCategory) {
    return {
      candidates: buildSamplingCandidates(allItems, strategy, limit).map((item) => ({ item, reason: "general" })),
      mix: null,
    };
  }

  const primaryPool = allItems.filter((item) => predictedCategoryOf(item) === targetCategory);
  const nearMissPool = allItems.filter((item) => {
    const predicted = predictedCategoryOf(item);
    if (predicted === targetCategory) return false;
    if (!hasTargetHints(item, targetCategory)) return false;
    return predicted === "unknown" || predicted !== targetCategory;
  });

  const primaryTarget = Math.max(1, Math.floor(limit * 0.4));
  const nearMissTarget = Math.max(1, Math.floor(limit * 0.4));
  const sourceCap = Math.max(2, Math.ceil(limit * 0.35));

  const selectedIds = new Set<string>();
  const sourceCounts = new Map<string, number>();
  const selected: SamplingCandidate[] = [];

  const rankedPrimary = buildSamplingCandidates(primaryPool, strategy, primaryPool.length);
  const pickedPrimary = selectWithSourceCap(
    rankedPrimary,
    Math.min(primaryTarget, limit),
    selectedIds,
    sourceCounts,
    sourceCap,
  );
  selected.push(...pickedPrimary.map((item) => ({ item, reason: "primary" as const })));

  const primaryShortfall = Math.max(0, primaryTarget - pickedPrimary.length);
  const nearMissBudget = Math.min(limit - selected.length, nearMissTarget + primaryShortfall);
  const rankedNearMiss = buildSamplingCandidates(nearMissPool, strategy, nearMissPool.length);
  const pickedNearMiss = selectWithSourceCap(
    rankedNearMiss,
    nearMissBudget,
    selectedIds,
    sourceCounts,
    sourceCap,
  );
  selected.push(...pickedNearMiss.map((item) => ({ item, reason: "near_miss" as const })));

  const focusSources = new Set(selected.map((entry) => sourceIdOf(entry.item)));
  const remainingBudget = Math.max(0, limit - selected.length);
  const contextualPool = allItems.filter((item) => {
    if (selectedIds.has(item.id)) return false;
    return focusSources.size === 0 || focusSources.has(sourceIdOf(item));
  });
  const fallbackPool = contextualPool.length > 0
    ? contextualPool
    : allItems.filter((item) => !selectedIds.has(item.id));
  const rankedFallback = buildSamplingCandidates(fallbackPool, strategy, fallbackPool.length);
  const pickedBackfill = selectWithSourceCap(
    rankedFallback,
    remainingBudget,
    selectedIds,
    sourceCounts,
    sourceCap,
  );
  selected.push(...pickedBackfill.map((item) => ({ item, reason: "backfill" as const })));

  return {
    candidates: selected.slice(0, limit),
    mix: {
      primaryCandidates: primaryPool.length,
      nearMissCandidates: nearMissPool.length,
      selectedPrimary: pickedPrimary.length,
      selectedNearMiss: pickedNearMiss.length,
      selectedBackfill: pickedBackfill.length,
    },
  };
}

async function fetchActiveItemsForSampling(
  db: FirebaseFirestore.Firestore,
  scanLimit: number,
): Promise<ItemTuple[]> {
  const target = Math.max(100, scanLimit);
  const pageSize = Math.min(500, target);
  const allItems: ItemTuple[] = [];
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;

  try {
    while (allItems.length < target) {
      let query: FirebaseFirestore.Query = db
        .collection("items")
        .where("isActive", "==", true)
        .orderBy("lastUpdatedAt", "desc")
        .limit(Math.min(pageSize, target - allItems.length));
      if (cursor) query = query.startAfter(cursor);

      const snap = await query.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        allItems.push({ id: doc.id, data: (doc.data() || {}) as Record<string, unknown> });
      }
      cursor = snap.docs[snap.docs.length - 1];
      if (snap.docs.length < pageSize) break;
    }
    if (allItems.length > 0) return allItems;
  } catch (e) {
    console.warn("[adminSamplingCandidatesGet] paginated fetch failed, falling back", e);
  }

  const fallbackSnap = await db
    .collection("items")
    .where("isActive", "==", true)
    .limit(Math.min(target, 2000))
    .get();
  return fallbackSnap.docs.map((doc) => ({
    id: doc.id,
    data: (doc.data() || {}) as Record<string, unknown>,
  }));
}

export async function adminSamplingCandidatesGet(req: Request, res: Response): Promise<void> {
  try {
    const db = admin.firestore();
    const strategy = asString(req.query.strategy, "diverse") || "diverse";
    const limit = parseLimit(req.query.limit, 20, 200);
    const scanLimit = parseLimit(req.query.scan_limit, 5000, 20000);
    const targetCategory = asString(
      req.query.target_category,
      asString(req.query.targetCategory, ""),
    ).trim().toLowerCase();

    const allItems = await fetchActiveItemsForSampling(db, scanLimit);

    const { candidates, mix } = buildTargetAwareSamplingCandidates(
      allItems,
      strategy,
      limit,
      targetCategory,
    );

    const items = candidates.map(({ item, reason }) => ({
      id: item.id,
      title: item.data.title,
      brand: item.data.brand,
      images: Array.isArray(item.data.images) ? item.data.images.slice(0, 1) : [],
      priceAmount: item.data.priceAmount,
      canonicalUrl: item.data.canonicalUrl,
      classification: item.data.classification || null,
      sourceId: item.data.sourceId,
      breadcrumbs: Array.isArray(item.data.breadcrumbs) ? item.data.breadcrumbs : [],
      samplingReason: reason,
    }));

    res.status(200).json({
      items,
      count: items.length,
      strategy,
      targetCategory: targetCategory || null,
      samplingMix: mix,
      scannedItems: allItems.length,
      scanLimit,
    });
  } catch (e) {
    console.error("[adminSamplingCandidatesGet]", e);
    res.status(500).json({ error: `sampling-candidates failed: ${String(e)}` });
  }
}

export async function adminReviewActionPost(req: Request, res: Response): Promise<void> {
  try {
    const db = admin.firestore();
    const body = (req.body || {}) as Record<string, unknown>;

    const itemId = asString(body.item_id).trim();
    const action = asString(body.action).trim();
    const correctCategory = asString(body.correct_category).trim() || null;
    const reason = asString(body.reason).trim() || null;
    const reviewerId = asString(body.reviewer_id, "admin").trim() || "admin";
    const trainingOnly = Boolean(body.training_only);
    const labelCategory = asString(body.label_category).trim().toLowerCase() || null;
    const labelDecisionRaw = asString(body.label_decision).trim().toLowerCase();
    const labelDecision = ["in_category", "not_category"].includes(labelDecisionRaw)
      ? labelDecisionRaw
      : null;
    const isInCategory = labelDecision
      ? labelDecision === "in_category"
      : (action === "accept" ? true : (action === "reject" ? false : null));

    if (!itemId) {
      res.status(400).json({ error: "item_id is required" });
      return;
    }
    if (!["accept", "reject", "reclassify"].includes(action)) {
      res.status(400).json({ error: "action must be one of: accept, reject, reclassify" });
      return;
    }
    if (action === "reclassify" && !correctCategory) {
      res.status(400).json({ error: "correct_category is required when action=reclassify" });
      return;
    }

    const nowIso = new Date().toISOString();
    const itemRef = db.collection("items").doc(itemId);
    const itemDoc = await itemRef.get();

    if (!itemDoc.exists) {
      res.status(404).json({ error: "Item not found" });
      return;
    }

    const itemData = itemDoc.data() || {};
    const reviewDoc = trainingOnly ? null : await db.collection("reviewQueue").doc(itemId).get();
    const reviewData = reviewDoc?.exists
      ? (reviewDoc.data() || {})
      : {
          itemId,
          classification: itemData.classification || {},
          decisions: itemData.eligibility || {},
          status: "pending",
          createdAt: nowIso,
          seededBy: "admin_review_action",
        };

    if (!trainingOnly && reviewDoc && !reviewDoc.exists) {
      await db.collection("reviewQueue").doc(itemId).set(reviewData, { merge: true });
    }

    if (!trainingOnly && action === "accept") {
      const classification = (reviewData.classification || {}) as Record<string, unknown>;
      const goldDoc = {
        itemId,
        eligibleSurfaces: ["swiper_deck_sofas", "swiper_deck_all_furniture"],
        primaryCategory:
          asString(classification.primaryCategory, asString(classification.predictedCategory, "unknown")) ||
          "unknown",
        predictedCategory: asString(classification.predictedCategory, "unknown") || "unknown",
        sofaTypeShape: classification.sofaTypeShape || null,
        sofaFunction: classification.sofaFunction || null,
        seatCountBucket: classification.seatCountBucket || null,
        environment:
          asString(classification.environment).toLowerCase() === "unknown"
            ? null
            : classification.environment || null,
        subCategory: classification.subCategory || null,
        roomTypes: Array.isArray(classification.roomTypes) ? classification.roomTypes : [],
        categoryConfidence: 1.0,
        classificationVersion: classification.classificationVersion || 1,
        policyVersion: 1,
        humanVerified: true,
        reviewerId,
        reviewReason: reason,
        promotedAt: nowIso,
        title: itemData.title,
        brand: itemData.brand,
        priceAmount: itemData.priceAmount,
        priceCurrency: itemData.priceCurrency,
        images: itemData.images,
        canonicalUrl: itemData.canonicalUrl,
        sourceId: itemData.sourceId,
        outboundUrl: itemData.outboundUrl,
        material: itemData.material,
        colorFamily: itemData.colorFamily,
        sizeClass: itemData.sizeClass,
        styleTags: itemData.styleTags || [],
        productType: itemData.productType,
        isActive: true,
      };
      await db.collection("goldItems").doc(itemId).set(goldDoc, { merge: true });
    }

    if (!trainingOnly && action === "reject") {
      await db.collection("goldItems").doc(itemId).delete();
    }

    if (!trainingOnly && action === "reclassify" && correctCategory) {
      await itemRef.update({
        "classification.primaryCategory": correctCategory,
        "classification.predictedCategory": correctCategory,
        "classification.humanCorrected": true,
        "classification.correctedBy": reviewerId,
        primaryCategory: correctCategory,
      });
    }

    const writes: Array<Promise<unknown>> = [
      db.collection("reviewerLabels").add({
        itemId,
        action,
        correctCategory,
        reason,
        reviewerId,
        trainingOnly,
        labelCategory,
        labelDecision,
        isInCategory,
        source: trainingOnly ? "training_lab" : "operations_review",
        originalClassification: reviewData.classification || itemData.classification || null,
        createdAt: nowIso,
      }),
    ];

    if (!trainingOnly) {
      writes.push(
        db.collection("reviewQueue").doc(itemId).set(
          {
            status: "reviewed",
            reviewedBy: reviewerId,
            reviewAction: action,
            reviewReason: reason,
            correctCategory,
            labelCategory,
            labelDecision,
            reviewedAt: nowIso,
          },
          { merge: true },
        ),
      );
    }

    await Promise.all(writes);

    res.status(200).json({ status: "ok", action, itemId, trainingOnly });
  } catch (e) {
    console.error("[adminReviewActionPost]", e);
    res.status(500).json({ error: `review-action failed: ${String(e)}` });
  }
}

type TokenStats = { total: number; rejects: number };
type SourceStats = {
  sourceId: string;
  total: number;
  accepts: number;
  rejects: number;
  missingImageRejects: number;
};
type SourceCategoryStats = {
  sourceId: string;
  predictedCategory: string;
  total: number;
  accepts: number;
  rejects: number;
  tokenStats: Map<string, TokenStats>;
};

function extractTrainingTokens(itemData: Record<string, unknown>): string[] {
  const pieces: string[] = [];
  pieces.push(asString(itemData.productType));
  pieces.push(asString(itemData.title));

  const breadcrumbs = Array.isArray(itemData.breadcrumbs) ? itemData.breadcrumbs : [];
  for (const breadcrumb of breadcrumbs.slice(-2)) {
    pieces.push(asString(breadcrumb));
  }

  const tokens = new Set<string>();
  for (const piece of pieces) {
    for (const token of tokenizeText(piece)) {
      if (TOKEN_STOPWORDS.has(token)) continue;
      tokens.add(token);
    }
  }
  return [...tokens].slice(0, 40);
}

function upsertNestedList(
  root: Record<string, Record<string, string[]>>,
  sourceId: string,
  category: string,
  values: string[],
): void {
  if (!root[sourceId]) root[sourceId] = {};
  root[sourceId][category] = values;
}

function upsertNestedNumber(
  root: Record<string, Record<string, number>>,
  sourceId: string,
  category: string,
  value: number,
): void {
  if (!root[sourceId]) root[sourceId] = {};
  root[sourceId][category] = value;
}

type TrainingSample = {
  itemId: string;
  item: Record<string, unknown>;
  sourceId: string;
  predictedCategory: string;
  isInCategory: boolean;
  hasImages: boolean;
};

function hashBucket(value: string, mod = 10): number {
  let hash = 0;
  for (let i = 0; i < value.length; i += 1) {
    hash = ((hash << 5) - hash) + value.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash) % mod;
}

function evaluateRuleRejection(
  sample: TrainingSample,
  targetCategory: string,
  sourceCategoryRejectTokens: Record<string, Record<string, string[]>>,
  sourceCategoryMinConfidence: Record<string, Record<string, number>>,
  sourceRequireImages: Record<string, boolean>,
): boolean {
  const sourceId = sample.sourceId;
  if (sourceRequireImages[sourceId] && !sample.hasImages) return true;

  const confMap = sourceCategoryMinConfidence[sourceId] || {};
  const minConf = confMap[targetCategory];
  if (typeof minConf === "number") {
    const cls = (sample.item.classification as Record<string, unknown> | undefined) || {};
    const conf = toNumber(cls.top1Confidence, 0.5);
    if (conf < minConf) return true;
  }

  const rejectTokens = ((sourceCategoryRejectTokens[sourceId] || {})[targetCategory] || []);
  if (rejectTokens.length === 0) return false;
  const textBlob = normalizeToken(
    [
      asString(sample.item.title),
      asString(sample.item.productType),
      asString(sample.item.canonicalUrl),
      ...(Array.isArray(sample.item.breadcrumbs)
        ? (sample.item.breadcrumbs as unknown[]).map((entry) => asString(entry))
        : []),
    ].join(" "),
  );
  return rejectTokens.some((token) => {
    const normalized = normalizeToken(token);
    return normalized.length > 0 && textBlob.includes(normalized);
  });
}

function computeBinaryMetrics(
  rows: Array<{ actualPositive: boolean; predictedPositive: boolean }>,
): { precision: number; recall: number; f1: number; tp: number; fp: number; fn: number; sampleSize: number } {
  let tp = 0;
  let fp = 0;
  let fn = 0;
  for (const row of rows) {
    if (row.predictedPositive && row.actualPositive) tp += 1;
    if (row.predictedPositive && !row.actualPositive) fp += 1;
    if (!row.predictedPositive && row.actualPositive) fn += 1;
  }
  const precision = tp + fp > 0 ? tp / (tp + fp) : 0;
  const recall = tp + fn > 0 ? tp / (tp + fn) : 0;
  const f1 = precision + recall > 0 ? (2 * precision * recall) / (precision + recall) : 0;
  return {
    precision: Number(precision.toFixed(4)),
    recall: Number(recall.toFixed(4)),
    f1: Number(f1.toFixed(4)),
    tp,
    fp,
    fn,
    sampleSize: rows.length,
  };
}

export async function adminTrainCategorizerPost(req: Request, res: Response): Promise<void> {
  try {
    const db = admin.firestore();
    const nowIso = new Date().toISOString();
    const body = (req.body || {}) as Record<string, unknown>;
    const targetCategory = asString(body.category, "sofa").trim().toLowerCase() || "sofa";
    const allowLegacyFallback = process.env.ALLOW_LEGACY_TRAINING_LABEL_FALLBACK === "true";

    const labelsSnap = await db.collection("reviewerLabels").limit(8000).get();
    if (labelsSnap.empty) {
      res.status(200).json({
        status: "ok",
        message: "No reviewer labels found.",
        targetCategory,
        labelsUsed: 0,
        recommendedMinLabels: 150,
      });
      return;
    }

    const labels = labelsSnap.docs.map((doc) => doc.data() || {});
    const actionable = labels
      .map((raw) => raw as Record<string, unknown>)
      .map((label) => {
        const itemId = asString(label.itemId).trim();
        if (!itemId) return null;

        const explicitCategory = asString(label.labelCategory || label.label_category).trim().toLowerCase();
        if (!explicitCategory && !allowLegacyFallback) return null;
        if (explicitCategory && explicitCategory !== targetCategory) return null;
        if (!explicitCategory && allowLegacyFallback && targetCategory !== "sofa") return null;

        let isInCategory: boolean | null =
          typeof label.isInCategory === "boolean" ? (label.isInCategory as boolean) : null;

        if (isInCategory === null) {
          const decision = asString(label.labelDecision || label.label_decision).trim().toLowerCase();
          if (decision === "in_category") isInCategory = true;
          if (decision === "not_category") isInCategory = false;
        }

        if (isInCategory === null && allowLegacyFallback) {
          const action = asString(label.action).toLowerCase();
          if (action === "accept") isInCategory = true;
          if (action === "reject") isInCategory = false;
        }

        if (isInCategory === null) return null;

        return {
          itemId,
          isInCategory,
          originalClassification: (label.originalClassification as Record<string, unknown> | undefined) || {},
        };
      })
      .filter((row): row is {
        itemId: string;
        isInCategory: boolean;
        originalClassification: Record<string, unknown>;
      } => row !== null);

    if (actionable.length === 0) {
      res.status(200).json({
        status: "ok",
        message: `No labels found for category '${targetCategory}'.`,
        targetCategory,
        labelsUsed: 0,
        recommendedMinLabels: 150,
      });
      return;
    }

    const itemIds = [...new Set(actionable.map((label) => label.itemId).filter(Boolean))];
    const itemMap = new Map<string, Record<string, unknown>>();
    for (const batch of chunked(itemIds, 250)) {
      const docs = await Promise.all(batch.map((id) => db.collection("items").doc(id).get()));
      for (const doc of docs) {
        if (doc.exists) itemMap.set(doc.id, (doc.data() || {}) as Record<string, unknown>);
      }
    }

    const allSamples: TrainingSample[] = [];
    for (const rawLabel of actionable) {
      const item = itemMap.get(rawLabel.itemId);
      if (!item) continue;
      const sourceId = asString(item.sourceId, "unknown") || "unknown";
      const originalClassification = rawLabel.originalClassification || {};
      const itemClassification = (item.classification as Record<string, unknown> | undefined) || {};
      const predictedCategory = asString(
        originalClassification.primaryCategory,
        asString(
          originalClassification.predictedCategory,
          asString(itemClassification.primaryCategory, asString(itemClassification.predictedCategory, "unknown")),
        ),
      ) || "unknown";
      allSamples.push({
        itemId: rawLabel.itemId,
        item,
        sourceId,
        predictedCategory,
        isInCategory: rawLabel.isInCategory,
        hasImages: Array.isArray(item.images) && item.images.length > 0,
      });
    }

    const trainSamples: TrainingSample[] = [];
    const holdoutSamples: TrainingSample[] = [];
    for (const sample of allSamples) {
      if (hashBucket(sample.itemId, 10) < 8) {
        trainSamples.push(sample);
      } else {
        holdoutSamples.push(sample);
      }
    }

    const sourceStatsMap = new Map<string, SourceStats>();
    const sourceCategoryStatsMap = new Map<string, SourceCategoryStats>();
    let labelsUsed = 0;

    for (const sample of trainSamples) {
      labelsUsed += 1;
      const isReject = !sample.isInCategory;

      const sourceStat = sourceStatsMap.get(sample.sourceId) || {
        sourceId: sample.sourceId,
        total: 0,
        accepts: 0,
        rejects: 0,
        missingImageRejects: 0,
      };
      sourceStat.total += 1;
      if (sample.isInCategory) sourceStat.accepts += 1;
      if (isReject) {
        sourceStat.rejects += 1;
        if (!sample.hasImages) sourceStat.missingImageRejects += 1;
      }
      sourceStatsMap.set(sample.sourceId, sourceStat);

      const scKey = `${sample.sourceId}::${sample.predictedCategory}`;
      const scStat = sourceCategoryStatsMap.get(scKey) || {
        sourceId: sample.sourceId,
        predictedCategory: sample.predictedCategory,
        total: 0,
        accepts: 0,
        rejects: 0,
        tokenStats: new Map<string, TokenStats>(),
      };
      scStat.total += 1;
      if (sample.isInCategory) scStat.accepts += 1;
      if (isReject) scStat.rejects += 1;

      const tokens = extractTrainingTokens(sample.item);
      for (const token of tokens) {
        const tokenStat = scStat.tokenStats.get(token) || { total: 0, rejects: 0 };
        tokenStat.total += 1;
        if (isReject) tokenStat.rejects += 1;
        scStat.tokenStats.set(token, tokenStat);
      }
      sourceCategoryStatsMap.set(scKey, scStat);
    }

    const sourceCategoryRejectTokens: Record<string, Record<string, string[]>> = {};
    const sourceCategoryMinConfidence: Record<string, Record<string, number>> = {};
    const sourceRequireImages: Record<string, boolean> = {};
    const topFindings: Array<Record<string, unknown>> = [];

    for (const sourceStat of sourceStatsMap.values()) {
      if (sourceStat.rejects >= 5) {
        const missingImageRejectRate = sourceStat.missingImageRejects / sourceStat.rejects;
        if (missingImageRejectRate >= 0.35) {
          sourceRequireImages[sourceStat.sourceId] = true;
        }
      }
    }

    for (const scStat of sourceCategoryStatsMap.values()) {
      if (scStat.total < 8) continue;
      const rejectRate = scStat.rejects / scStat.total;

      if (scStat.total >= 15 && rejectRate >= 0.55) {
        const minConf = rejectRate >= 0.7 ? 0.75 : 0.65;
        upsertNestedNumber(
          sourceCategoryMinConfidence,
          scStat.sourceId,
          scStat.predictedCategory,
          minConf,
        );
      }

      const riskyTokens = [...scStat.tokenStats.entries()]
        .map(([token, stat]) => ({
          token,
          support: stat.total,
          rejectRate: stat.total > 0 ? stat.rejects / stat.total : 0,
          rejects: stat.rejects,
        }))
        .filter((entry) => entry.support >= 3 && entry.rejectRate >= 0.75 && entry.rejects >= 3)
        .sort((a, b) => {
          if (b.rejectRate !== a.rejectRate) return b.rejectRate - a.rejectRate;
          return b.rejects - a.rejects;
        })
        .slice(0, 8);

      if (riskyTokens.length > 0) {
        upsertNestedList(
          sourceCategoryRejectTokens,
          scStat.sourceId,
          scStat.predictedCategory,
          riskyTokens.map((entry) => entry.token),
        );
      }

      if (rejectRate >= 0.5) {
        topFindings.push({
          sourceId: scStat.sourceId,
          predictedCategory: scStat.predictedCategory,
          sampleSize: scStat.total,
          rejectRate: Number(rejectRate.toFixed(3)),
          riskyTokens: riskyTokens.slice(0, 5),
        });
      }
    }

    topFindings.sort((a, b) => {
      const rA = toNumber((a as Record<string, unknown>).rejectRate, 0);
      const rB = toNumber((b as Record<string, unknown>).rejectRate, 0);
      if (rB !== rA) return rB - rA;
      const sA = toNumber((a as Record<string, unknown>).sampleSize, 0);
      const sB = toNumber((b as Record<string, unknown>).sampleSize, 0);
      return sB - sA;
    });

    const baselineRows = holdoutSamples.map((sample) => ({
      actualPositive: sample.isInCategory,
      predictedPositive: sample.predictedCategory === targetCategory,
    }));
    const adjustedRows = holdoutSamples.map((sample) => {
      const baselinePositive = sample.predictedCategory === targetCategory;
      if (!baselinePositive) {
        return { actualPositive: sample.isInCategory, predictedPositive: false };
      }
      const rejectedByRules = evaluateRuleRejection(
        sample,
        targetCategory,
        sourceCategoryRejectTokens,
        sourceCategoryMinConfidence,
        sourceRequireImages,
      );
      return {
        actualPositive: sample.isInCategory,
        predictedPositive: !rejectedByRules,
      };
    });

    const baselineMetrics = computeBinaryMetrics(baselineRows);
    const adjustedMetrics = computeBinaryMetrics(adjustedRows);
    const precisionDelta = Number((adjustedMetrics.precision - baselineMetrics.precision).toFixed(4));
    const recallDelta = Number((adjustedMetrics.recall - baselineMetrics.recall).toFixed(4));

    const minHoldout = 40;
    const hasHoldoutData = holdoutSamples.length >= minHoldout;
    const gatePassed = hasHoldoutData && precisionDelta >= 0.03 && recallDelta >= -0.08;
    const gateReason = !hasHoldoutData
      ? `insufficient_holdout:${holdoutSamples.length}<${minHoldout}`
      : gatePassed
        ? "pass"
        : "precision_or_recall_regression";

    const categoryConfig = {
      version: 2,
      targetCategory,
      trainedAt: nowIso,
      labelsUsed,
      trainingSplit: {
        trainSamples: trainSamples.length,
        holdoutSamples: holdoutSamples.length,
      },
      sourceCategoryRejectTokens,
      sourceCategoryMinConfidence,
      sourceRequireImages,
      evaluation: {
        baseline: baselineMetrics,
        adjusted: adjustedMetrics,
        precisionDelta,
        recallDelta,
        gate: {
          passed: gatePassed,
          reason: gateReason,
        },
      },
      runtimeStatus: gatePassed ? "validated" : "shadow_only",
      summary: {
        sourcesCovered: sourceStatsMap.size,
        sourceCategoriesCovered: sourceCategoryStatsMap.size,
        findingsCount: topFindings.length,
      },
    };

    const latestRef = db.collection("categorizationTrainingConfig").doc("latest");
    const latestSnap = await latestRef.get();
    const latestData = latestSnap.exists ? (latestSnap.data() || {}) : {};
    const byCategory = ((latestData.byCategory as Record<string, unknown>) || {}) as Record<string, unknown>;
    byCategory[targetCategory] = categoryConfig;

    await Promise.all([
      latestRef.set({
        version: 2,
        updatedAt: nowIso,
        lastTargetCategory: targetCategory,
        byCategory,
      }, { merge: true }),
      db.collection("categorizationTrainingRuns").add({
        ...categoryConfig,
        topFindings: topFindings.slice(0, 30),
      }),
    ]);

    res.status(200).json({
      status: "ok",
      targetCategory,
      labelsUsed,
      recommendedMinLabels: 150,
      recommendedGoodLabels: 400,
      legacyFallbackEnabled: allowLegacyFallback,
      config: {
        sourcesWithImageRule: Object.keys(sourceRequireImages).length,
        sourcesWithTokenRules: Object.keys(sourceCategoryRejectTokens).length,
        sourcesWithConfidenceRules: Object.keys(sourceCategoryMinConfidence).length,
      },
      evaluation: categoryConfig.evaluation,
      runtimeStatus: categoryConfig.runtimeStatus,
      topFindings: topFindings.slice(0, 12),
    });
  } catch (e) {
    console.error("[adminTrainCategorizerPost]", e);
    res.status(500).json({ error: `train-categorizer failed: ${String(e)}` });
  }
}
