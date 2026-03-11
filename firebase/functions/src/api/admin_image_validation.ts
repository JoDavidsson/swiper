import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { analyzeImageUrl, type ImageMetaResult } from "./image_proxy";

const DEFAULT_VALIDATE_LIMIT = 50;
const MAX_VALIDATE_LIMIT = 100;
const MAX_IMAGES_TO_ANALYZE = Math.max(
  1,
  Math.min(12, parseInt(String(process.env.IMAGE_VALIDATION_MAX_IMAGES_TO_ANALYZE || "8"), 10) || 8)
);
const VALIDATION_SCAN_PAGE_SIZE = 300;
const VALIDATION_TIME_BUDGET_MS = 45_000;
const VALIDATION_ITEM_CONCURRENCY = 4;

type NormalizedImageCandidate = {
  url: string;
  sourceIndex: number;
};

type EvaluatedImage = NormalizedImageCandidate & {
  meta: ImageMetaResult;
  creativeScore: number;
};

type ValidationResult = {
  itemId: string;
  success: boolean;
  score?: number;
  band?: string;
  sceneType?: string;
  selectedImageUrl?: string;
  error?: string;
};

/**
 * POST /api/admin/validate-images
 *
 * Trigger image validation for items that haven't been validated yet.
 * Validates image quality and selects the best display image when multiple
 * images exist.
 *
 * Request body:
 * - limit: Max items to validate (default: 50)
 * - retailer: Optional retailer slug to filter
 * - force: Re-validate even if already validated (default: false)
 */
export async function adminValidateImagesPost(req: Request, res: Response): Promise<void> {
  const { limit = DEFAULT_VALIDATE_LIMIT, retailer, force = false } = req.body;
  const requestedLimit = Number.isFinite(limit) ? Number(limit) : DEFAULT_VALIDATE_LIMIT;
  const maxLimit = Math.min(MAX_VALIDATE_LIMIT, Math.max(1, Math.floor(requestedLimit)));

  const db = admin.firestore();

  try {
    const docsToValidate = await collectValidationCandidates({
      db,
      maxLimit,
      retailer,
      force: force === true,
    });

    if (docsToValidate.length === 0) {
      res.json({
        message: "No items need validation",
        validated: 0,
      });
      return;
    }

    const results: ValidationResult[] = [];
    const startedAt = Date.now();

    for (let index = 0; index < docsToValidate.length; index += VALIDATION_ITEM_CONCURRENCY) {
      if (Date.now() - startedAt >= VALIDATION_TIME_BUDGET_MS) {
        break;
      }
      const chunk = docsToValidate.slice(index, index + VALIDATION_ITEM_CONCURRENCY);
      const chunkResults = await Promise.all(chunk.map((doc) => validateItemDocument(doc)));
      results.push(...chunkResults);
    }

    const successCount = results.filter((r) => r.success).length;
    const avgScore =
      results
        .filter((r) => r.success && r.score != null)
        .reduce((sum, r) => sum + (r.score || 0), 0) / (successCount || 1);
    const hasMore = results.length < docsToValidate.length || results.length >= maxLimit;

    res.json({
      message: `Validated ${results.length} items`,
      validated: results.length,
      successful: successCount,
      averageScore: Math.round(avgScore),
      hasMore,
      results,
    });
  } catch (error) {
    console.error("Image validation error:", error);
    res.status(500).json({ error: "Failed to validate images" });
  }
}

/**
 * GET /api/admin/creative-health-stats
 *
 * Get aggregate Creative Health statistics for items.
 */
export async function adminCreativeHealthStatsGet(req: Request, res: Response): Promise<void> {
  const retailer = req.query.retailer as string | undefined;

  const db = admin.firestore();

  try {
    let query = db.collection("items").where("isActive", "==", true);

    if (retailer) {
      query = query.where("sourceId", "==", retailer);
    }

    const snapshot = await query.limit(1000).get();

    const stats = {
      total: snapshot.size,
      validated: 0,
      notValidated: 0,
      byBand: {
        green: 0,
        yellow: 0,
        red: 0,
      },
      bySceneType: {
        contextual: 0,
        studio_cutout: 0,
        unknown: 0,
      },
      averageScore: 0,
      averageDisplaySuitability: 0,
      commonIssues: {} as Record<string, number>,
    };

    let scoreSum = 0;
    let scoredCount = 0;
    let displaySum = 0;
    let displayCount = 0;

    for (const doc of snapshot.docs) {
      const item = doc.data();
      const health = toRecord(item.creativeHealth);
      const validation = toRecord(item.imageValidation);

      const score = asFiniteNumber(health?.score);
      if (score != null) {
        stats.validated += 1;
        scoreSum += score;
        scoredCount += 1;

        const band = asTrimmedString(health?.band) as "green" | "yellow" | "red" | null;
        if (band && stats.byBand[band] !== undefined) {
          stats.byBand[band] += 1;
        }

        const sceneType =
          asTrimmedString(health?.sceneType) ||
          asTrimmedString(validation?.selectedSceneType) ||
          "unknown";
        if (sceneType === "contextual") stats.bySceneType.contextual += 1;
        else if (sceneType === "studio_cutout") stats.bySceneType.studio_cutout += 1;
        else stats.bySceneType.unknown += 1;

        const displaySuitability =
          asFiniteNumber(health?.displaySuitabilityScore) ??
          asFiniteNumber(validation?.selectedDisplaySuitabilityScore);
        if (displaySuitability != null) {
          displaySum += displaySuitability;
          displayCount += 1;
        }

        const issues = toStringArray(health?.issues);
        for (const issue of issues) {
          stats.commonIssues[issue] = (stats.commonIssues[issue] || 0) + 1;
        }
      } else {
        stats.notValidated += 1;
      }
    }

    stats.averageScore = scoredCount > 0 ? Math.round(scoreSum / scoredCount) : 0;
    stats.averageDisplaySuitability = displayCount > 0 ? Math.round(displaySum / displayCount) : 0;

    res.json(stats);
  } catch (error) {
    console.error("Creative health stats error:", error);
    res.status(500).json({ error: "Failed to get stats" });
  }
}

function currentTimestamp(): Date {
  return new Date();
}

async function collectValidationCandidates(params: {
  db: FirebaseFirestore.Firestore;
  maxLimit: number;
  retailer?: string;
  force: boolean;
}): Promise<Array<FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>>> {
  const { db, maxLimit, retailer, force } = params;
  let baseQuery: FirebaseFirestore.Query = db.collection("items").where("isActive", "==", true);
  if (retailer) {
    baseQuery = baseQuery.where("sourceId", "==", retailer);
  }

  const docs: Array<FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>> = [];
  const pageSize = force ? maxLimit : Math.max(maxLimit, VALIDATION_SCAN_PAGE_SIZE);
  let cursorId: string | null = null;

  while (docs.length < maxLimit) {
    let pageQuery = baseQuery.orderBy("__name__").limit(pageSize);
    if (cursorId) {
      pageQuery = pageQuery.startAfter(cursorId);
    }
    const page = await pageQuery.get();
    if (page.empty) break;

    for (const doc of page.docs) {
      if (force || needsImageValidation(doc.data() as Record<string, unknown>)) {
        docs.push(doc);
        if (docs.length >= maxLimit) break;
      }
    }

    cursorId = page.docs[page.docs.length - 1].id;
    if (page.size < pageSize) break;
  }

  return docs;
}

function needsImageValidation(item: Record<string, unknown>): boolean {
  const validation = toRecord(item.imageValidation);
  if (!validation || validation.validated !== true) {
    return true;
  }

  const hasAnalyzedImages = Array.isArray(validation.analyzedImages) && validation.analyzedImages.length > 0;
  const hasSelectedImage =
    asTrimmedString(validation.selectedImageUrl) ??
    asTrimmedString(toRecord(item.creativeHealth)?.selectedImageUrl);
  const hasSelectedScene =
    asTrimmedString(validation.selectedSceneType) ??
    asTrimmedString(toRecord(item.creativeHealth)?.sceneType);
  const hasScore = asFiniteNumber(toRecord(item.creativeHealth)?.score) != null;

  return !(hasAnalyzedImages && hasSelectedImage && hasSelectedScene && hasScore);
}

async function validateItemDocument(
  doc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>
): Promise<ValidationResult> {
  const item = doc.data();
  const imageCandidates = normalizeImageCandidates(item.images);
  const rawImages = Array.isArray(item.images) ? (item.images as unknown[]) : [];
  const validatedAt = currentTimestamp();

  if (imageCandidates.length === 0) {
    await doc.ref.update({
      imageValidation: {
        validated: true,
        validatedAt,
        primaryImageValid: false,
        validImageCount: 0,
        totalImageCount: 0,
        issues: ["no-images"],
      },
      creativeHealth: {
        score: 0,
        band: "red",
        issues: ["no-images"],
        validatedAt,
      },
    });

    return {
      itemId: doc.id,
      success: true,
      score: 0,
      band: "red",
    };
  }

  const candidatesToAnalyze = imageCandidates.slice(0, MAX_IMAGES_TO_ANALYZE);

  try {
    const evaluated = await Promise.all(
      candidatesToAnalyze.map(async (candidate): Promise<EvaluatedImage> => {
        try {
          const meta = await analyzeImageUrl(candidate.url);
          return {
            ...candidate,
            meta,
            creativeScore: calculateCreativeHealthScore(meta),
          };
        } catch (error) {
          const issue = classifyValidationIssue(error);
          const failedMeta = buildFailedMeta(candidate.url, issue);
          return {
            ...candidate,
            meta: failedMeta,
            creativeScore: 0,
          };
        }
      })
    );

    const selected = selectBestDisplayImage(evaluated);
    const validImageCount = evaluated.filter((entry) => entry.meta.valid).length;
    const score = calculateItemCreativeScore(selected, evaluated);
    const band = toBand(score);
    const combinedIssues = dedupeIssues(evaluated.flatMap((entry) => entry.meta.issues));
    if (validImageCount === 0 && !combinedIssues.includes("no-valid-images")) {
      combinedIssues.push("no-valid-images");
    }

    const analyzedImages = evaluated.map((entry) => ({
      url: entry.url,
      sourceIndex: entry.sourceIndex,
      valid: entry.meta.valid,
      width: entry.meta.width,
      height: entry.meta.height,
      aspectRatio: entry.meta.aspectRatio,
      aspectCategory: entry.meta.aspectCategory,
      format: entry.meta.format,
      sceneType: entry.meta.sceneType,
      displaySuitabilityScore: entry.meta.displaySuitabilityScore,
      sceneMetrics: entry.meta.sceneMetrics,
      issues: entry.meta.issues,
    }));

    const updatePayload: Record<string, unknown> = {
      imageValidation: {
        validated: true,
        validatedAt,
        primaryImage: {
          url: selected.url,
          sourceIndex: selected.sourceIndex,
          valid: selected.meta.valid,
          width: selected.meta.width,
          height: selected.meta.height,
          aspectRatio: selected.meta.aspectRatio,
          aspectCategory: selected.meta.aspectCategory,
          format: selected.meta.format,
          sceneType: selected.meta.sceneType,
          displaySuitabilityScore: selected.meta.displaySuitabilityScore,
          sceneMetrics: selected.meta.sceneMetrics,
          issues: selected.meta.issues,
        },
        primaryImageValid: selected.meta.valid,
        validImageCount,
        totalImageCount: imageCandidates.length,
        analyzedImageCount: analyzedImages.length,
        selectedImageIndex: selected.sourceIndex,
        selectedImageUrl: selected.url,
        selectedSceneType: selected.meta.sceneType,
        selectedDisplaySuitabilityScore: selected.meta.displaySuitabilityScore,
        issues: combinedIssues,
        analyzedImages,
      },
      creativeHealth: {
        score,
        band,
        issues: combinedIssues,
        sceneType: selected.meta.sceneType,
        displaySuitabilityScore: selected.meta.displaySuitabilityScore,
        selectedImageUrl: selected.url,
        validatedAt,
      },
    };

    if (selected.sourceIndex > 0 && rawImages.length > selected.sourceIndex) {
      updatePayload.images = reorderImages(rawImages, selected.sourceIndex);
    }

    await doc.ref.update(updatePayload);

    return {
      itemId: doc.id,
      success: true,
      score,
      band,
      sceneType: selected.meta.sceneType,
      selectedImageUrl: selected.url,
    };
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);

    await doc.ref.update({
      imageValidation: {
        validated: true,
        validatedAt,
        primaryImageValid: false,
        validImageCount: 0,
        totalImageCount: imageCandidates.length,
        issues: ["validation-error"],
        error: errorMsg,
      },
      creativeHealth: {
        score: 0,
        band: "red",
        issues: ["validation-error"],
        validatedAt,
      },
    });

    return {
      itemId: doc.id,
      success: false,
      error: errorMsg,
    };
  }
}

/**
 * Calculate Creative Health score from image metadata.
 */
function calculateCreativeHealthScore(meta: ImageMetaResult): number {
  if (!meta.valid) {
    return 0;
  }

  let structuralScore = 100;

  const minDim = Math.min(meta.width, meta.height);
  if (minDim < 400) {
    structuralScore -= 40;
  } else if (minDim < 800) {
    structuralScore -= 15;
  }

  if (meta.aspectRatio > 3.0 || meta.aspectRatio < 0.33) {
    structuralScore -= 25;
  } else if (meta.aspectRatio > 1.8 || meta.aspectRatio < 0.6) {
    structuralScore -= 10;
  }

  for (const issue of meta.issues) {
    if (issue === "low-resolution") structuralScore -= 20;
    if (issue === "extreme-aspect-ratio") structuralScore -= 15;
    if (issue === "transparent-background") structuralScore -= 8;
    if (issue === "white-background") structuralScore -= 8;
    if (issue === "studio-cutout") structuralScore -= 12;
  }

  const blended = Math.round(structuralScore * 0.45 + meta.displaySuitabilityScore * 0.55);
  return clamp(blended, 0, 100);
}

function selectBestDisplayImage(candidates: EvaluatedImage[]): EvaluatedImage {
  const eligible = candidates.filter(
    (candidate) => candidate.meta.valid && candidate.meta.sceneType !== "studio_cutout"
  );
  const pool = eligible.length > 0 ? eligible : candidates;
  return pool.reduce((best, current) =>
    displayRankScore(current) > displayRankScore(best) ? current : best
  );
}

function displayRankScore(candidate: EvaluatedImage): number {
  let score = candidate.meta.displaySuitabilityScore * 0.7 + candidate.creativeScore * 0.3;
  if (candidate.meta.sceneType === "contextual") score += 6;
  if (candidate.meta.sceneType === "studio_cutout") score -= 6;
  if (!candidate.meta.valid) score -= 20;
  return score;
}

function calculateItemCreativeScore(selected: EvaluatedImage, evaluated: EvaluatedImage[]): number {
  if (evaluated.length === 0) return 0;
  const avgCreative = evaluated.reduce((sum, entry) => sum + entry.creativeScore, 0) / evaluated.length;
  const weighted = selected.creativeScore * 0.75 + avgCreative * 0.25;
  return clamp(Math.round(weighted), 0, 100);
}

function normalizeImageCandidates(images: unknown): NormalizedImageCandidate[] {
  if (!Array.isArray(images)) return [];
  const out: NormalizedImageCandidate[] = [];
  const seen = new Set<string>();

  images.forEach((entry, index) => {
    let url = "";
    if (typeof entry === "string") {
      url = entry.trim();
    } else if (entry && typeof entry === "object") {
      const candidate = (entry as { url?: unknown }).url;
      if (typeof candidate === "string") {
        url = candidate.trim();
      }
    }

    if (!url || seen.has(url)) return;
    seen.add(url);
    out.push({ url, sourceIndex: index });
  });

  return out;
}

function reorderImages(rawImages: unknown[], selectedIndex: number): unknown[] {
  if (selectedIndex <= 0 || selectedIndex >= rawImages.length) return rawImages;
  const reordered = rawImages.slice();
  const [selected] = reordered.splice(selectedIndex, 1);
  reordered.unshift(selected);
  return reordered;
}

function classifyValidationIssue(error: unknown): string {
  const message = (error instanceof Error ? error.message : String(error)).toLowerCase();
  if (message.includes("timed out") || message.includes("timeout")) return "timeout";
  if (message.includes("not an image")) return "non-image-response";
  if (message.includes("too large")) return "image-too-large";
  if (message.includes("domain is not allowed")) return "domain-blocked";
  if (message.includes("upstream error") || message.includes("upstream")) return "fetch-failed";
  return "validation-error";
}

function buildFailedMeta(url: string, issue: string): ImageMetaResult {
  return {
    valid: false,
    url,
    domain: parseDomain(url),
    width: 0,
    height: 0,
    aspectRatio: 0,
    aspectCategory: "unknown",
    format: "unknown",
    size: 0,
    sceneType: "unknown",
    displaySuitabilityScore: 0,
    sceneMetrics: {
      backgroundRatio: 0,
      borderBackgroundRatio: 0,
      nearWhiteRatio: 0,
      transparentRatio: 0,
      subjectCoverage: 0,
      textureScore: 0,
    },
    issues: [issue],
  };
}

function parseDomain(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return "unknown";
  }
}

function dedupeIssues(issues: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const issue of issues) {
    const normalized = issue.trim();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function toBand(score: number): "green" | "yellow" | "red" {
  if (score >= 75) return "green";
  if (score >= 45) return "yellow";
  return "red";
}

function toRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function toStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (typeof entry === "string" ? entry.trim() : ""))
    .filter((entry) => entry.length > 0);
}

function asTrimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export const __adminImageValidationTestUtils = {
  needsImageValidation,
  selectBestDisplayImage,
};
