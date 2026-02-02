import type { ItemCandidate } from "./types";

type ScoreItemResult = {
  score: number;
  signalCount: number;
};

/**
 * Pure scoring function: score an item by preference weights.
 * Uses styleTags, material (material:X), colorFamily (color:X), sizeClass (size:X).
 */
export function scoreItemWithSignals(
  data: ItemCandidate,
  weights: Record<string, number>
): ScoreItemResult {
  let score = 0;
  let signalCount = 0;
  const tags = (data.styleTags as string[] | undefined) || [];
  for (const t of tags) {
    const weight = weights[t];
    if (typeof weight === "number" && weight !== 0) {
      score += weight;
      signalCount += 1;
    }
  }
  const material = data.material as string | undefined;
  if (material) {
    const weight = weights[`material:${material}`];
    if (typeof weight === "number" && weight !== 0) {
      score += weight;
      signalCount += 1;
    }
  }
  const color = data.colorFamily as string | undefined;
  if (color) {
    const weight = weights[`color:${color}`];
    if (typeof weight === "number" && weight !== 0) {
      score += weight;
      signalCount += 1;
    }
  }
  const sizeClass = data.sizeClass as string | undefined;
  if (sizeClass) {
    const weight = weights[`size:${sizeClass}`];
    if (typeof weight === "number" && weight !== 0) {
      score += weight;
      signalCount += 1;
    }
  }
  return { score, signalCount };
}

export function normalizeScore(score: number, signalCount: number): number {
  if (signalCount <= 0) return 0;
  return score / Math.sqrt(signalCount);
}

export function scoreItem(data: ItemCandidate, weights: Record<string, number>): number {
  return scoreItemWithSignals(data, weights).score;
}
