import type { ItemCandidate } from "./types";

/**
 * Pure scoring function: score an item by preference weights.
 * Uses styleTags, material (material:X), colorFamily (color:X), sizeClass (size:X).
 */
export function scoreItem(data: ItemCandidate, weights: Record<string, number>): number {
  let score = 0;
  const tags = (data.styleTags as string[] | undefined) || [];
  for (const t of tags) {
    score += weights[t] ?? 0;
  }
  const material = data.material as string | undefined;
  if (material) score += weights[`material:${material}`] ?? 0;
  const color = data.colorFamily as string | undefined;
  if (color) score += weights[`color:${color}`] ?? 0;
  const sizeClass = data.sizeClass as string | undefined;
  if (sizeClass) score += weights[`size:${sizeClass}`] ?? 0;
  return score;
}
