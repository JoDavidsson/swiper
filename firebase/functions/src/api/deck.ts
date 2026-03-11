import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { applyExploration, PreferenceWeightsRanker, PersonalPlusPersonaRanker } from "../ranker";
import type { ItemCandidate, PersonaSignals, SessionContext } from "../ranker";
import { getPersonaSignals } from "../scheduled/persona_aggregation";
import {
  buildSessionTargetingProfile,
  DEFAULT_SEGMENT_MATCH_THRESHOLD,
  evaluateSegmentMatch,
  toSegmentCriteria,
} from "../targeting/segment_targeting";
import type { SessionTargetingProfile } from "../targeting/segment_targeting";

const DEFAULT_LIMIT = 30;
const MIN_ITEMS_FETCH_LIMIT = 240;
const MIN_CANDIDATE_CAP = 120;
const MIN_RANK_WINDOW = 120;
const MIN_SOURCE_FETCH = 60;
const MAX_PERSONA_RETRIEVAL_IDS = 120;
const DEFAULT_FEATURED_FREQUENCY_CAP = Math.max(
  2,
  parseInt(String(process.env.FEATURED_FREQUENCY_CAP || "12"), 10) || 12
);
const FEATURED_RETAILER_COOLDOWN = Math.max(
  1,
  parseInt(String(process.env.FEATURED_RETAILER_COOLDOWN || "1"), 10) || 1
);
const FEATURED_COST_PER_IMPRESSION_SEK = Math.max(
  0,
  parseFloat(String(process.env.FEATURED_COST_PER_IMPRESSION_SEK || "1")) || 1
);
const FEATURED_PACING_BUFFER_RATIO = Math.max(
  0,
  parseFloat(String(process.env.FEATURED_PACING_BUFFER_RATIO || "0.2")) || 0.2
);

/** Default boost value for onboarding pick attributes (cold-start) */
const ONBOARDING_PICK_BOOST = 3;
const ONBOARDING_V2_BOOST = 2.5;
const UNIVERSAL_FAMILY_DEDUPE_TOP_N = Math.max(
  0,
  parseInt(String(process.env.UNIVERSAL_FAMILY_DEDUPE_TOP_N || "12"), 10) || 12
);
const ONBOARDING_HARD_CONSTRAINT_SWIPE_THRESHOLD = Math.max(
  0,
  parseInt(String(process.env.ONBOARDING_HARD_CONSTRAINT_SWIPE_THRESHOLD || "10"), 10) || 10
);
const ONBOARDING_MEDIUM_CONSTRAINT_SWIPE_THRESHOLD = Math.max(
  0,
  parseInt(String(process.env.ONBOARDING_MEDIUM_CONSTRAINT_SWIPE_THRESHOLD || "4"), 10) || 4
);
const HARD_NEAR_DUPLICATE_TOP_N = Math.max(
  0,
  parseInt(String(process.env.HARD_NEAR_DUPLICATE_TOP_N || "8"), 10) || 8
);
const SOFT_NEAR_DUPLICATE_TOP_N = Math.max(
  HARD_NEAR_DUPLICATE_TOP_N,
  parseInt(String(process.env.SOFT_NEAR_DUPLICATE_TOP_N || "12"), 10) || 12
);
const SOFT_NEAR_DUPLICATE_MAX_REPEATS = Math.max(
  0,
  parseInt(String(process.env.SOFT_NEAR_DUPLICATE_MAX_REPEATS || "1"), 10) || 1
);
const SOFT_NEAR_DUPLICATE_MIN_STYLE_DISTANCE = Math.min(
  1,
  Math.max(
    0,
    parseFloat(String(process.env.SOFT_NEAR_DUPLICATE_MIN_STYLE_DISTANCE || "0.28")) || 0.28
  )
);
const SOFT_NEAR_DUPLICATE_MIN_GAP = Math.max(
  1,
  parseInt(String(process.env.SOFT_NEAR_DUPLICATE_MIN_GAP || "4"), 10) || 4
);
const SOFT_REPEAT_MIN_IMAGE_COUNT = Math.max(
  1,
  parseInt(String(process.env.SOFT_REPEAT_MIN_IMAGE_COUNT || "2"), 10) || 2
);
const SOFT_REPEAT_MIN_CREATIVE_SCORE = Math.max(
  0,
  parseFloat(String(process.env.SOFT_REPEAT_MIN_CREATIVE_SCORE || "60")) || 60
);
const PREFER_CONTEXTUAL_SCENE_CANDIDATES =
  process.env.PREFER_CONTEXTUAL_SCENE_CANDIDATES !== "false";
const SOURCE_DIVERSITY_TOP_N = Math.max(
  HARD_NEAR_DUPLICATE_TOP_N,
  parseInt(String(process.env.SOURCE_DIVERSITY_TOP_N || "12"), 10) || 12
);
const SOURCE_DIVERSITY_MAX_PER_SOURCE = Math.max(
  1,
  parseInt(String(process.env.SOURCE_DIVERSITY_MAX_PER_SOURCE || "6"), 10) || 6
);
const TOP_MODEL_DEDUPE_TOP_N = Math.max(
  HARD_NEAR_DUPLICATE_TOP_N,
  parseInt(String(process.env.TOP_MODEL_DEDUPE_TOP_N || "12"), 10) || 12
);
const TOP_MODEL_DEDUPE_MAX_PER_MODEL = Math.max(
  1,
  parseInt(String(process.env.TOP_MODEL_DEDUPE_MAX_PER_MODEL || "1"), 10) || 1
);
const ENABLE_SCORE_QUALITY_GATE = process.env.ENABLE_SCORE_QUALITY_GATE !== "false";
const QUALITY_SCORE_LOOKUP_LIMIT = Math.max(
  0,
  parseInt(String(process.env.QUALITY_SCORE_LOOKUP_LIMIT || "120"), 10) || 120
);

const MAX_LIMIT = parseInt(String(process.env.DECK_RESPONSE_LIMIT || "500"), 10) || 500;

type QueueName =
  | "fresh_promoted"
  | "fresh_catalog"
  | "preference_match"
  | "persona_similar"
  | "long_tail"
  | "serendipity";

type OnboardingV2Constraints = {
  budgetBand?: string;
  seatCount?: string;
  modularOnly?: boolean;
  kidsPets?: boolean;
  smallSpace?: boolean;
};

type OnboardingV2Profile = {
  sceneArchetypes: string[];
  sofaVibes: string[];
  constraints: OnboardingV2Constraints;
  derivedProfile?: {
    primaryStyle?: string | null;
    secondaryStyle?: string | null;
    confidence?: number;
    explanation?: string[];
  };
  pickHash?: string;
};

type CampaignTargetingContext = {
  campaignId: string;
  retailerId: string;
  segmentId: string;
  segmentCriteria: ReturnType<typeof toSegmentCriteria>;
  threshold: number;
  frequencyCap: number;
  recommendedProductIds: Set<string>;
  productMode: "all" | "selected" | "auto";
  productIds: Set<string>;
};

type PromotedTargetingDecision = {
  eligible: boolean;
  reason:
    | "legacy_promoted"
    | "eligible_campaign"
    | "campaign_not_found"
    | "segment_mismatch"
    | "product_set_mismatch";
  campaignId: string | null;
  segmentId: string | null;
  relevanceScore: number | null;
  threshold: number | null;
};

type FeaturedServingStats = {
  configuredFrequencyCap: number;
  maxFeaturedSlots: number;
  featuredInSourceRank: number;
  featuredServed: number;
  droppedForFrequencyCap: number;
  droppedForDiversity: number;
  fallbackToOrganicCount: number;
  overflowFeaturedUsed: number;
};

type FeaturedLoggingStats = {
  loggedCount: number;
  updatedCampaignCount: number;
  estimatedSpendSEK: number;
};

type ExplorationDiversityStats = {
  droppedHardNearDuplicate: number;
  droppedSoftNearDuplicate: number;
  droppedSoftForQuality: number;
  droppedSoftForStyleDistance: number;
  allowedSoftNearDuplicate: number;
};

type SourceDiversityStats = {
  deferredForSourceCap: number;
};

type ModelDiversityStats = {
  deferredForModelCap: number;
};

const ONBOARDING_V2_SCENE_SIGNAL_MAP: Record<string, string[]> = {
  calm_minimal: ["minimal", "scandinavian", "modern", "color:white", "color:grey"],
  warm_organic: ["scandinavian", "material:wood", "color:beige", "color:brown"],
  bold_eclectic: ["vintage", "color:green", "color:blue"],
  urban_industrial: ["industrial", "modern", "color:black", "material:metal"],
};

const ONBOARDING_V2_SOFA_SIGNAL_MAP: Record<string, string[]> = {
  rounded_boucle: ["material:boucle", "material:fabric", "color:beige"],
  low_profile_linen: ["material:linen", "size:medium", "feature:small_space"],
  structured_leather: ["material:leather", "color:brown", "color:black"],
  modular_cloud: ["feature:modular", "subcat:modular_sofa"],
};

const ONBOARDING_V2_BUDGET_BANDS: Record<string, { min?: number; max?: number }> = {
  lt_5k: { max: 5000 },
  "5k_15k": { min: 5000, max: 15000 },
  "15k_30k": { min: 15000, max: 30000 },
  "30k_plus": { min: 30000 },
};

const ONBOARDING_V2_SEAT_SUBCATEGORIES: Record<string, string[]> = {
  "2": ["2_seater"],
  "3": ["3_seater"],
  "4_plus": ["4_seater", "corner_sofa", "u_sofa"],
};

const ONBOARDING_V2_SEAT_BUCKETS: Record<string, string[]> = {
  "2": ["2"],
  "3": ["3"],
  "4_plus": ["4_plus"],
};

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

function asTrimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function toRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

function toStringSet(value: unknown): Set<string> {
  if (!Array.isArray(value)) return new Set<string>();
  const out = new Set<string>();
  for (const entry of value) {
    const id = asTrimmedString(entry);
    if (id) out.add(id);
  }
  return out;
}

function timestampToMillis(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  if (typeof value === "object") {
    const candidate = value as { toMillis?: () => number; toDate?: () => Date };
    if (typeof candidate.toMillis === "function") {
      const ms = candidate.toMillis();
      return Number.isFinite(ms) ? ms : null;
    }
    if (typeof candidate.toDate === "function") {
      const date = candidate.toDate();
      const ms = date.getTime();
      return Number.isFinite(ms) ? ms : null;
    }
  }
  return null;
}

function toDateKeyUTC(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function toCampaignProductMode(value: unknown): "all" | "selected" | "auto" {
  if (value === "selected" || value === "auto" || value === "all") return value;
  return "all";
}

function toFrequencyCap(value: unknown): number {
  const parsed = asFiniteNumber(value);
  if (parsed == null || !Number.isInteger(parsed) || parsed < 2) {
    return DEFAULT_FEATURED_FREQUENCY_CAP;
  }
  return Math.min(60, parsed);
}

function toMatchThreshold(value: unknown): number {
  const parsed = asFiniteNumber(value);
  if (parsed == null) return DEFAULT_SEGMENT_MATCH_THRESHOLD;
  return Math.max(0, Math.min(1, parsed));
}

function campaignHasBudgetRemaining(campaignData: Record<string, unknown>): boolean {
  const budgetTotal = asFiniteNumber(campaignData.budgetTotal);
  if (budgetTotal == null) return true;
  const budgetSpent = asFiniteNumber(campaignData.budgetSpent) ?? 0;
  return budgetSpent < budgetTotal;
}

function campaignHasDailyBudgetRemaining(
  campaignData: Record<string, unknown>,
  todayKey: string
): boolean {
  const budgetDaily = asFiniteNumber(campaignData.budgetDaily);
  if (budgetDaily == null) return true;
  const dailySpendByDate = toRecord(campaignData.dailySpendByDate);
  const spentToday = asFiniteNumber(dailySpendByDate?.[todayKey]) ?? 0;
  return spentToday < budgetDaily;
}

function campaignIsInScheduleWindow(campaignData: Record<string, unknown>, nowMs: number): boolean {
  const startMs = timestampToMillis(campaignData.startDate);
  const endMs = timestampToMillis(campaignData.endDate);
  if (startMs != null && nowMs < startMs) return false;
  if (endMs != null && nowMs > endMs) return false;
  return true;
}

function campaignPassesPacingWindow(campaignData: Record<string, unknown>, nowMs: number): boolean {
  const budgetTotal = asFiniteNumber(campaignData.budgetTotal);
  if (budgetTotal == null || budgetTotal <= 0) return true;
  const budgetSpent = asFiniteNumber(campaignData.budgetSpent) ?? 0;

  const startMs = timestampToMillis(campaignData.startDate);
  const endMs = timestampToMillis(campaignData.endDate);
  if (startMs == null || endMs == null || endMs <= startMs) return true;

  const elapsed = Math.max(0, Math.min(1, (nowMs - startMs) / (endMs - startMs)));
  const expectedSpendByNow = budgetTotal * elapsed;
  const budgetDaily = asFiniteNumber(campaignData.budgetDaily);
  const softBuffer = Math.max(
    budgetTotal * FEATURED_PACING_BUFFER_RATIO,
    budgetDaily != null ? budgetDaily * 0.5 : 0,
    50
  );

  return budgetSpent <= expectedSpendByNow + softBuffer;
}

function extractCampaignIdFromPromotedItem(data: Record<string, unknown>): string | null {
  const direct =
    asTrimmedString(data.campaignId) ||
    asTrimmedString(data.featuredCampaignId) ||
    asTrimmedString(data.sponsoredCampaignId);
  if (direct) return direct;

  const campaignObject = toRecord(data.campaign);
  if (campaignObject) {
    const nested = asTrimmedString(campaignObject.id) || asTrimmedString(campaignObject.campaignId);
    if (nested) return nested;
  }

  const featuredObject = toRecord(data.featured);
  if (featuredObject) {
    const nested = asTrimmedString(featuredObject.campaignId) || asTrimmedString(featuredObject.id);
    if (nested) return nested;
  }

  return null;
}

async function loadActiveCampaignTargetingContexts(
  db: admin.firestore.Firestore,
  nowMs: number
): Promise<Map<string, CampaignTargetingContext>> {
  const todayKey = toDateKeyUTC(nowMs);
  const activeCampaignsSnap = await db
    .collection("campaigns")
    .where("status", "==", "active")
    .limit(300)
    .get();

  const contexts = new Map<string, CampaignTargetingContext>();
  const pendingBySegmentId = new Map<
    string,
    Array<{
      campaignId: string;
      threshold: number;
      frequencyCap: number;
      retailerId: string;
      productMode: "all" | "selected" | "auto";
      productIds: Set<string>;
      recommendedProductIds: Set<string>;
    }>
  >();

  for (const doc of activeCampaignsSnap.docs) {
    const campaignData = (doc.data() || {}) as Record<string, unknown>;
    if (!campaignHasBudgetRemaining(campaignData)) continue;
    if (!campaignHasDailyBudgetRemaining(campaignData, todayKey)) continue;
    if (!campaignPassesPacingWindow(campaignData, nowMs)) continue;
    if (!campaignIsInScheduleWindow(campaignData, nowMs)) continue;

    const retailerId = asTrimmedString(campaignData.retailerId);
    if (!retailerId) continue;

    const threshold = toMatchThreshold(
      campaignData.relevanceThreshold ?? campaignData.segmentMatchThreshold
    );
    const frequencyCap = toFrequencyCap(campaignData.frequencyCap);
    const productMode = toCampaignProductMode(campaignData.productMode);
    const productIds = toStringSet(campaignData.productIds);
    const recommendedProductIds = toStringSet(campaignData.recommendedProductIds);
    const segmentId = asTrimmedString(campaignData.segmentId);
    if (!segmentId) continue;

    const segmentSnapshot = toRecord(campaignData.segmentSnapshot);
    if (segmentSnapshot) {
      contexts.set(doc.id, {
        campaignId: doc.id,
        retailerId,
        segmentId,
        segmentCriteria: toSegmentCriteria(segmentSnapshot),
        threshold,
        frequencyCap,
        recommendedProductIds,
        productMode,
        productIds,
      });
      continue;
    }

    const pending = pendingBySegmentId.get(segmentId) || [];
    pending.push({
      campaignId: doc.id,
      threshold,
      frequencyCap,
      retailerId,
      productMode,
      productIds,
      recommendedProductIds,
    });
    pendingBySegmentId.set(segmentId, pending);
  }

  if (pendingBySegmentId.size > 0) {
    const segmentRefs = Array.from(pendingBySegmentId.keys()).map((id) =>
      db.collection("segments").doc(id)
    );
    const segmentDocs = await db.getAll(...segmentRefs);
    const segmentDataById = new Map<string, Record<string, unknown>>();
    for (const segmentDoc of segmentDocs) {
      if (!segmentDoc.exists) continue;
      segmentDataById.set(segmentDoc.id, (segmentDoc.data() || {}) as Record<string, unknown>);
    }

    for (const [segmentId, campaigns] of pendingBySegmentId.entries()) {
      const segmentData = segmentDataById.get(segmentId);
      if (!segmentData) continue;
      for (const campaign of campaigns) {
        contexts.set(campaign.campaignId, {
          campaignId: campaign.campaignId,
          retailerId: campaign.retailerId,
          segmentId,
          segmentCriteria: toSegmentCriteria(segmentData),
          threshold: campaign.threshold,
          frequencyCap: campaign.frequencyCap,
          recommendedProductIds: campaign.recommendedProductIds,
          productMode: campaign.productMode,
          productIds: campaign.productIds,
        });
      }
    }
  }

  return contexts;
}

function evaluatePromotedItemTargeting(
  itemId: string,
  itemData: Record<string, unknown>,
  campaignContexts: Map<string, CampaignTargetingContext>,
  profile: SessionTargetingProfile
): PromotedTargetingDecision {
  const campaignId = extractCampaignIdFromPromotedItem(itemData);
  if (!campaignId) {
    return {
      eligible: true,
      reason: "legacy_promoted",
      campaignId: null,
      segmentId: null,
      relevanceScore: null,
      threshold: null,
    };
  }

  const campaignContext = campaignContexts.get(campaignId);
  if (!campaignContext) {
    return {
      eligible: false,
      reason: "campaign_not_found",
      campaignId,
      segmentId: null,
      relevanceScore: null,
      threshold: null,
    };
  }

  if (
    campaignContext.productMode === "selected" &&
    campaignContext.productIds.size > 0 &&
    !campaignContext.productIds.has(itemId)
  ) {
    return {
      eligible: false,
      reason: "product_set_mismatch",
      campaignId,
      segmentId: campaignContext.segmentId,
      relevanceScore: null,
      threshold: campaignContext.threshold,
    };
  }

  if (campaignContext.productMode === "auto") {
    const autoSet =
      campaignContext.productIds.size > 0
        ? campaignContext.productIds
        : campaignContext.recommendedProductIds;
    if (autoSet.size > 0 && !autoSet.has(itemId)) {
      return {
        eligible: false,
        reason: "product_set_mismatch",
        campaignId,
        segmentId: campaignContext.segmentId,
        relevanceScore: null,
        threshold: campaignContext.threshold,
      };
    }
  }

  const matchResult = evaluateSegmentMatch(
    campaignContext.segmentCriteria,
    profile,
    campaignContext.threshold
  );
  if (!matchResult.isMatch) {
    return {
      eligible: false,
      reason: "segment_mismatch",
      campaignId,
      segmentId: campaignContext.segmentId,
      relevanceScore: matchResult.overallScore,
      threshold: campaignContext.threshold,
    };
  }

  return {
    eligible: true,
    reason: "eligible_campaign",
    campaignId,
    segmentId: campaignContext.segmentId,
    relevanceScore: matchResult.overallScore,
    threshold: campaignContext.threshold,
  };
}

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

async function loadCreativeHealthScoreByItemId(
  db: admin.firestore.Firestore,
  itemIds: string[]
): Promise<Map<string, number>> {
  const out = new Map<string, { score: number; impressions: number }>();
  if (itemIds.length === 0 || !ENABLE_SCORE_QUALITY_GATE) return new Map<string, number>();

  for (let start = 0; start < itemIds.length; start += 30) {
    const chunk = itemIds.slice(start, start + 30);
    if (chunk.length === 0) continue;
    const scoreSnap = await db
      .collection("scores")
      .where("productId", "in", chunk)
      .limit(400)
      .get();

    for (const scoreDoc of scoreSnap.docs) {
      const data = (scoreDoc.data() || {}) as Record<string, unknown>;
      if (asTrimmedString(data.timeWindow) !== "30d") continue;

      const productId = asTrimmedString(data.productId);
      const creativeHealthScore = asFiniteNumber(data.creativeHealthScore);
      if (!productId || creativeHealthScore == null) continue;

      const impressions = asFiniteNumber(data.impressions) ?? 0;
      const previous = out.get(productId);
      if (!previous || impressions > previous.impressions) {
        out.set(productId, {
          score: creativeHealthScore,
          impressions,
        });
      }
    }
  }

  const flattened = new Map<string, number>();
  out.forEach((value, key) => flattened.set(key, value.score));
  return flattened;
}

function parseOnboardingV2Profile(data: unknown): OnboardingV2Profile | null {
  if (!data || typeof data !== "object") return null;
  const raw = data as Record<string, unknown>;
  const sceneArchetypes = getStringArray(raw.sceneArchetypes);
  const sofaVibes = getStringArray(raw.sofaVibes);
  const constraintsRaw =
    raw.constraints && typeof raw.constraints === "object"
      ? (raw.constraints as Record<string, unknown>)
      : {};
  const constraints: OnboardingV2Constraints = {
    budgetBand: normalizeToken(constraintsRaw.budgetBand) ?? undefined,
    seatCount: normalizeToken(constraintsRaw.seatCount) ?? undefined,
    modularOnly: constraintsRaw.modularOnly === true,
    kidsPets: constraintsRaw.kidsPets === true,
    smallSpace: constraintsRaw.smallSpace === true,
  };
  const derivedRaw =
    raw.derivedProfile && typeof raw.derivedProfile === "object"
      ? (raw.derivedProfile as Record<string, unknown>)
      : null;

  if (sceneArchetypes.length === 0 && sofaVibes.length === 0) return null;

  return {
    sceneArchetypes,
    sofaVibes,
    constraints,
    derivedProfile: derivedRaw
      ? {
          primaryStyle: normalizeToken(derivedRaw.primaryStyle),
          secondaryStyle: normalizeToken(derivedRaw.secondaryStyle),
          confidence:
            typeof derivedRaw.confidence === "number" && Number.isFinite(derivedRaw.confidence)
              ? derivedRaw.confidence
              : undefined,
          explanation: getStringArray(derivedRaw.explanation),
        }
      : undefined,
    pickHash: normalizeToken(raw.pickHash) ?? undefined,
  };
}

function buildOnboardingV2Weights(profile: OnboardingV2Profile): Record<string, number> {
  const next: Record<string, number> = {};
  const add = (key: string, weight: number) => {
    next[key] = Math.max(next[key] || 0, weight);
  };

  for (const sceneToken of profile.sceneArchetypes) {
    const mapped = ONBOARDING_V2_SCENE_SIGNAL_MAP[sceneToken] || [];
    for (const key of mapped) {
      add(key, ONBOARDING_V2_BOOST);
    }
  }

  for (const sofaToken of profile.sofaVibes) {
    const mapped = ONBOARDING_V2_SOFA_SIGNAL_MAP[sofaToken] || [];
    for (const key of mapped) {
      add(key, ONBOARDING_V2_BOOST + 0.25);
    }
  }

  if (profile.constraints.modularOnly) add("feature:modular", ONBOARDING_V2_BOOST + 0.5);
  if (profile.constraints.smallSpace) add("feature:small_space", ONBOARDING_V2_BOOST + 0.4);
  if (profile.constraints.kidsPets) add("material:fabric", ONBOARDING_V2_BOOST);

  return next;
}

const TITLE_COLOR_HINT_TOKENS = new Set([
  "beige", "cream", "white", "offwhite", "ivory", "black", "grey", "gray", "charcoal", "brown",
  "green", "blue", "red", "yellow", "orange", "pink", "purple", "navy", "sand", "stone", "taupe",
  "natural", "oak", "walnut", "ash", "graphite", "multi", "gra", "graa", "svart", "vit", "vitra",
  "beigefargad", "brun", "gron", "bla",
]);
const TITLE_VARIANT_NOISE_TOKENS = new Set([
  "sofa", "soffa", "couch", "set", "module", "modular", "left", "right", "chaise", "corner",
  "sectional", "seat", "seater", "sits", "sit", "with", "and", "the", "for", "new", "inkl",
  "inklusive", "pack", "cm", "m", "l", "xl", "bed", "sleeper", "daybed", "daybeds",
  "sofabed", "futon", "baddsoffa", "baddsoffor", "sovsoffa", "sangsoffa", "hornbaddsoffa",
  "divanbaddsoffa", "langsbaddad",
]);

const TITLE_TOKEN_ALIASES: Record<string, string> = {
  knobb: "knob",
};

const PATH_MODEL_NOISE_TOKENS = new Set([
  ...TITLE_VARIANT_NOISE_TOKENS,
  "produkt",
  "product",
  "products",
  "produkter",
  "vara",
  "artikel",
  "item",
  "model",
  "p",
  "html",
]);

const PATH_CATEGORY_SEGMENT_HINTS = new Set([
  "category",
  "kategori",
  "collections",
  "collection",
  "campaign",
  "kampanj",
  "inspiration",
  "guide",
  "blog",
  "sale",
  "erbjudanden",
  "sortiment",
]);

function normalizeTitleForFamily(title: unknown): string | null {
  if (typeof title !== "string") return null;
  const normalized = title
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return normalized.length > 0 ? normalized : null;
}

function canonicalizeFamilyParts(parts: string[]): string | null {
  const deduped = Array.from(new Set(parts.filter((part) => part.length > 1 && !/^\d+$/.test(part))));
  if (deduped.length === 0) return null;
  return deduped.slice(0, 2).sort().join("_");
}

function titleFamilyKey(title: unknown): string | null {
  const normalized = normalizeTitleForFamily(title);
  if (!normalized) return null;
  const parts = normalized
    .split(" ")
    .map((part) => TITLE_TOKEN_ALIASES[part] || part)
    .filter((p) => p.length > 1 && !/^\d+$/.test(p));
  if (parts.length === 0) return null;

  const informative = parts.filter(
    (part) => !TITLE_COLOR_HINT_TOKENS.has(part) && !TITLE_VARIANT_NOISE_TOKENS.has(part)
  );
  const informativeKey = canonicalizeFamilyParts(informative);
  if (informativeKey) return informativeKey;

  const fallback = parts.filter((part) => !TITLE_VARIANT_NOISE_TOKENS.has(part));
  const fallbackKey = canonicalizeFamilyParts(fallback);
  if (fallbackKey) return fallbackKey;
  return canonicalizeFamilyParts(parts);
}

function canonicalPathModelKey(url: unknown): string | null {
  if (typeof url !== "string") return null;
  const trimmed = url.trim();
  if (!trimmed) return null;
  let segments: string[] = [];
  try {
    const parsed = new URL(trimmed);
    segments = parsed.pathname
      .split("/")
      .map((segment) => normalizeToken(segment))
      .filter((segment): segment is string => segment != null && segment.length > 0);
  } catch {
    return null;
  }
  if (segments.length === 0) return null;

  for (let i = segments.length - 1; i >= 0; i -= 1) {
    let segment = segments[i];
    segment = segment.replace(/\.html?$/i, "");
    if (!segment) continue;
    if (/^[0-9-]+$/.test(segment)) continue;
    if (/^c-\d+$/i.test(segment)) continue;
    if (/^p-[a-z]?\d{4,}/i.test(segment)) continue;
    if (PATH_CATEGORY_SEGMENT_HINTS.has(segment)) continue;

    const parts = segment
      .split(/[-_]+/)
      .map((part) => TITLE_TOKEN_ALIASES[part] || part)
      .filter((part) => part.length > 1 && !/^\d+$/.test(part));
    if (parts.length === 0) continue;

    const informative = parts.filter(
      (part) =>
        !TITLE_COLOR_HINT_TOKENS.has(part) &&
        !TITLE_VARIANT_NOISE_TOKENS.has(part) &&
        !PATH_MODEL_NOISE_TOKENS.has(part)
    );
    const informativeKey = canonicalizeFamilyParts(informative);
    if (informativeKey) return informativeKey;

    const fallback = parts.filter((part) => !PATH_MODEL_NOISE_TOKENS.has(part));
    const fallbackKey = canonicalizeFamilyParts(fallback);
    if (fallbackKey) return fallbackKey;
  }
  return null;
}

function canonicalPathKey(url: unknown): string | null {
  if (typeof url !== "string") return null;
  const trimmed = url.trim();
  if (!trimmed) return null;
  try {
    const parsed = new URL(trimmed);
    const host = normalizeToken(parsed.hostname.replace(/^www\./, ""));
    const path = normalizeToken(
      parsed.pathname
        .replace(/\/+/g, "/")
        .replace(/\/$/, "")
    );
    if (!host || !path) return null;
    return `${host}${path}`;
  } catch {
    return null;
  }
}

function itemModelKey(data: Record<string, unknown>): string | null {
  return (
    normalizeToken(data.familyId) ||
    normalizeToken(data.collectionId) ||
    normalizeToken(data.groupId) ||
    titleFamilyKey(data.title) ||
    canonicalPathModelKey(data.canonicalUrl) ||
    canonicalPathModelKey(data.sourceUrl) ||
    canonicalPathKey(data.canonicalUrl)
  );
}

function itemFamilyKey(data: Record<string, unknown>): string | null {
  const modelKey = itemModelKey(data);
  if (!modelKey) return null;
  const retailer = normalizeToken(data.retailer ?? data.retailerId);
  return retailer ? `${retailer}::${modelKey}` : modelKey;
}

function itemVariantKey(
  data: Record<string, unknown>,
  familyKey?: string | null,
  modelKey?: string | null
): string | null {
  const base = modelKey ?? familyKey ?? itemModelKey(data) ?? itemFamilyKey(data);
  if (!base) return null;
  const classification = toRecord(data.classification);
  const color = normalizeToken(data.colorFamily) || "unknown";
  const seatCountBucket = normalizeToken(data.seatCountBucket ?? classification?.seatCountBucket) || "unknown";
  return `${base}::${color}::${seatCountBucket}`;
}

function sourceHostKey(url: unknown): string | null {
  if (typeof url !== "string") return null;
  const trimmed = url.trim();
  if (!trimmed) return null;
  try {
    const parsed = new URL(trimmed);
    return normalizeToken(parsed.hostname.replace(/^www\./, ""));
  } catch {
    return null;
  }
}

function itemSourceKey(data: Record<string, unknown>): string | null {
  return (
    normalizeToken(data.sourceId) ||
    normalizeToken(data.retailer) ||
    normalizeToken(data.retailerId) ||
    sourceHostKey(data.canonicalUrl) ||
    sourceHostKey(data.sourceUrl)
  );
}

function extractItemImageUrls(data: Record<string, unknown>): string[] {
  const rawImages = Array.isArray(data.images) ? data.images : [];
  const urls: string[] = [];
  const seen = new Set<string>();
  for (const entry of rawImages) {
    let url: string | null = null;
    if (typeof entry === "string") {
      url = asTrimmedString(entry);
    } else {
      const record = toRecord(entry);
      if (record) url = asTrimmedString(record.url);
    }
    if (!url || seen.has(url)) continue;
    seen.add(url);
    urls.push(url);
  }
  return urls;
}

function selectedImageSceneType(data: Record<string, unknown>): string | null {
  const imageValidation = toRecord(data.imageValidation);
  const creativeHealth = toRecord(data.creativeHealth);
  const primaryImage = toRecord(imageValidation?.primaryImage);
  return (
    normalizeToken(imageValidation?.selectedSceneType) ||
    normalizeToken(creativeHealth?.sceneType) ||
    normalizeToken(primaryImage?.sceneType)
  );
}

function passesImageDisplayGate(data: Record<string, unknown>): boolean {
  const imageUrls = extractItemImageUrls(data);
  if (imageUrls.length === 0) return false;

  const criticalIssues = new Set([
    "no-images",
    "no-valid-images",
    "broken",
    "validation-error",
    "fetch-failed",
    "non-image-response",
    "domain-blocked",
  ]);

  const imageValidation = toRecord(data.imageValidation);
  const creativeHealth = toRecord(data.creativeHealth);
  const validationIssuesRaw = Array.isArray(imageValidation?.issues) ? imageValidation?.issues : [];
  const creativeIssuesRaw = Array.isArray(creativeHealth?.issues) ? creativeHealth?.issues : [];
  const issueTokens = [...validationIssuesRaw, ...creativeIssuesRaw]
    .map((issue) => normalizeToken(issue))
    .filter((issue): issue is string => issue != null);

  if (issueTokens.some((issue) => criticalIssues.has(issue))) return false;

  const validated = imageValidation?.validated === true;
  const validImageCount = asFiniteNumber(imageValidation?.validImageCount);
  if (validated && validImageCount != null && validImageCount <= 0) return false;

  return true;
}

function passesSoftRepeatQualityGate(
  data: Record<string, unknown>,
  creativeScoreByItemId?: Map<string, number>
): boolean {
  const itemId = asTrimmedString(data.id);
  if (itemId && creativeScoreByItemId?.has(itemId)) {
    const score = creativeScoreByItemId.get(itemId)!;
    return score >= SOFT_REPEAT_MIN_CREATIVE_SCORE;
  }

  const creativeHealth = toRecord(data.creativeHealth);
  const explicitScore = asFiniteNumber(
    creativeHealth?.score ?? data.creativeHealthScore ?? data.imageQualityScore ?? data.qualityScore
  );
  if (explicitScore != null) {
    return explicitScore >= SOFT_REPEAT_MIN_CREATIVE_SCORE;
  }

  const imageUrls = extractItemImageUrls(data);
  const hasEnoughImages = imageUrls.length >= SOFT_REPEAT_MIN_IMAGE_COUNT;
  const hasTitle = asTrimmedString(data.title) != null;
  const hasSource = asTrimmedString(data.canonicalUrl) != null || asTrimmedString(data.sourceUrl) != null;
  return hasEnoughImages && hasTitle && hasSource;
}

function minStyleDistanceToFamily(
  candidate: Record<string, unknown>,
  familyItems: Array<Record<string, unknown>>
): number | null {
  if (familyItems.length === 0) return null;
  const candidateTokens = buildStyleTokenSet(candidate);
  if (candidateTokens.size < 2) return null;

  let minDistance: number | null = null;
  for (const existing of familyItems) {
    const existingTokens = buildStyleTokenSet(existing);
    if (existingTokens.size < 2) continue;
    const distance = jaccardDistance(candidateTokens, existingTokens);
    minDistance = minDistance == null ? distance : Math.min(minDistance, distance);
  }

  if (minDistance == null) return null;
  return Number(minDistance.toFixed(4));
}

function spreadDeferredNearDuplicates(
  deferred: Array<Record<string, unknown>>
): Array<Record<string, unknown>> {
  if (deferred.length < 2) return deferred;
  const buckets = new Map<string, Array<Record<string, unknown>>>();
  deferred.forEach((item, index) => {
    const key =
      itemModelKey(item) ||
      itemFamilyKey(item) ||
      asTrimmedString(item.id) ||
      `unknown_${index}`;
    const bucket = buckets.get(key) || [];
    bucket.push(item);
    buckets.set(key, bucket);
  });

  const orderedKeys = Array.from(buckets.keys());
  const output: Array<Record<string, unknown>> = [];
  while (output.length < deferred.length) {
    orderedKeys.sort((a, b) => (buckets.get(b)?.length || 0) - (buckets.get(a)?.length || 0));
    let advanced = false;
    for (const key of orderedKeys) {
      const bucket = buckets.get(key);
      if (!bucket || bucket.length === 0) continue;
      output.push(bucket.shift()!);
      advanced = true;
    }
    if (!advanced) break;
  }
  return output;
}

function spreadDeferredBySource(
  deferred: Array<Record<string, unknown>>
): Array<Record<string, unknown>> {
  if (deferred.length < 2) return deferred;
  const buckets = new Map<string, Array<Record<string, unknown>>>();
  deferred.forEach((item, index) => {
    const key = itemSourceKey(item) || itemFamilyKey(item) || asTrimmedString(item.id) || `unknown_${index}`;
    const bucket = buckets.get(key) || [];
    bucket.push(item);
    buckets.set(key, bucket);
  });

  const orderedKeys = Array.from(buckets.keys());
  const output: Array<Record<string, unknown>> = [];
  while (output.length < deferred.length) {
    orderedKeys.sort((a, b) => (buckets.get(b)?.length || 0) - (buckets.get(a)?.length || 0));
    let advanced = false;
    for (const key of orderedKeys) {
      const bucket = buckets.get(key);
      if (!bucket || bucket.length === 0) continue;
      output.push(bucket.shift()!);
      advanced = true;
    }
    if (!advanced) break;
  }
  return output;
}

function applyNearDuplicateExplorationPolicy(
  rankedItems: Array<Record<string, unknown>>,
  limit: number,
  creativeScoreByItemId?: Map<string, number>
): { items: Array<Record<string, unknown>>; stats: ExplorationDiversityStats } {
  const shaped: Array<Record<string, unknown>> = [];
  const deferred: Array<Record<string, unknown>> = [];
  const familyToItems = new Map<string, Array<Record<string, unknown>>>();
  const modelToItems = new Map<string, Array<Record<string, unknown>>>();
  const familyLastPosition = new Map<string, number>();
  const modelLastPosition = new Map<string, number>();
  const seenVariantTop8 = new Set<string>();
  let softRepeatsUsed = 0;
  const softWindowTopN = Math.max(
    SOFT_NEAR_DUPLICATE_TOP_N,
    Math.min(rankedItems.length, Math.max(0, limit) + SOFT_NEAR_DUPLICATE_MAX_REPEATS)
  );

  const stats: ExplorationDiversityStats = {
    droppedHardNearDuplicate: 0,
    droppedSoftNearDuplicate: 0,
    droppedSoftForQuality: 0,
    droppedSoftForStyleDistance: 0,
    allowedSoftNearDuplicate: 0,
  };

  for (const item of rankedItems) {
    const familyKey = itemFamilyKey(item);
    const modelKey = itemModelKey(item);
    const variantKey = itemVariantKey(item, familyKey, modelKey);
    const projectedPosition = shaped.length + 1;
    const withinHardWindow = projectedPosition <= HARD_NEAR_DUPLICATE_TOP_N;
    const withinSoftWindow = projectedPosition <= softWindowTopN;
    const familyItems = familyKey ? familyToItems.get(familyKey) || [] : [];
    const modelItems = modelKey ? modelToItems.get(modelKey) || [] : [];
    const nearDuplicateItems = [...familyItems, ...modelItems];
    const nearDuplicateSeen = nearDuplicateItems.length > 0;

    if (withinHardWindow && nearDuplicateSeen) {
      stats.droppedHardNearDuplicate += 1;
      deferred.push(item);
      continue;
    }
    if (withinHardWindow && variantKey && seenVariantTop8.has(variantKey)) {
      stats.droppedHardNearDuplicate += 1;
      deferred.push(item);
      continue;
    }

    if (withinSoftWindow && nearDuplicateSeen) {
      if (softRepeatsUsed >= SOFT_NEAR_DUPLICATE_MAX_REPEATS) {
        stats.droppedSoftNearDuplicate += 1;
        deferred.push(item);
        continue;
      }
      if (!passesSoftRepeatQualityGate(item, creativeScoreByItemId)) {
        stats.droppedSoftForQuality += 1;
        deferred.push(item);
        continue;
      }
      const minDistance = minStyleDistanceToFamily(item, nearDuplicateItems);
      if (minDistance != null && minDistance < SOFT_NEAR_DUPLICATE_MIN_STYLE_DISTANCE) {
        stats.droppedSoftForStyleDistance += 1;
        deferred.push(item);
        continue;
      }

      // Keep near-duplicate families spaced out in the first cards so the deck
      // feels exploratory instead of clustered by color/variant.
      const familyGap = familyKey ? projectedPosition - (familyLastPosition.get(familyKey) || 0) : Number.MAX_SAFE_INTEGER;
      const modelGap = modelKey ? projectedPosition - (modelLastPosition.get(modelKey) || 0) : Number.MAX_SAFE_INTEGER;
      const minGap = Math.min(familyGap, modelGap);
      if (minGap < SOFT_NEAR_DUPLICATE_MIN_GAP) {
        stats.droppedSoftNearDuplicate += 1;
        deferred.push(item);
        continue;
      }

      softRepeatsUsed += 1;
      stats.allowedSoftNearDuplicate += 1;
    }

    shaped.push(item);
    const acceptedPosition = shaped.length;
    if (familyKey) {
      familyToItems.set(familyKey, [...familyItems, item]);
      familyLastPosition.set(familyKey, acceptedPosition);
    }
    if (modelKey) {
      modelToItems.set(modelKey, [...modelItems, item]);
      modelLastPosition.set(modelKey, acceptedPosition);
    }
    if (withinHardWindow && variantKey) {
      seenVariantTop8.add(variantKey);
    }
  }

  const spreadDeferred = spreadDeferredNearDuplicates(deferred);

  return {
    items: [...shaped, ...spreadDeferred],
    stats,
  };
}

function applySourceDiversityPolicy(
  rankedItems: Array<Record<string, unknown>>,
  limit: number
): { items: Array<Record<string, unknown>>; stats: SourceDiversityStats } {
  const shaped: Array<Record<string, unknown>> = [];
  const deferred: Array<Record<string, unknown>> = [];
  const sourceCounts = new Map<string, number>();
  const capWindowTopN = Math.max(SOURCE_DIVERSITY_TOP_N, Math.min(rankedItems.length, Math.max(limit, 0)));

  const stats: SourceDiversityStats = {
    deferredForSourceCap: 0,
  };

  for (const item of rankedItems) {
    const sourceKey = itemSourceKey(item);
    const projectedPosition = shaped.length + 1;
    const withinCapWindow = projectedPosition <= capWindowTopN;

    if (withinCapWindow && sourceKey) {
      const currentCount = sourceCounts.get(sourceKey) || 0;
      if (currentCount >= SOURCE_DIVERSITY_MAX_PER_SOURCE) {
        stats.deferredForSourceCap += 1;
        deferred.push(item);
        continue;
      }
      sourceCounts.set(sourceKey, currentCount + 1);
    }

    shaped.push(item);
  }

  return {
    items: [...shaped, ...spreadDeferredBySource(deferred)],
    stats,
  };
}

function applyTopModelDedupePolicy(
  rankedItems: Array<Record<string, unknown>>,
  limit: number
): { items: Array<Record<string, unknown>>; stats: ModelDiversityStats } {
  const shaped: Array<Record<string, unknown>> = [];
  const deferred: Array<Record<string, unknown>> = [];
  const modelCounts = new Map<string, number>();
  const capWindowTopN = Math.max(TOP_MODEL_DEDUPE_TOP_N, Math.min(rankedItems.length, Math.max(limit, 0)));

  const stats: ModelDiversityStats = {
    deferredForModelCap: 0,
  };

  for (const item of rankedItems) {
    const projectedPosition = shaped.length + 1;
    const withinCapWindow = projectedPosition <= capWindowTopN;
    const modelKey = itemModelKey(item) || titleFamilyKey(item.title);

    if (withinCapWindow && modelKey) {
      const currentCount = modelCounts.get(modelKey) || 0;
      if (currentCount >= TOP_MODEL_DEDUPE_MAX_PER_MODEL) {
        stats.deferredForModelCap += 1;
        deferred.push(item);
        continue;
      }
      modelCounts.set(modelKey, currentCount + 1);
    }

    shaped.push(item);
  }

  return {
    items: [...shaped, ...spreadDeferredNearDuplicates(deferred)],
    stats,
  };
}

function computeSameFamilyTop8Rate(items: Array<Record<string, unknown>>): number {
  const top = items.slice(0, 8);
  const seen = new Set<string>();
  let familyCount = 0;
  let duplicateCount = 0;

  for (const item of top) {
    const family = itemFamilyKey(item) || titleFamilyKey(item.title);
    if (!family) continue;
    familyCount += 1;
    if (seen.has(family)) {
      duplicateCount += 1;
    } else {
      seen.add(family);
    }
  }

  if (familyCount === 0) return 0;
  return Number((duplicateCount / familyCount).toFixed(4));
}

function computeSourceConcentrationTop8(items: Array<Record<string, unknown>>): number {
  const top = items.slice(0, 8);
  if (top.length === 0) return 0;
  const counts = new Map<string, number>();
  for (const item of top) {
    const source = itemSourceKey(item) || "unknown";
    counts.set(source, (counts.get(source) || 0) + 1);
  }
  const maxCount = Math.max(0, ...Array.from(counts.values()));
  return Number((maxCount / top.length).toFixed(4));
}

function computeSourceDiversityTop8(items: Array<Record<string, unknown>>): number {
  const top = items.slice(0, 8);
  if (top.length === 0) return 0;
  const sources = new Set<string>();
  for (const item of top) {
    const source = itemSourceKey(item);
    if (source) sources.add(source);
  }
  return sources.size;
}

function buildStyleTokenSet(data: Record<string, unknown>): Set<string> {
  const tokens = new Set<string>();
  const classification = toRecord(data.classification);
  for (const tag of getStringArray(data.styleTags)) tokens.add(`style:${tag}`);
  const primaryCategory = normalizeToken(
    data.primaryCategory ?? classification?.primaryCategory ?? classification?.predictedCategory
  );
  if (primaryCategory) tokens.add(`primary:${primaryCategory}`);
  const material = normalizeToken(data.material);
  if (material) tokens.add(`material:${material}`);
  const color = normalizeToken(data.colorFamily);
  if (color) tokens.add(`color:${color}`);
  const sofaTypeShape = normalizeToken(data.sofaTypeShape ?? classification?.sofaTypeShape);
  if (sofaTypeShape) tokens.add(`sofa_shape:${sofaTypeShape}`);
  const sofaFunction = normalizeToken(data.sofaFunction ?? classification?.sofaFunction);
  if (sofaFunction) tokens.add(`sofa_function:${sofaFunction}`);
  const seatCountBucket = normalizeToken(data.seatCountBucket ?? classification?.seatCountBucket);
  if (seatCountBucket) tokens.add(`seat_bucket:${seatCountBucket}`);
  const environment = normalizeToken(data.environment ?? classification?.environment);
  if (environment && environment !== "unknown") tokens.add(`environment:${environment}`);
  const subCategory = normalizeToken(data.subCategory);
  if (subCategory) tokens.add(`subcat:${subCategory}`);
  for (const roomType of getStringArray(data.roomTypes)) tokens.add(`room:${roomType}`);
  if (data.modular === true) tokens.add("feature:modular");
  if (data.smallSpaceFriendly === true) tokens.add("feature:small_space");
  return tokens;
}

function jaccardDistance(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 0;
  let intersection = 0;
  for (const token of a) {
    if (b.has(token)) intersection += 1;
  }
  const union = a.size + b.size - intersection;
  if (union === 0) return 0;
  return 1 - intersection / union;
}

function computeMinStyleDistanceTop4(items: Array<Record<string, unknown>>): number | null {
  const top = items.slice(0, 4);
  const tokenSets = top
    .map((item) => buildStyleTokenSet(item))
    .filter((tokens) => tokens.size >= 2);
  if (tokenSets.length < 2) return null;

  let minDistance = 1;
  for (let i = 0; i < tokenSets.length; i += 1) {
    for (let j = i + 1; j < tokenSets.length; j += 1) {
      minDistance = Math.min(minDistance, jaccardDistance(tokenSets[i], tokenSets[j]));
    }
  }
  return Number(minDistance.toFixed(4));
}

function getFeaturedRetailerId(item: Record<string, unknown>): string | null {
  return asTrimmedString(item.featuredRetailerId) || asTrimmedString(item.retailer);
}

function deriveFeaturedFrequencyCap(campaignContexts: Map<string, CampaignTargetingContext>): number {
  let cap = DEFAULT_FEATURED_FREQUENCY_CAP;
  for (const context of campaignContexts.values()) {
    cap = Math.min(cap, context.frequencyCap);
  }
  return Math.max(2, cap);
}

function applyFeaturedServingPolicy(
  rankedItems: Array<Record<string, unknown>>,
  limit: number,
  frequencyCap: number,
  retailerCooldown: number
): { items: Array<Record<string, unknown>>; stats: FeaturedServingStats } {
  const cappedLimit = Math.max(0, Math.min(limit, rankedItems.length));
  if (cappedLimit === 0) {
    return {
      items: [],
      stats: {
        configuredFrequencyCap: frequencyCap,
        maxFeaturedSlots: 0,
        featuredInSourceRank: 0,
        featuredServed: 0,
        droppedForFrequencyCap: 0,
        droppedForDiversity: 0,
        fallbackToOrganicCount: 0,
        overflowFeaturedUsed: 0,
      },
    };
  }

  const organicQueue = rankedItems.filter((item) => item.isFeatured !== true);
  const featuredQueue = rankedItems.filter((item) => item.isFeatured === true);
  const featuredInSourceRank = featuredQueue.length;
  const recentFeaturedRetailers: string[] = [];
  const maxFeaturedSlots = Math.floor(cappedLimit / Math.max(2, frequencyCap));

  let featuredServed = 0;
  let droppedForDiversity = 0;
  let fallbackToOrganicCount = 0;
  const overflowFeaturedUsed = 0;

  const popFeatured = (): Record<string, unknown> | null => {
    if (featuredQueue.length === 0) return null;
    for (let idx = 0; idx < featuredQueue.length; idx += 1) {
      const candidate = featuredQueue[idx];
      const retailerId = getFeaturedRetailerId(candidate);
      if (retailerId && recentFeaturedRetailers.includes(retailerId)) {
        droppedForDiversity += 1;
        continue;
      }
      featuredQueue.splice(idx, 1);
      return candidate;
    }
    // Strict diversity behavior: if no featured candidate passes cooldown, use organic.
    return null;
  };

  const result: Array<Record<string, unknown>> = [];
  for (let position = 1; position <= cappedLimit; position += 1) {
    const isFeaturedSlot =
      position % Math.max(2, frequencyCap) === 0 && featuredServed < maxFeaturedSlots;

    let picked: Record<string, unknown> | null = null;
    if (isFeaturedSlot) {
      picked = popFeatured();
    }

    if (!picked && organicQueue.length > 0) {
      picked = organicQueue.shift() || null;
      if (isFeaturedSlot) fallbackToOrganicCount += 1;
    }

    if (!picked) break;

    if (picked.isFeatured === true) {
      featuredServed += 1;
      const retailerId = getFeaturedRetailerId(picked);
      if (retailerId) {
        recentFeaturedRetailers.push(retailerId);
        if (recentFeaturedRetailers.length > retailerCooldown) {
          recentFeaturedRetailers.shift();
        }
      }
    }

    result.push(picked);
  }

  return {
    items: result,
    stats: {
      configuredFrequencyCap: frequencyCap,
      maxFeaturedSlots,
      featuredInSourceRank,
      featuredServed,
      droppedForFrequencyCap: Math.max(0, featuredInSourceRank - featuredServed),
      droppedForDiversity,
      fallbackToOrganicCount,
      overflowFeaturedUsed,
    },
  };
}

async function logFeaturedImpressionsAndUpdateCampaigns(
  db: admin.firestore.Firestore,
  sessionId: string,
  requestId: string,
  items: Array<Record<string, unknown>>,
  nowMs: number
): Promise<FeaturedLoggingStats> {
  const featuredItems = items
    .map((item, index) => ({ item, positionInDeck: index + 1 }))
    .filter(({ item }) => item.isFeatured === true);
  if (featuredItems.length === 0) {
    return { loggedCount: 0, updatedCampaignCount: 0, estimatedSpendSEK: 0 };
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const dayKey = toDateKeyUTC(nowMs);
  const batch = db.batch();
  const campaignAggregates = new Map<string, { impressions: number; spend: number }>();

  for (const { item, positionInDeck } of featuredItems) {
    const itemId = asTrimmedString(item.id);
    if (!itemId) continue;

    const campaignId = asTrimmedString(item.campaignId);
    const segmentId = asTrimmedString(item.segmentId);
    const retailerId = getFeaturedRetailerId(item);
    const relevanceScore = asFiniteNumber(item.featuredRelevanceScore);
    const matchThreshold = asFiniteNumber(item.featuredMatchThreshold);

    const impressionRef = db.collection("featuredImpressions").doc();
    batch.set(impressionRef, {
      id: impressionRef.id,
      sessionId,
      requestId,
      itemId,
      campaignId: campaignId ?? null,
      segmentId: segmentId ?? null,
      retailerId: retailerId ?? null,
      positionInDeck,
      relevanceScore: relevanceScore ?? null,
      matchThreshold: matchThreshold ?? null,
      isFeatured: true,
      source: campaignId ? "campaign" : "legacy",
      createdAt: now,
    });

    if (campaignId) {
      const prev = campaignAggregates.get(campaignId) || { impressions: 0, spend: 0 };
      prev.impressions += 1;
      prev.spend += FEATURED_COST_PER_IMPRESSION_SEK;
      campaignAggregates.set(campaignId, prev);
    }
  }

  for (const [campaignId, aggregate] of campaignAggregates.entries()) {
    const updates: Record<string, unknown> = {
      impressions: admin.firestore.FieldValue.increment(aggregate.impressions),
      featuredImpressions: admin.firestore.FieldValue.increment(aggregate.impressions),
      budgetSpent: admin.firestore.FieldValue.increment(aggregate.spend),
      lastImpressionAt: now,
      updatedAt: now,
    };
    updates[`dailyImpressionsByDate.${dayKey}`] = admin.firestore.FieldValue.increment(
      aggregate.impressions
    );
    updates[`dailySpendByDate.${dayKey}`] = admin.firestore.FieldValue.increment(aggregate.spend);
    batch.set(db.collection("campaigns").doc(campaignId), updates, { merge: true });
  }

  await batch.commit();
  const estimatedSpendSEK = Array.from(campaignAggregates.values()).reduce(
    (sum, entry) => sum + entry.spend,
    0
  );
  return {
    loggedCount: featuredItems.length,
    updatedCampaignCount: campaignAggregates.size,
    estimatedSpendSEK: Number(estimatedSpendSEK.toFixed(2)),
  };
}

export async function deckGet(req: Request, res: Response): Promise<void> {
  const startedAtMs = Date.now();
  const sessionId = req.query.sessionId as string;
  const requested = parseInt(String(req.query.limit || DEFAULT_LIMIT), 10) || DEFAULT_LIMIT;
  const limit = Math.min(Math.max(0, requested), MAX_LIMIT);
  const filtersJson = req.query.filters as string | undefined;
  const debugMode = req.query.debug === "true";
  const providedRequestId = typeof req.query.requestId === "string" ? req.query.requestId.trim() : "";
  const requestId = providedRequestId.length > 0 ? providedRequestId : createDeckRequestId(sessionId || "unknown");
  const logDeckEvent = (eventName: string, payload: Record<string, unknown>): void => {
    console.info(eventName, {
      requestId,
      sessionId: sessionId || null,
      ...payload,
    });
  };

  if (!sessionId) {
    logDeckEvent("deck_request_rejected", {
      reason: "missing_session_id",
      latencyMs: Date.now() - startedAtMs,
    });
    res.status(400).json({ error: "sessionId required" });
    return;
  }

  try {
    const db = admin.firestore();

    const [
      swipesSnap,
      _likesSnap,
      sessionSnap,
      weightsSnap,
      onboardingPicksSnap,
      onboardingV2Snap,
    ] = await Promise.all([
      // Only exclude swipes from the last 7 days so items can be recycled.
      // This prevents running out of cards when the catalog is small.
      (() => {
        const recycleAfterDays = parseInt(process.env.DECK_RECYCLE_AFTER_DAYS || "7", 10);
        const recycleAfter = new Date(Date.now() - recycleAfterDays * 24 * 60 * 60 * 1000);
        return db.collection("swipes")
          .where("sessionId", "==", sessionId)
          .where("createdAt", ">", recycleAfter)
          .orderBy("createdAt", "desc")
          .limit(500)
          .get();
      })(),
      db.collection("likes").where("sessionId", "==", sessionId).get(),
      db.collection("anonSessions").doc(sessionId).get(),
      db.collection("anonSessions").doc(sessionId).collection("preferenceWeights").doc("weights").get(),
      db.collection("onboardingPicks").doc(sessionId).get(),
      db.collection("onboardingProfiles").doc(sessionId).get(),
    ]);

  // Start with existing preference weights
  let preferenceWeights = weightsSnap.exists
    ? (weightsSnap.data() as Record<string, number>) || {}
    : (sessionSnap.exists ? (sessionSnap.data()?.preferenceWeights as Record<string, number> | undefined) : undefined) || {};

  const sessionData = (sessionSnap.data() || {}) as Record<string, unknown>;
  const onboardingPicksData = (onboardingPicksSnap.data() || {}) as Record<string, unknown>;
  const onboardingExtractedAttributes =
    onboardingPicksData.extractedAttributes && typeof onboardingPicksData.extractedAttributes === "object"
      ? (onboardingPicksData.extractedAttributes as Record<string, unknown>)
      : null;

  const onboardingV2Profile = onboardingV2Snap.exists
    ? parseOnboardingV2Profile(onboardingV2Snap.data())
    : null;

  // Cold-start: if user has onboarding picks but few/no swipes, boost attributes from picked items
  const hasLimitedHistory = swipesSnap.size < 5;
  if (hasLimitedHistory && onboardingV2Profile != null) {
    const v2Weights = buildOnboardingV2Weights(onboardingV2Profile);
    // Merge: existing weights take precedence over onboarding priors.
    preferenceWeights = { ...v2Weights, ...preferenceWeights };
  }

  if (hasLimitedHistory && onboardingPicksSnap.exists) {
    if (onboardingExtractedAttributes) {
      const coldStartWeights: Record<string, number> = {};

      if (Array.isArray(onboardingExtractedAttributes.styleTags)) {
        for (const tag of onboardingExtractedAttributes.styleTags) {
          coldStartWeights[tag] = ONBOARDING_PICK_BOOST;
        }
      }

      if (Array.isArray(onboardingExtractedAttributes.materials)) {
        for (const material of onboardingExtractedAttributes.materials) {
          coldStartWeights[`material:${material}`] = ONBOARDING_PICK_BOOST;
        }
      }

      if (Array.isArray(onboardingExtractedAttributes.colorFamilies)) {
        for (const color of onboardingExtractedAttributes.colorFamilies) {
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
      logDeckEvent("deck_request_rejected", {
        reason: "invalid_filters_json",
        latencyMs: Date.now() - startedAtMs,
      });
      res.status(400).json({ error: "filters must be valid JSON" });
      return;
    }
  }

  const sizeClassFilter = typeof filters.sizeClass === "string" ? filters.sizeClass : undefined;
  const colorFamilyFilter = typeof filters.colorFamily === "string" ? filters.colorFamily : undefined;
  const newUsedFilter = typeof filters.newUsed === "string" ? filters.newUsed : undefined;
  const primaryCategoryFilter = normalizeToken(filters.primaryCategory);
  const sofaTypeShapeFilter = normalizeToken(filters.sofaTypeShape);
  const sofaFunctionFilter = normalizeToken(filters.sofaFunction);
  const seatCountBucketFilter = normalizeToken(filters.seatCountBucket);
  const environmentFilter = normalizeToken(filters.environment);
  const subCategoryFilter = typeof filters.subCategory === "string" ? filters.subCategory : undefined;
  const roomTypeFilter = typeof filters.roomType === "string" ? filters.roomType : undefined;
  const explicitPriceMin = asFiniteNumber(filters.priceMin);
  const explicitPriceMax = asFiniteNumber(filters.priceMax);
  const onboardingV2Constraints = onboardingV2Profile?.constraints ?? {};
  const onboardingConstraintsMode =
    swipesSnap.size >= ONBOARDING_HARD_CONSTRAINT_SWIPE_THRESHOLD
      ? "hard"
      : swipesSnap.size >= ONBOARDING_MEDIUM_CONSTRAINT_SWIPE_THRESHOLD
        ? "medium"
        : "soft";
  const applyOnboardingMediumOrHardConstraints =
    onboardingConstraintsMode === "medium" || onboardingConstraintsMode === "hard";
  const applyOnboardingHardConstraints = onboardingConstraintsMode === "hard";
  const onboardingSeatBuckets =
    applyOnboardingMediumOrHardConstraints && onboardingV2Constraints.seatCount != null
      ? ONBOARDING_V2_SEAT_BUCKETS[onboardingV2Constraints.seatCount] || []
      : [];
  const onboardingSeatSubcats =
    applyOnboardingMediumOrHardConstraints && onboardingV2Constraints.seatCount != null
      ? ONBOARDING_V2_SEAT_SUBCATEGORIES[onboardingV2Constraints.seatCount] || []
      : [];
  const requireModular =
    applyOnboardingMediumOrHardConstraints && onboardingV2Constraints.modularOnly === true;
  const requireSmallSpace =
    applyOnboardingMediumOrHardConstraints && onboardingV2Constraints.smallSpace === true;

  // Apply onboarding budget as hard filter only after enough behavior history.
  let budgetMin: number | undefined;
  let budgetMax: number | undefined;
  if (explicitPriceMin == null && explicitPriceMax == null && applyOnboardingHardConstraints) {
    const budgetBand = onboardingV2Constraints.budgetBand;
    if (budgetBand && ONBOARDING_V2_BUDGET_BANDS[budgetBand]) {
      const range = ONBOARDING_V2_BUDGET_BANDS[budgetBand];
      budgetMin = range.min;
      budgetMax = range.max;
    } else if (onboardingPicksSnap.exists) {
      if (typeof onboardingPicksData.budgetMin === "number") budgetMin = onboardingPicksData.budgetMin;
      if (typeof onboardingPicksData.budgetMax === "number") budgetMax = onboardingPicksData.budgetMax;
    }
  }
  const minPriceFilter = explicitPriceMin ?? budgetMin;
  const maxPriceFilter = explicitPriceMax ?? budgetMax;

  const onboardingStyleTokens = [
    ...getStringArray(onboardingExtractedAttributes?.styleTags),
    ...getStringArray(onboardingV2Profile?.sceneArchetypes),
    ...getStringArray(onboardingV2Profile?.sofaVibes),
    ...(onboardingV2Profile?.derivedProfile?.primaryStyle != null
      ? [onboardingV2Profile.derivedProfile.primaryStyle]
      : []),
    ...(onboardingV2Profile?.derivedProfile?.secondaryStyle != null
      ? [onboardingV2Profile.derivedProfile.secondaryStyle]
      : []),
  ];

  const inferredSizeClasses: string[] = [];
  if (onboardingV2Constraints.seatCount === "2") inferredSizeClasses.push("small");
  if (onboardingV2Constraints.seatCount === "3") inferredSizeClasses.push("medium");
  if (onboardingV2Constraints.seatCount === "4_plus") inferredSizeClasses.push("large");
  if (onboardingV2Constraints.smallSpace === true) {
    inferredSizeClasses.push("small");
    inferredSizeClasses.push("compact");
  }

  const sessionTargetingProfile = buildSessionTargetingProfile({
    locale: asTrimmedString(req.query.locale) || asTrimmedString(sessionData.locale),
    geoRegion: asTrimmedString(req.query.geoRegion) || asTrimmedString(sessionData.geoRegion),
    geoCity: asTrimmedString(req.query.geoCity) || asTrimmedString(sessionData.geoCity),
    geoPostcode: asTrimmedString(req.query.geoPostcode) || asTrimmedString(sessionData.geoPostcode),
    preferenceWeights,
    onboardingStyleTokens,
    preferredBudgetMin: minPriceFilter ?? null,
    preferredBudgetMax: maxPriceFilter ?? null,
    explicitSizeClass: sizeClassFilter ?? null,
    inferredSizeClasses,
  });

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
  const onboardingPickHash = onboardingV2Profile?.pickHash ||
    (onboardingPicksSnap.exists ? (onboardingPicksSnap.data()?.pickHash as string | undefined) : undefined);
  if (onboardingPickHash) {
    const itemScoresFromSimilar = await getPersonaSignals(onboardingPickHash);
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

  // Multi-queue retrieval sources: promoted feed + recency feed (+ persona item IDs).
  // The deck surface determines which items are eligible (default: sofas only).
  const deckSurface = (req.query.surface as string) || "swiper_deck_sofas";
  const useGold = process.env.DECK_USE_GOLD !== "false";
  const [goldSnapOrNull, catalogSnap, activeCampaignTargeting] = await Promise.all([
    useGold
      ? db
          .collection("goldItems")
          .where("isActive", "==", true)
          .where("eligibleSurfaces", "array-contains", deckSurface)
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
    loadActiveCampaignTargetingContexts(db, Date.now()),
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
  const deferredStudioCutoutDocs = new Map<QueueName, admin.firestore.DocumentSnapshot[]>();
  for (const queue of QUEUE_ORDER) {
    deferredStudioCutoutDocs.set(queue, []);
  }
  const deferredStudioCutoutIds = new Set<string>();
  let deferredStudioCutoutCount = 0;
  let recoveredStudioCutoutCount = 0;

  const acceptedIds = new Set<string>();
  const seenCanonicals = new Set<string>();
  const seenFamilyKeys = new Set<string>();
  const seenModelKeys = new Set<string>();
  let droppedForFamilyDedupe = 0;
  const candidateDocs: admin.firestore.DocumentSnapshot[] = [];
  const candidateQueueById = new Map<string, QueueName>();
  const featuredContextByItemId = new Map<
    string,
    {
      campaignId: string;
      retailerId: string;
      segmentId: string;
      relevanceScore: number;
      threshold: number;
    }
  >();
  const featuredTargetingStats = {
    legacyPromotedAccepted: 0,
    campaignMatched: 0,
    campaignNotFound: 0,
    campaignSegmentMismatch: 0,
    campaignProductSetMismatch: 0,
  };

  // Categories allowed on the sofa deck surface
  const SOFA_SURFACE_CATEGORIES = new Set(["sofa", "corner_sofa", "bed_sofa"]);
  // Quick title keywords to identify sofas in unclassified items
  const SOFA_TITLE_KEYWORDS = [
    "soffa", "soffor", "sofa", "sofás", "sofá", "couch",
    "divansoffa", "hörnsoffa", "modulsoffa", "bäddsoffa",
    "2-sits", "3-sits", "4-sits", "chaise",
  ];
  // Title keywords that indicate accessories, not actual sofas
  const SOFA_NEGATIVE_KEYWORDS = [
    "dynset", "sittdyna", "ryggdyna", "soffdyna", "dyna soffa",
    "soffbord", "soffkudde", "sofftäcke", "sofföverdrag", "överdrag",
    "klädsel", "cover for", "slipcover", "sofa table", "sofa cushion", "sofa cover", "cover",
    "förvaringsbänk", "forvaringsbank", "bänk", "bank", "bench",
    "funda", // Spanish "cover" (IKEA multi-locale)
  ];

  const titleHasNegativeSofaKeyword = (title: string): boolean => {
    const lower = title.toLowerCase();
    return SOFA_NEGATIVE_KEYWORDS.some((kw) => lower.includes(kw));
  };

  const titleLooksLikeSofa = (title: string): boolean => {
    const lower = title.toLowerCase();
    const hasPositive = SOFA_TITLE_KEYWORDS.some((kw) => lower.includes(kw));
    if (!hasPositive) return false;
    return !titleHasNegativeSofaKeyword(title);
  };

  const tryAcceptCandidate = (
    doc: admin.firestore.DocumentSnapshot,
    queue: QueueName,
    options?: {
      allowStudioCutout?: boolean;
      recordDeferredStudioCutout?: boolean;
    }
  ): boolean => {
    const allowStudioCutout = options?.allowStudioCutout ?? true;
    const recordDeferredStudioCutout = options?.recordDeferredStudioCutout === true;
    if (!doc.exists) return false;
    if (candidateDocs.length >= candidateCap) return false;
    if (seenItemIds.has(doc.id)) return false;
    if (acceptedIds.has(doc.id)) return false;

    const data = (doc.data() || {}) as Record<string, unknown>;
    const classification = toRecord(data.classification);

    // Retailer catalog include/exclude override from console.
    if (data.retailerCatalogIncluded === false) return false;

    // Surface eligibility gate: for catalog items (non-gold queues), check that the
    // item's classification matches the deck surface. Gold items are pre-filtered at
    // query time via eligibleSurfaces, but catalog items need a client-side check.
    if (deckSurface === "swiper_deck_sofas" && queue !== "fresh_promoted") {
      const eligibility = data.eligibility as Record<string, Record<string, unknown>> | undefined;
      const title = typeof data.title === "string" ? data.title : "";

      // Always reject clear sofa accessories/noise even if misclassified as sofa.
      if (titleHasNegativeSofaKeyword(title)) return false;

      // First check: if eligibility data exists, use the surface decision
      const surfaceDecision = eligibility?.[deckSurface]?.decision;
      if (surfaceDecision === "REJECT") return false;

      if (surfaceDecision === "ACCEPT") {
        // Explicitly accepted – pass through
      } else if (classification) {
        // Has classification but no explicit accept – check category
        const category =
          (classification.primaryCategory as string | undefined) ||
          (classification.predictedCategory as string | undefined);
        if (category && SOFA_SURFACE_CATEGORIES.has(category)) {
          // Classified as a sofa type – pass through
        } else {
          // Not a sofa category (or "unknown") – fall back to title heuristic
          if (!titleLooksLikeSofa(title)) return false;
        }
      } else {
        // No classification at all (e.g., sample feed items) – use title heuristic
        if (!titleLooksLikeSofa(title)) return false;
      }
    }

    if (!passesImageDisplayGate(data)) return false;

    if (queue === "fresh_promoted") {
      const targetingDecision = evaluatePromotedItemTargeting(
        doc.id,
        data,
        activeCampaignTargeting,
        sessionTargetingProfile
      );
      if (!targetingDecision.eligible) {
        if (targetingDecision.reason === "campaign_not_found") featuredTargetingStats.campaignNotFound += 1;
        if (targetingDecision.reason === "segment_mismatch") featuredTargetingStats.campaignSegmentMismatch += 1;
        if (targetingDecision.reason === "product_set_mismatch") featuredTargetingStats.campaignProductSetMismatch += 1;
        return false;
      }

      if (targetingDecision.reason === "legacy_promoted") {
        featuredTargetingStats.legacyPromotedAccepted += 1;
      }

      if (
        targetingDecision.reason === "eligible_campaign" &&
        targetingDecision.campaignId &&
        targetingDecision.segmentId &&
        targetingDecision.relevanceScore != null &&
        targetingDecision.threshold != null
      ) {
        const campaignContext = activeCampaignTargeting.get(targetingDecision.campaignId);
        if (!campaignContext) {
          return false;
        }
        featuredTargetingStats.campaignMatched += 1;
        featuredContextByItemId.set(doc.id, {
          campaignId: targetingDecision.campaignId,
          retailerId: campaignContext.retailerId,
          segmentId: targetingDecision.segmentId,
          relevanceScore: targetingDecision.relevanceScore,
          threshold: targetingDecision.threshold,
        });
      }
    }

    if (sizeClassFilter && data.sizeClass !== sizeClassFilter) return false;
    if (!sizeClassFilter && requireSmallSpace && data.smallSpaceFriendly !== true) return false;
    if (colorFamilyFilter && data.colorFamily !== colorFamilyFilter) return false;
    if (newUsedFilter && data.newUsed !== newUsedFilter) return false;
    const candidatePrimaryCategory = normalizeToken(
      data.primaryCategory ?? classification?.primaryCategory ?? classification?.predictedCategory
    );
    const candidateSofaTypeShape = normalizeToken(data.sofaTypeShape ?? classification?.sofaTypeShape);
    const candidateSofaFunction = normalizeToken(data.sofaFunction ?? classification?.sofaFunction);
    const candidateSeatCountBucket = normalizeToken(data.seatCountBucket ?? classification?.seatCountBucket);
    const candidateEnvironment = normalizeToken(data.environment ?? classification?.environment);
    if (primaryCategoryFilter && candidatePrimaryCategory !== primaryCategoryFilter) return false;
    if (sofaTypeShapeFilter && candidateSofaTypeShape !== sofaTypeShapeFilter) return false;
    if (sofaFunctionFilter && candidateSofaFunction !== sofaFunctionFilter) return false;
    if (seatCountBucketFilter && candidateSeatCountBucket !== seatCountBucketFilter) return false;
    if (environmentFilter) {
      if (!candidateEnvironment || candidateEnvironment === "unknown") return false;
      if (environmentFilter === "indoor" && !["indoor", "both"].includes(candidateEnvironment)) return false;
      if (environmentFilter === "outdoor" && !["outdoor", "both"].includes(candidateEnvironment)) return false;
      if (environmentFilter === "both" && candidateEnvironment !== "both") return false;
    }
    if (subCategoryFilter && data.subCategory !== subCategoryFilter) return false;
    if (!subCategoryFilter && onboardingSeatBuckets.length > 0) {
      if (candidateSeatCountBucket) {
        if (!onboardingSeatBuckets.includes(candidateSeatCountBucket)) return false;
      } else {
        const candidateSubCategory = normalizeToken(data.subCategory);
        if (!candidateSubCategory || !onboardingSeatSubcats.includes(candidateSubCategory)) return false;
      }
    }
    if (requireModular && data.modular !== true) return false;
    if (roomTypeFilter) {
      const roomTypes = Array.isArray(data.roomTypes) ? data.roomTypes : [];
      if (!roomTypes.includes(roomTypeFilter)) return false;
    }

    const price = asFiniteNumber(data.priceAmount);
    if (price != null) {
      if (minPriceFilter != null && price < minPriceFilter) return false;
      if (maxPriceFilter != null && price > maxPriceFilter) return false;
    }

    const canonical = typeof data.canonicalUrl === "string" ? data.canonicalUrl.trim() : "";
    if (canonical && seenCanonicals.has(canonical)) return false;

    const familyKey = itemFamilyKey(data);
    const modelKey = itemModelKey(data);
    if (
      candidateDocs.length < UNIVERSAL_FAMILY_DEDUPE_TOP_N &&
      ((familyKey && seenFamilyKeys.has(familyKey)) || (modelKey && seenModelKeys.has(modelKey)))
    ) {
      droppedForFamilyDedupe += 1;
      return false;
    }

    // For v2 cold-start first slate, enforce minimum visual/style distance.
    if (onboardingV2Profile != null && candidateDocs.length < 4) {
      const thisTokens = buildStyleTokenSet(data);
      if (thisTokens.size >= 2) {
        for (const existingDoc of candidateDocs.slice(0, 4)) {
          const existingData = (existingDoc.data() || {}) as Record<string, unknown>;
          const existingTokens = buildStyleTokenSet(existingData);
          if (existingTokens.size < 2) continue;
          const distance = jaccardDistance(thisTokens, existingTokens);
          if (distance < 0.4) {
            return false;
          }
        }
      }
    }

    if (PREFER_CONTEXTUAL_SCENE_CANDIDATES && !allowStudioCutout) {
      const sceneType = selectedImageSceneType(data);
      if (sceneType === "studio_cutout") {
        if (recordDeferredStudioCutout && !deferredStudioCutoutIds.has(doc.id)) {
          deferredStudioCutoutIds.add(doc.id);
          deferredStudioCutoutDocs.get(queue)?.push(doc);
          deferredStudioCutoutCount += 1;
        }
        return false;
      }
    }

    acceptedIds.add(doc.id);
    if (canonical) seenCanonicals.add(canonical);
    if (familyKey) seenFamilyKeys.add(familyKey);
    if (modelKey) seenModelKeys.add(modelKey);
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
        if (
          tryAcceptCandidate(doc, queue, {
            allowStudioCutout: !PREFER_CONTEXTUAL_SCENE_CANDIDATES,
            recordDeferredStudioCutout: PREFER_CONTEXTUAL_SCENE_CANDIDATES,
          })
        ) {
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
      tryAcceptCandidate(doc, queue, {
        allowStudioCutout: !PREFER_CONTEXTUAL_SCENE_CANDIDATES,
        recordDeferredStudioCutout: PREFER_CONTEXTUAL_SCENE_CANDIDATES,
      });
    }
  }

  // Contextual-first pass: if we still have room, re-consider deferred studio cutouts.
  if (
    PREFER_CONTEXTUAL_SCENE_CANDIDATES &&
    candidateDocs.length < candidateCap &&
    deferredStudioCutoutCount > 0
  ) {
    for (const queue of BACKFILL_QUEUE_ORDER) {
      if (candidateDocs.length >= candidateCap) break;
      const deferredDocs = deferredStudioCutoutDocs.get(queue) || [];
      for (const doc of deferredDocs) {
        if (candidateDocs.length >= candidateCap) break;
        if (tryAcceptCandidate(doc, queue, { allowStudioCutout: true })) {
          recoveredStudioCutoutCount += 1;
        }
      }
    }
  }

  // Exhaustion fallback: if no candidates after exclusion, clear seen items
  // and re-accept from queue docs so the user never sees an empty deck.
  let recycled = false;
  let fallbackStage: "none" | "recycled_seen_items" | "catalog_exhausted" = "none";
  if (candidateDocs.length === 0 && seenItemIds.size > 0) {
    recycled = true;
    seenItemIds.clear();
    // Re-run acceptance from all queue docs
    for (const queue of QUEUE_ORDER) {
      const state = queueState.get(queue);
      if (!state) continue;
      state.cursor = 0;
      while (state.cursor < state.docs.length && candidateDocs.length < candidateCap) {
        const doc = state.docs[state.cursor++];
        tryAcceptCandidate(doc, queue, { allowStudioCutout: true });
      }
    }
    fallbackStage = candidateDocs.length > 0 ? "recycled_seen_items" : "catalog_exhausted";
    console.info(`[deck] Exhaustion fallback: recycled ${candidateDocs.length} candidates for session ${sessionId}`);
  }
  if (candidateDocs.length === 0 && fallbackStage === "none") {
    fallbackStage = "catalog_exhausted";
  }

  const candidates: ItemCandidate[] = candidateDocs.map((doc) => ({ id: doc.id, ...doc.data() } as ItemCandidate));
  const sessionContext: SessionContext = { preferenceWeights };

  const rankWindow = Math.min(candidates.length, Math.max(limit * 24, MIN_RANK_WINDOW));
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

  const rankedItems = exploredIds
    .map((id) => idToCandidate.get(id))
    .filter((c): c is ItemCandidate => c != null)
    .map((c) => {
      const queue = candidateQueueById.get(String(c.id));
      const fromPromotedQueue = queue === "fresh_promoted";
      if (!fromPromotedQueue) return { ...c };
      const featuredContext = featuredContextByItemId.get(String(c.id));

      // Explicit featured flag for client rendering and analytics.
      return {
        ...c,
        isFeatured: true,
        featuredLabel: "Featured",
        ...(featuredContext
          ? {
              campaignId: featuredContext.campaignId,
              featuredRetailerId: featuredContext.retailerId,
              segmentId: featuredContext.segmentId,
              featuredRelevanceScore: featuredContext.relevanceScore,
              featuredMatchThreshold: featuredContext.threshold,
            }
          : {}),
      };
    });

  const qualityLookupIds = rankedItems
    .slice(0, Math.min(rankedItems.length, QUALITY_SCORE_LOOKUP_LIMIT))
    .map((item) => asTrimmedString(item.id))
    .filter((id): id is string => id != null);
  const creativeScoreByItemId = await loadCreativeHealthScoreByItemId(
    db,
    Array.from(new Set(qualityLookupIds))
  );

  const nearDuplicatePhase1 = applyNearDuplicateExplorationPolicy(
    rankedItems as Array<Record<string, unknown>>,
    limit,
    creativeScoreByItemId
  );
  const sourceDiversityPreFeatured = applySourceDiversityPolicy(
    nearDuplicatePhase1.items as Array<Record<string, unknown>>,
    limit
  );
  const nearDuplicatePreFeatured = applyNearDuplicateExplorationPolicy(
    sourceDiversityPreFeatured.items as Array<Record<string, unknown>>,
    limit,
    creativeScoreByItemId
  );
  const shapedRankedItems = nearDuplicatePreFeatured.items as ItemCandidate[];

  const featuredFrequencyCap = deriveFeaturedFrequencyCap(activeCampaignTargeting);
  const featuredServing = applyFeaturedServingPolicy(
    shapedRankedItems as Array<Record<string, unknown>>,
    limit,
    featuredFrequencyCap,
    FEATURED_RETAILER_COOLDOWN
  );
  const sourceDiversityShaping = applySourceDiversityPolicy(
    featuredServing.items as Array<Record<string, unknown>>,
    limit
  );
  const nearDuplicateShaping = applyNearDuplicateExplorationPolicy(
    sourceDiversityShaping.items as Array<Record<string, unknown>>,
    limit,
    creativeScoreByItemId
  );
  const modelDedupeShaping = applyTopModelDedupePolicy(
    nearDuplicateShaping.items as Array<Record<string, unknown>>,
    limit
  );
  const items = modelDedupeShaping.items as ItemCandidate[];
  const servedItemIds = items.map((item) => String(item.id));

  const itemsForMetrics = items.map((item) => item as Record<string, unknown>);
  const sameFamilyTop8Rate = computeSameFamilyTop8Rate(itemsForMetrics);
  const styleDistanceTop4Min = computeMinStyleDistanceTop4(itemsForMetrics);
  const sourceConcentrationTop8 = computeSourceConcentrationTop8(itemsForMetrics);
  const sourceDiversityTop8 = computeSourceDiversityTop8(itemsForMetrics);

  const itemScores: Record<string, number> = {};
  servedItemIds.forEach((id) => {
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
  const onboardingProfileSummary = onboardingV2Profile != null
    ? {
        primaryStyle:
          onboardingV2Profile.derivedProfile?.primaryStyle ||
          onboardingV2Profile.sceneArchetypes[0] ||
          onboardingV2Profile.sofaVibes[0] ||
          null,
        secondaryStyle:
          onboardingV2Profile.derivedProfile?.secondaryStyle ||
          onboardingV2Profile.sceneArchetypes[1] ||
          onboardingV2Profile.sofaVibes[1] ||
          null,
        confidence: onboardingV2Profile.derivedProfile?.confidence ?? null,
        explanation: onboardingV2Profile.derivedProfile?.explanation || [],
      }
    : null;

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
      itemIds: servedItemIds,
      variant,
      variantBucket,
      explorationPolicy: explorationRate > 0 ? "sample_from_top_2limit" : "none",
      scoreStats,
      sameFamilyTop8Rate,
      styleDistanceTop4Min,
      sourceConcentrationTop8,
      sourceDiversityTop8,
      familyDedupeTopN: UNIVERSAL_FAMILY_DEDUPE_TOP_N,
      droppedForFamilyDedupe,
      nearDuplicatePolicy: {
        hardTopN: HARD_NEAR_DUPLICATE_TOP_N,
        softTopN: SOFT_NEAR_DUPLICATE_TOP_N,
        softRepeatBudget: SOFT_NEAR_DUPLICATE_MAX_REPEATS,
        minStyleDistance: SOFT_NEAR_DUPLICATE_MIN_STYLE_DISTANCE,
        minImageCount: SOFT_REPEAT_MIN_IMAGE_COUNT,
        minCreativeScore: SOFT_REPEAT_MIN_CREATIVE_SCORE,
        qualityScoreLookupEnabled: ENABLE_SCORE_QUALITY_GATE,
        qualityScoreLookupLimit: QUALITY_SCORE_LOOKUP_LIMIT,
        qualityScoresFound: creativeScoreByItemId.size,
      },
      scenePreferencePolicy: {
        contextualFirst: PREFER_CONTEXTUAL_SCENE_CANDIDATES,
        deferredStudioCutoutCount,
        recoveredStudioCutoutCount,
      },
      nearDuplicateShaping: nearDuplicateShaping.stats,
      nearDuplicatePhase1Shaping: nearDuplicatePhase1.stats,
      sourceDiversityPolicy: {
        topN: SOURCE_DIVERSITY_TOP_N,
        maxPerSource: SOURCE_DIVERSITY_MAX_PER_SOURCE,
      },
      sourceDiversityShaping: sourceDiversityShaping.stats,
      modelDiversityPolicy: {
        topN: TOP_MODEL_DEDUPE_TOP_N,
        maxPerModel: TOP_MODEL_DEDUPE_MAX_PER_MODEL,
      },
      modelDiversityShaping: modelDedupeShaping.stats,
      featuredServing,
      fallbackStage,
      ...(onboardingProfileSummary != null ? { onboardingProfile: onboardingProfileSummary } : {}),
      ...(recycled ? { recycled: true } : {}),
    },
    itemScores,
  };

  let featuredLoggingStats: FeaturedLoggingStats = {
    loggedCount: 0,
    updatedCampaignCount: 0,
    estimatedSpendSEK: 0,
  };
  try {
    featuredLoggingStats = await logFeaturedImpressionsAndUpdateCampaigns(
      db,
      sessionId,
      requestId,
      itemsForMetrics,
      Date.now()
    );
  } catch (loggingError) {
    console.warn("featured_impression_logging_failed", {
      requestId,
      sessionId,
      error: loggingError instanceof Error ? loggingError.message : String(loggingError),
    });
  }

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
      onboardingConstraintMode: onboardingConstraintsMode,
      onboardingMediumConstraintSwipeThreshold: ONBOARDING_MEDIUM_CONSTRAINT_SWIPE_THRESHOLD,
      onboardingHardConstraintSwipeThreshold: ONBOARDING_HARD_CONSTRAINT_SWIPE_THRESHOLD,
      swipeHistoryCount: swipesSnap.size,
      fallbackStage,
      sourceFetchCounts: {
        freshPromoted: freshPromotedDocs.length,
        freshCatalog: freshCatalogDocs.length,
        personaById: personaDocs.length,
      },
      diversityGuards: {
        universalFamilyDedupeTopN: UNIVERSAL_FAMILY_DEDUPE_TOP_N,
        droppedForFamilyDedupe,
        hardNearDuplicateTopN: HARD_NEAR_DUPLICATE_TOP_N,
        softNearDuplicateTopN: SOFT_NEAR_DUPLICATE_TOP_N,
        softNearDuplicateRepeatBudget: SOFT_NEAR_DUPLICATE_MAX_REPEATS,
        softNearDuplicateMinStyleDistance: SOFT_NEAR_DUPLICATE_MIN_STYLE_DISTANCE,
        softRepeatMinImageCount: SOFT_REPEAT_MIN_IMAGE_COUNT,
        softRepeatMinCreativeScore: SOFT_REPEAT_MIN_CREATIVE_SCORE,
        qualityScoreLookupEnabled: ENABLE_SCORE_QUALITY_GATE,
        qualityScoreLookupLimit: QUALITY_SCORE_LOOKUP_LIMIT,
        qualityScoresFound: creativeScoreByItemId.size,
        scenePreference: {
          contextualFirst: PREFER_CONTEXTUAL_SCENE_CANDIDATES,
          deferredStudioCutoutCount,
          recoveredStudioCutoutCount,
        },
        nearDuplicatePhase1Shaping: nearDuplicatePhase1.stats,
        nearDuplicateShaping: nearDuplicateShaping.stats,
        sourceDiversityTopN: SOURCE_DIVERSITY_TOP_N,
        sourceDiversityMaxPerSource: SOURCE_DIVERSITY_MAX_PER_SOURCE,
        sourceDiversityShaping: sourceDiversityShaping.stats,
      },
      featuredTargeting: {
        activeCampaignCount: activeCampaignTargeting.size,
        ...featuredTargetingStats,
      },
      featuredServing,
      featuredLoggingStats,
      sessionTargetingProfile,
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

  logDeckEvent("deck_request_served", {
    latencyMs: Date.now() - startedAtMs,
    limit,
    candidateCount: candidates.length,
    servedCount: items.length,
    retrievalQueues: retrievalQueuesUsed,
    hasOnboardingV2: onboardingV2Profile != null,
    sameFamilyTop8Rate,
    styleDistanceTop4Min,
    sourceConcentrationTop8,
    sourceDiversityTop8,
    droppedForFamilyDedupe,
    nearDuplicatePhase1Shaping: nearDuplicatePhase1.stats,
    nearDuplicateShaping: nearDuplicateShaping.stats,
    sourceDiversityShaping: sourceDiversityShaping.stats,
    modelDiversityShaping: modelDedupeShaping.stats,
    qualityScoresFound: creativeScoreByItemId.size,
    onboardingConstraintMode: onboardingConstraintsMode,
    fallbackStage,
    activeCampaignCount: activeCampaignTargeting.size,
    featuredTargetingStats,
    featuredServing,
    featuredLoggingStats,
  });
  res.status(200).json(response);
  } catch (error) {
    console.error("deck_request_failed", {
      requestId,
      sessionId,
      latencyMs: Date.now() - startedAtMs,
      limit,
      error: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}

export const __deckTestUtils = {
  parseOnboardingV2Profile,
  buildOnboardingV2Weights,
  buildStyleTokenSet,
  jaccardDistance,
  titleFamilyKey,
  itemModelKey,
  itemFamilyKey,
  itemSourceKey,
  itemVariantKey,
  extractItemImageUrls,
  passesImageDisplayGate,
  passesSoftRepeatQualityGate,
  applyNearDuplicateExplorationPolicy,
  applySourceDiversityPolicy,
  applyTopModelDedupePolicy,
  computeSameFamilyTop8Rate,
  computeSourceConcentrationTop8,
  computeSourceDiversityTop8,
  computeMinStyleDistanceTop4,
  extractCampaignIdFromPromotedItem,
  evaluatePromotedItemTargeting,
  applyFeaturedServingPolicy,
  deriveFeaturedFrequencyCap,
};
