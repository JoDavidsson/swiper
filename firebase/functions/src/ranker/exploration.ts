import type { ItemCandidate } from "./types";

/**
 * Seeded simple RNG for reproducible exploration (mulberry32).
 */
function createSeededRandom(seed: number): () => number {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Apply exploration to a ranked list of item IDs.
 * When explorationRate === 0, returns rankedIds unchanged (deterministic).
 * When rate > 0, uses "sample-from-top-2limit" strategy: take top 2*limit from rankedIds,
 * then randomly sample limit from that set (with optional seed for reproducibility).
 */
export function applyExploration(
  rankedIds: string[],
  _candidates: ItemCandidate[],
  options: { explorationRate: number; limit: number; seed?: number }
): string[] {
  const { explorationRate, limit, seed } = options;
  if (explorationRate <= 0 || limit <= 0) return rankedIds.slice(0, limit);

  const pool = rankedIds.slice(0, Math.min(rankedIds.length, 2 * limit));
  if (pool.length <= limit) return pool;

  const random = seed !== undefined ? createSeededRandom(seed) : Math.random;
  const base = rankedIds.slice(0, limit);
  const available = pool.slice(limit);
  if (available.length === 0) return base;

  const clampedRate = Math.min(1, Math.max(0, explorationRate));
  const desired = clampedRate * base.length;
  let numExplore = Math.floor(desired);
  const remainder = desired - numExplore;
  if (remainder > 0 && random() < remainder) numExplore += 1;
  numExplore = Math.min(numExplore, available.length);
  if (numExplore <= 0) return base;

  const pickUniqueIndices = (count: number, maxExclusive: number): number[] => {
    const picks: number[] = [];
    const used = new Set<number>();
    while (picks.length < count && used.size < maxExclusive) {
      const idx = Math.floor(random() * maxExclusive);
      if (used.has(idx)) continue;
      used.add(idx);
      picks.push(idx);
    }
    return picks;
  };

  const replacePositions = pickUniqueIndices(numExplore, base.length);
  const explorePositions = pickUniqueIndices(numExplore, available.length);
  const result = base.slice();

  for (let i = 0; i < numExplore; i += 1) {
    result[replacePositions[i]] = available[explorePositions[i]];
  }

  return result;
}
