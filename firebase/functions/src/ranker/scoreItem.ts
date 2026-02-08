import type { ItemCandidate } from "./types";

type ScoreItemResult = {
  score: number;
  signalCount: number;
};

function addWeightedSignal(
  key: string | null | undefined,
  weights: Record<string, number>,
  state: { score: number; signalCount: number }
): void {
  if (!key) return;
  const weight = weights[key];
  if (typeof weight === "number" && weight !== 0) {
    state.score += weight;
    state.signalCount += 1;
  }
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

export function toPriceBucket(amount: unknown): string | null {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount < 0) return null;
  if (amount <= 3000) return "budget";
  if (amount <= 8000) return "affordable";
  if (amount <= 15000) return "mid";
  if (amount <= 30000) return "premium";
  return "luxury";
}

/**
 * Pure scoring function: score an item by preference weights.
 * Uses style/material/color/size plus richer furniture signals:
 * brand, delivery complexity, condition, eco tags, product features, and price bucket.
 */
export function scoreItemWithSignals(
  data: ItemCandidate,
  weights: Record<string, number>
): ScoreItemResult {
  const state = { score: 0, signalCount: 0 };
  const tags = getStringArray(data.styleTags);
  for (const t of tags) {
    addWeightedSignal(t, weights, state);
  }

  const material = normalizeToken(data.material);
  addWeightedSignal(material ? `material:${material}` : null, weights, state);

  const color = normalizeToken(data.colorFamily);
  addWeightedSignal(color ? `color:${color}` : null, weights, state);

  const sizeClass = normalizeToken(data.sizeClass);
  addWeightedSignal(sizeClass ? `size:${sizeClass}` : null, weights, state);

  const brand = normalizeToken(data.brand);
  addWeightedSignal(brand ? `brand:${brand}` : null, weights, state);

  const delivery = normalizeToken(data.deliveryComplexity);
  addWeightedSignal(delivery ? `delivery:${delivery}` : null, weights, state);

  const newUsed = normalizeToken(data.newUsed);
  addWeightedSignal(newUsed ? `condition:${newUsed}` : null, weights, state);

  const ecoTags = getStringArray(data.ecoTags);
  for (const ecoTag of ecoTags) {
    addWeightedSignal(`eco:${ecoTag}`, weights, state);
  }

  if (data.smallSpaceFriendly === true) {
    addWeightedSignal("feature:small_space", weights, state);
  }
  if (data.modular === true) {
    addWeightedSignal("feature:modular", weights, state);
  }

  // Sub-category signal (e.g., "subcat:3_seater", "subcat:corner_sofa")
  const subCategory = normalizeToken(data.subCategory);
  addWeightedSignal(subCategory ? `subcat:${subCategory}` : null, weights, state);

  // Room-type signals (e.g., "room:living_room", "room:outdoor")
  const roomTypes = getStringArray(data.roomTypes);
  for (const roomType of roomTypes) {
    addWeightedSignal(`room:${roomType}`, weights, state);
  }

  const priceBucket = toPriceBucket(data.priceAmount);
  addWeightedSignal(priceBucket ? `price_bucket:${priceBucket}` : null, weights, state);

  return state;
}

export function normalizeScore(score: number, signalCount: number): number {
  if (signalCount <= 0) return 0;
  return score / Math.sqrt(signalCount);
}

export function scoreItem(data: ItemCandidate, weights: Record<string, number>): number {
  return scoreItemWithSignals(data, weights).score;
}
