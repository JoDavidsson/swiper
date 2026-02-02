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

function pickRandomUnusedId(pool: string[], usedIds: Set<string>, random: () => number): string | undefined {
  if (pool.length === 0) return undefined;

  // Try a few random draws first (fast when the pool is large and sparse).
  const maxAttempts = Math.min(25, pool.length);
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const idx = Math.floor(random() * pool.length);
    const id = pool[idx];
    if (!usedIds.has(id)) return id;
  }

  // Fall back to a linear scan (guaranteed termination).
  for (const id of pool) {
    if (!usedIds.has(id)) return id;
  }
  return undefined;
}

/**
 * Apply exploration to a ranked list of item IDs.
 * When explorationRate === 0, returns rankedIds unchanged (deterministic).
 *
 * When rate > 0, we probabilistically inject exploration while preserving most of the
 * ranker order:
 * - For each position in the output, with probability = explorationRate, pick a random
 *   unseen item from the "exploration pool" (top-N of rankedIds).
 * - Otherwise, take the next unseen item from the strict ranked order.
 *
 * Exploration pool size:
 * - Up to top 2,000 items, but never smaller than top 2*limit (when available).
 *
 * This keeps exposure mostly aligned with the ranker while still surfacing novelty.
 */
export function applyExploration(
  rankedIds: string[],
  _candidates: ItemCandidate[],
  options: { explorationRate: number; limit: number; seed?: number }
): string[] {
  const { explorationRate, limit, seed } = options;
  if (explorationRate <= 0 || limit <= 0) return rankedIds.slice(0, limit);

  const poolSize = Math.min(rankedIds.length, Math.max(2 * limit, 2000));
  const pool = rankedIds.slice(0, poolSize);

  const random = seed !== undefined ? createSeededRandom(seed) : Math.random;
  const result: string[] = [];
  const usedIds = new Set<string>();
  let strictIdx = 0;

  // Clamp rate into [0,1] to avoid surprising behavior.
  const rate = Math.min(1, Math.max(0, explorationRate));

  while (result.length < limit) {
    const shouldExplore = random() < rate;
    let chosen: string | undefined;

    if (shouldExplore) {
      chosen = pickRandomUnusedId(pool, usedIds, random);
    }

    // Fallback: take next strict item.
    if (chosen === undefined) {
      while (strictIdx < rankedIds.length && usedIds.has(rankedIds[strictIdx])) strictIdx += 1;
      chosen = rankedIds[strictIdx];
      strictIdx += 1;
    }

    if (chosen === undefined) break;
    if (usedIds.has(chosen)) continue;
    usedIds.add(chosen);
    result.push(chosen);
  }

  return result;
}
