import type { ItemCandidate } from "./types";

type MMROptions = {
  lambda: number;
  topN: number;
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function normalizeToken(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

function getRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

function getStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((entry) => normalizeToken(entry)).filter((entry): entry is string => entry != null);
}

function itemFeatureTokens(item: ItemCandidate): Set<string> {
  const tokens = new Set<string>();
  const classification = getRecord(item.classification);

  for (const styleTag of getStringArray(item.styleTags)) {
    tokens.add(`style:${styleTag}`);
  }

  const material = normalizeToken(item.material);
  if (material) tokens.add(`material:${material}`);

  const color = normalizeToken(item.colorFamily);
  if (color) tokens.add(`color:${color}`);

  const sizeClass = normalizeToken(item.sizeClass);
  if (sizeClass) tokens.add(`size:${sizeClass}`);

  const primaryCategory = normalizeToken(
    item.primaryCategory ?? classification?.primaryCategory ?? classification?.predictedCategory
  );
  if (primaryCategory) tokens.add(`primary:${primaryCategory}`);

  const subCategory = normalizeToken(item.subCategory ?? classification?.subCategory);
  if (subCategory) tokens.add(`subcat:${subCategory}`);

  const seatCountBucket = normalizeToken(item.seatCountBucket ?? classification?.seatCountBucket);
  if (seatCountBucket) tokens.add(`seat_bucket:${seatCountBucket}`);

  for (const roomType of getStringArray(item.roomTypes ?? classification?.roomTypes)) {
    tokens.add(`room:${roomType}`);
  }

  return tokens;
}

function jaccardSimilarity(left: Set<string>, right: Set<string>): number {
  if (left.size === 0 || right.size === 0) return 0;
  let intersection = 0;
  for (const token of left) {
    if (right.has(token)) intersection += 1;
  }
  if (intersection === 0) return 0;
  return intersection / (left.size + right.size - intersection);
}

function normalizeRelevanceById(poolIds: string[], rawScores: Record<string, number>): Map<string, number> {
  const values = poolIds.map((id) => rawScores[id] ?? 0);
  const min = values.length > 0 ? Math.min(...values) : 0;
  const max = values.length > 0 ? Math.max(...values) : 0;
  const span = max - min;
  const normalized = new Map<string, number>();
  for (const id of poolIds) {
    const raw = rawScores[id] ?? 0;
    normalized.set(id, span > 0 ? (raw - min) / span : 0);
  }
  return normalized;
}

/**
 * Diversity-aware rerank based on Maximal Marginal Relevance (MMR).
 *
 * - lambda=1.0: pure relevance (no diversity penalty).
 * - lambda=0.0: pure diversity.
 *
 * Only the first `topN` items are reranked; tail order is preserved.
 */
export function applyMMRReRank(
  rankedIds: string[],
  candidates: ItemCandidate[],
  itemScores: Record<string, number>,
  options: MMROptions
): string[] {
  const lambda = clamp(options.lambda, 0, 1);
  const topN = Math.max(1, Math.min(options.topN, rankedIds.length));
  if (rankedIds.length <= 1 || topN <= 1 || lambda >= 1) return rankedIds.slice();

  const candidateById = new Map<string, ItemCandidate>();
  for (const candidate of candidates) {
    candidateById.set(String(candidate.id), candidate);
  }

  const poolIds = rankedIds.slice(0, topN);
  const tailIds = rankedIds.slice(topN);
  const originalIndex = new Map<string, number>();
  poolIds.forEach((id, index) => originalIndex.set(id, index));

  const relevanceById = normalizeRelevanceById(poolIds, itemScores);
  const tokensById = new Map<string, Set<string>>();
  for (const id of poolIds) {
    const candidate = candidateById.get(id);
    tokensById.set(id, candidate ? itemFeatureTokens(candidate) : new Set<string>());
  }

  const selected: string[] = [];
  const remaining = new Set<string>(poolIds);

  while (selected.length < poolIds.length) {
    let bestId: string | null = null;
    let bestMmr = Number.NEGATIVE_INFINITY;
    let bestRelevance = Number.NEGATIVE_INFINITY;
    let bestIndex = Number.MAX_SAFE_INTEGER;

    for (const id of poolIds) {
      if (!remaining.has(id)) continue;

      const relevance = relevanceById.get(id) ?? 0;
      let maxSimilarity = 0;
      const itemTokens = tokensById.get(id) || new Set<string>();
      for (const selectedId of selected) {
        const selectedTokens = tokensById.get(selectedId) || new Set<string>();
        maxSimilarity = Math.max(maxSimilarity, jaccardSimilarity(itemTokens, selectedTokens));
      }

      const mmrScore = lambda * relevance - (1 - lambda) * maxSimilarity;
      const index = originalIndex.get(id) ?? Number.MAX_SAFE_INTEGER;

      if (
        mmrScore > bestMmr ||
        (mmrScore === bestMmr && relevance > bestRelevance) ||
        (mmrScore === bestMmr && relevance === bestRelevance && index < bestIndex)
      ) {
        bestId = id;
        bestMmr = mmrScore;
        bestRelevance = relevance;
        bestIndex = index;
      }
    }

    if (!bestId) break;
    selected.push(bestId);
    remaining.delete(bestId);
  }

  if (selected.length !== poolIds.length) {
    for (const id of poolIds) {
      if (remaining.has(id)) selected.push(id);
    }
  }

  return [...selected, ...tailIds];
}
