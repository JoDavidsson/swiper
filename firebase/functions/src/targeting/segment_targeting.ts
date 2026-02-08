const ALLOWED_SIZE_CLASSES = new Set(["small", "medium", "large", "compact"]);
const REGION_ALIASES: Record<string, string> = {
  se: "sweden",
  sverige: "sweden",
  sweden: "sweden",
};

export const DEFAULT_SEGMENT_MATCH_THRESHOLD = 0.5;

export type SegmentCriteria = {
  styleTags: string[];
  budgetMin: number | null;
  budgetMax: number | null;
  sizeClasses: string[];
  geoRegion: string | null;
  geoCity: string | null;
  geoPostcodes: string[];
};

export type SegmentCriteriaPatch = {
  styleTags?: string[] | null;
  budgetMin?: number | null;
  budgetMax?: number | null;
  sizeClasses?: string[] | null;
  geoRegion?: string | null;
  geoCity?: string | null;
  geoPostcodes?: string[] | null;
};

export type SegmentValidationIssue = {
  field: string;
  message: string;
};

export type SegmentSnapshot = SegmentCriteria & {
  id: string;
  name: string | null;
  isTemplate: boolean;
};

export type SessionTargetingInput = {
  locale?: string | null;
  geoRegion?: string | null;
  geoCity?: string | null;
  geoPostcode?: string | null;
  preferenceWeights?: Record<string, number>;
  onboardingStyleTokens?: string[];
  preferredBudgetMin?: number | null;
  preferredBudgetMax?: number | null;
  explicitSizeClass?: string | null;
  inferredSizeClasses?: string[];
};

export type SessionTargetingProfile = {
  styleTags: string[];
  budgetMin: number | null;
  budgetMax: number | null;
  sizeClasses: string[];
  geoRegion: string | null;
  geoCity: string | null;
  geoPostcode: string | null;
};

type SegmentMatchComponent = {
  required: boolean;
  matched: boolean;
  score: number;
  details: Record<string, unknown>;
};

export type SegmentMatchResult = {
  isMatch: boolean;
  overallScore: number;
  threshold: number;
  components: {
    style: SegmentMatchComponent;
    budget: SegmentMatchComponent;
    size: SegmentMatchComponent;
    geo: SegmentMatchComponent;
  };
};

function round(value: number, decimals = 4): number {
  const scale = Math.pow(10, decimals);
  return Math.round(value * scale) / scale;
}

function normalizeToken(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeRegionToken(value: unknown): string | null {
  const token = normalizeToken(value);
  if (!token) return null;
  return REGION_ALIASES[token] || token;
}

function normalizePostcodeToken(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.toUpperCase().replace(/\s+/g, "").trim();
  if (cleaned.length < 2 || cleaned.length > 12) return null;
  if (!/^[A-Z0-9-]+$/.test(cleaned)) return null;
  return cleaned;
}

function normalizeNumberField(value: unknown, field: string, issues: SegmentValidationIssue[]): number | null {
  if (value == null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    issues.push({ field, message: "must be a finite number or null" });
    return null;
  }
  if (value < 0) {
    issues.push({ field, message: "must be >= 0" });
    return null;
  }
  return value;
}

function toStringArrayOrNull(
  value: unknown,
  field: string,
  issues: SegmentValidationIssue[],
  allowedValues?: Set<string>
): string[] | null {
  if (value == null) return null;
  if (!Array.isArray(value)) {
    issues.push({ field, message: "must be an array of strings or null" });
    return null;
  }
  const output = new Set<string>();
  for (const entry of value) {
    const token = normalizeToken(entry);
    if (!token) continue;
    if (allowedValues && !allowedValues.has(token)) {
      issues.push({
        field,
        message: `contains unsupported value '${token}'`,
      });
      continue;
    }
    output.add(token);
  }
  return output.size > 0 ? Array.from(output) : null;
}

function toPostcodeArrayOrNull(
  value: unknown,
  field: string,
  issues: SegmentValidationIssue[]
): string[] | null {
  if (value == null) return null;
  if (!Array.isArray(value)) {
    issues.push({ field, message: "must be an array of postcodes or null" });
    return null;
  }
  const output = new Set<string>();
  for (const entry of value) {
    const postcode = normalizePostcodeToken(entry);
    if (!postcode) {
      issues.push({ field, message: "contains invalid postcode value" });
      continue;
    }
    output.add(postcode);
  }
  return output.size > 0 ? Array.from(output) : null;
}

function inferRegionFromLocale(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const token = value.trim().toLowerCase();
  if (!token) return null;
  if (token.includes("sv") || token.endsWith("-se") || token.endsWith("_se") || token === "se") {
    return "sweden";
  }
  return null;
}

function collectPreferenceStyleAndSize(preferenceWeights: Record<string, number>): {
  styles: Set<string>;
  sizes: Set<string>;
} {
  const styles = new Set<string>();
  const sizes = new Set<string>();

  for (const [rawKey, rawWeight] of Object.entries(preferenceWeights)) {
    if (typeof rawWeight !== "number" || !Number.isFinite(rawWeight) || rawWeight <= 0) continue;
    const key = normalizeToken(rawKey);
    if (!key) continue;

    if (key.includes(":")) {
      const [prefix, value] = key.split(":", 2);
      if (prefix === "size" && value && ALLOWED_SIZE_CLASSES.has(value)) {
        sizes.add(value);
      } else if (prefix === "style" && value) {
        styles.add(value);
      }
      continue;
    }

    // Un-prefixed positive keys are treated as style preference tokens.
    styles.add(key);
  }

  return { styles, sizes };
}

export function normalizeSegmentCriteriaInput(
  input: Record<string, unknown>
): { normalized: SegmentCriteriaPatch; issues: SegmentValidationIssue[] } {
  const issues: SegmentValidationIssue[] = [];
  const normalized: SegmentCriteriaPatch = {};

  if ("styleTags" in input) {
    normalized.styleTags = toStringArrayOrNull(input.styleTags, "styleTags", issues);
  }
  if ("budgetMin" in input) {
    normalized.budgetMin = normalizeNumberField(input.budgetMin, "budgetMin", issues);
  }
  if ("budgetMax" in input) {
    normalized.budgetMax = normalizeNumberField(input.budgetMax, "budgetMax", issues);
  }
  if ("sizeClasses" in input) {
    normalized.sizeClasses = toStringArrayOrNull(
      input.sizeClasses,
      "sizeClasses",
      issues,
      ALLOWED_SIZE_CLASSES
    );
  }
  if ("geoRegion" in input) {
    if (input.geoRegion != null && typeof input.geoRegion !== "string") {
      issues.push({ field: "geoRegion", message: "must be a string or null" });
    }
    normalized.geoRegion = normalizeRegionToken(input.geoRegion);
  }
  if ("geoCity" in input) {
    if (input.geoCity != null && typeof input.geoCity !== "string") {
      issues.push({ field: "geoCity", message: "must be a string or null" });
    }
    normalized.geoCity = normalizeToken(input.geoCity);
  }
  if ("geoPostcodes" in input) {
    normalized.geoPostcodes = toPostcodeArrayOrNull(input.geoPostcodes, "geoPostcodes", issues);
  }

  if (
    normalized.budgetMin != null &&
    normalized.budgetMax != null &&
    normalized.budgetMin > normalized.budgetMax
  ) {
    issues.push({
      field: "budgetMin/budgetMax",
      message: "budgetMin cannot be greater than budgetMax",
    });
  }

  return { normalized, issues };
}

export function toSegmentCriteria(raw: Record<string, unknown>): SegmentCriteria {
  const { normalized } = normalizeSegmentCriteriaInput(raw);
  return {
    styleTags: normalized.styleTags ?? [],
    budgetMin: normalized.budgetMin ?? null,
    budgetMax: normalized.budgetMax ?? null,
    sizeClasses: normalized.sizeClasses ?? [],
    geoRegion: normalized.geoRegion ?? null,
    geoCity: normalized.geoCity ?? null,
    geoPostcodes: normalized.geoPostcodes ?? [],
  };
}

export function buildSegmentSnapshot(segmentId: string, data: Record<string, unknown>): SegmentSnapshot {
  const criteria = toSegmentCriteria(data);
  return {
    id: segmentId,
    name: typeof data.name === "string" ? data.name : null,
    isTemplate: data.isTemplate === true,
    ...criteria,
  };
}

export function buildSessionTargetingProfile(input: SessionTargetingInput): SessionTargetingProfile {
  const styleTokens = new Set<string>();
  const sizeClasses = new Set<string>();

  const { styles, sizes } = collectPreferenceStyleAndSize(input.preferenceWeights || {});
  for (const token of styles) styleTokens.add(token);
  for (const token of sizes) sizeClasses.add(token);

  for (const token of input.onboardingStyleTokens || []) {
    const normalized = normalizeToken(token);
    if (normalized) styleTokens.add(normalized);
  }

  const explicitSize = normalizeToken(input.explicitSizeClass);
  if (explicitSize && ALLOWED_SIZE_CLASSES.has(explicitSize)) {
    sizeClasses.add(explicitSize);
  }

  for (const size of input.inferredSizeClasses || []) {
    const normalizedSize = normalizeToken(size);
    if (normalizedSize && ALLOWED_SIZE_CLASSES.has(normalizedSize)) {
      sizeClasses.add(normalizedSize);
    }
  }

  const budgetMin =
    typeof input.preferredBudgetMin === "number" &&
    Number.isFinite(input.preferredBudgetMin) &&
    input.preferredBudgetMin >= 0
      ? input.preferredBudgetMin
      : null;
  const budgetMax =
    typeof input.preferredBudgetMax === "number" &&
    Number.isFinite(input.preferredBudgetMax) &&
    input.preferredBudgetMax >= 0
      ? input.preferredBudgetMax
      : null;

  const resolvedBudgetMin =
    budgetMin != null && budgetMax != null && budgetMin > budgetMax ? null : budgetMin;
  const resolvedBudgetMax =
    budgetMin != null && budgetMax != null && budgetMin > budgetMax ? null : budgetMax;

  const geoRegion =
    normalizeRegionToken(input.geoRegion) || inferRegionFromLocale(input.locale) || "sweden";
  const geoCity = normalizeToken(input.geoCity);
  const geoPostcode = normalizePostcodeToken(input.geoPostcode);

  return {
    styleTags: Array.from(styleTokens),
    budgetMin: resolvedBudgetMin,
    budgetMax: resolvedBudgetMax,
    sizeClasses: Array.from(sizeClasses),
    geoRegion,
    geoCity,
    geoPostcode,
  };
}

export function evaluateSegmentMatch(
  segment: SegmentCriteria,
  profile: SessionTargetingProfile,
  threshold = DEFAULT_SEGMENT_MATCH_THRESHOLD
): SegmentMatchResult {
  const segmentStyles = new Set(segment.styleTags.map((tag) => normalizeToken(tag)).filter((v): v is string => v != null));
  const profileStyles = new Set(profile.styleTags.map((tag) => normalizeToken(tag)).filter((v): v is string => v != null));
  let styleOverlapCount = 0;
  for (const tag of segmentStyles) {
    if (profileStyles.has(tag)) styleOverlapCount += 1;
  }
  const styleRequired = segmentStyles.size > 0;
  const styleMatched = !styleRequired || styleOverlapCount > 0;
  const styleScore = styleRequired ? styleOverlapCount / segmentStyles.size : 1;

  const budgetRequired = segment.budgetMin != null || segment.budgetMax != null;
  const profileBudgetKnown = profile.budgetMin != null || profile.budgetMax != null;
  const segmentBudgetMin = segment.budgetMin ?? Number.NEGATIVE_INFINITY;
  const segmentBudgetMax = segment.budgetMax ?? Number.POSITIVE_INFINITY;
  const profileBudgetMin = profile.budgetMin ?? Number.NEGATIVE_INFINITY;
  const profileBudgetMax = profile.budgetMax ?? Number.POSITIVE_INFINITY;
  const budgetOverlap = profileBudgetKnown && Math.max(segmentBudgetMin, profileBudgetMin) <= Math.min(segmentBudgetMax, profileBudgetMax);
  const budgetMatched = !budgetRequired || budgetOverlap;
  const budgetScore = budgetRequired ? (budgetOverlap ? 1 : 0) : 1;

  const segmentSizes = new Set(segment.sizeClasses.map((size) => normalizeToken(size)).filter((v): v is string => v != null));
  const profileSizes = new Set(profile.sizeClasses.map((size) => normalizeToken(size)).filter((v): v is string => v != null));
  let sizeOverlapCount = 0;
  for (const size of segmentSizes) {
    if (profileSizes.has(size)) sizeOverlapCount += 1;
  }
  const sizeRequired = segmentSizes.size > 0;
  const sizeMatched = !sizeRequired || sizeOverlapCount > 0;
  const sizeScore = sizeRequired ? sizeOverlapCount / segmentSizes.size : 1;

  const segmentRegion = normalizeRegionToken(segment.geoRegion);
  const segmentCity = normalizeToken(segment.geoCity);
  const segmentPostcodes = new Set(
    segment.geoPostcodes
      .map((postcode) => normalizePostcodeToken(postcode))
      .filter((v): v is string => v != null)
  );
  const profileRegion = normalizeRegionToken(profile.geoRegion);
  const profileCity = normalizeToken(profile.geoCity);
  const profilePostcode = normalizePostcodeToken(profile.geoPostcode);

  const geoChecks: boolean[] = [];
  if (segmentRegion != null) geoChecks.push(profileRegion === segmentRegion);
  if (segmentCity != null) geoChecks.push(profileCity === segmentCity);
  if (segmentPostcodes.size > 0) geoChecks.push(profilePostcode != null && segmentPostcodes.has(profilePostcode));
  const geoRequired = geoChecks.length > 0;
  const geoMatchCount = geoChecks.filter(Boolean).length;
  const geoMatched = !geoRequired || geoMatchCount === geoChecks.length;
  const geoScore = geoRequired ? geoMatchCount / geoChecks.length : 1;

  const weights = {
    style: 0.4,
    budget: 0.25,
    size: 0.2,
    geo: 0.15,
  };

  const activeWeightSum =
    (styleRequired ? weights.style : 0) +
    (budgetRequired ? weights.budget : 0) +
    (sizeRequired ? weights.size : 0) +
    (geoRequired ? weights.geo : 0);

  const weightedScore =
    activeWeightSum > 0
      ? ((styleRequired ? styleScore * weights.style : 0) +
          (budgetRequired ? budgetScore * weights.budget : 0) +
          (sizeRequired ? sizeScore * weights.size : 0) +
          (geoRequired ? geoScore * weights.geo : 0)) /
        activeWeightSum
      : 1;

  const requiredDimensionsMatched = styleMatched && budgetMatched && sizeMatched && geoMatched;
  const overallScore = round(weightedScore);
  const isMatch = requiredDimensionsMatched && overallScore >= threshold;

  return {
    isMatch,
    overallScore,
    threshold,
    components: {
      style: {
        required: styleRequired,
        matched: styleMatched,
        score: round(styleScore),
        details: {
          requiredTags: Array.from(segmentStyles),
          overlapCount: styleOverlapCount,
        },
      },
      budget: {
        required: budgetRequired,
        matched: budgetMatched,
        score: round(budgetScore),
        details: {
          segmentBudgetMin: segment.budgetMin,
          segmentBudgetMax: segment.budgetMax,
          profileBudgetMin: profile.budgetMin,
          profileBudgetMax: profile.budgetMax,
          overlap: budgetOverlap,
        },
      },
      size: {
        required: sizeRequired,
        matched: sizeMatched,
        score: round(sizeScore),
        details: {
          requiredSizes: Array.from(segmentSizes),
          overlapCount: sizeOverlapCount,
        },
      },
      geo: {
        required: geoRequired,
        matched: geoMatched,
        score: round(geoScore),
        details: {
          segmentRegion,
          segmentCity,
          segmentPostcodes: Array.from(segmentPostcodes),
          profileRegion,
          profileCity,
          profilePostcode,
          matchedChecks: geoMatchCount,
          totalChecks: geoChecks.length,
        },
      },
    },
  };
}

export const __segmentTargetingTestUtils = {
  inferRegionFromLocale,
  normalizeRegionToken,
  normalizePostcodeToken,
};
