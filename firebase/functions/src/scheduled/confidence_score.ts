import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { SEGMENT_TEMPLATES } from "../api/segments";

/**
 * Time windows for score calculation.
 */
const TIME_WINDOWS = ["7d", "30d", "90d"] as const;
type TimeWindow = typeof TIME_WINDOWS[number];

/**
 * Bayesian smoothing parameters.
 * Prior gives stability for low-volume items.
 */
const BAYESIAN_PRIOR_SAVES = 2; // Assumed prior saves
const BAYESIAN_PRIOR_IMPRESSIONS = 100; // Assumed prior impressions (2% base save rate)

/**
 * Score component weights (must sum to 100).
 */
const WEIGHTS = {
  saveRate: 50, // Primary engagement signal
  clickRate: 15, // Secondary engagement
  volume: 15, // Impression volume confidence
  creative: 20, // Image quality
};

/**
 * Reason code definitions.
 */
interface ReasonCode {
  code: string;
  label: string;
  impact: "positive" | "negative" | "neutral";
}

/**
 * Generate reason codes based on metrics.
 */
function generateReasonCodes(
  saveRate: number,
  clickRate: number,
  impressions: number,
  skipRate: number,
  creativeHealthScore: number | null
): ReasonCode[] {
  const reasons: ReasonCode[] = [];

  // Save rate signals
  if (saveRate >= 0.05) {
    reasons.push({
      code: "STRONG_SAVES",
      label: "Strong save rate (5%+)",
      impact: "positive",
    });
  } else if (saveRate >= 0.03) {
    reasons.push({
      code: "GOOD_SAVES",
      label: "Good save rate",
      impact: "positive",
    });
  } else if (saveRate < 0.01 && impressions >= 50) {
    reasons.push({
      code: "LOW_SAVES",
      label: "Low save rate (<1%)",
      impact: "negative",
    });
  }

  // Click rate signals
  if (clickRate >= 0.10) {
    reasons.push({
      code: "HIGH_CLICKS",
      label: "High click-through (10%+)",
      impact: "positive",
    });
  } else if (clickRate < 0.02 && impressions >= 50) {
    reasons.push({
      code: "LOW_CLICKS",
      label: "Low engagement clicks",
      impact: "negative",
    });
  }

  // Skip rate signals
  if (skipRate >= 0.8) {
    reasons.push({
      code: "HIGH_SKIP",
      label: "Frequently skipped (80%+)",
      impact: "negative",
    });
  }

  // Volume signals
  if (impressions < 20) {
    reasons.push({
      code: "LOW_VOLUME",
      label: "Limited data (needs more impressions)",
      impact: "neutral",
    });
  } else if (impressions >= 500) {
    reasons.push({
      code: "HIGH_CONFIDENCE",
      label: "High confidence (500+ impressions)",
      impact: "positive",
    });
  }

  // Creative health signals
  if (creativeHealthScore !== null) {
    if (creativeHealthScore >= 80) {
      reasons.push({
        code: "EXCELLENT_CREATIVE",
        label: "Excellent image quality",
        impact: "positive",
      });
    } else if (creativeHealthScore < 50) {
      reasons.push({
        code: "CREATIVE_ISSUES",
        label: "Image quality concerns",
        impact: "negative",
      });
    }
  }

  return reasons;
}

/**
 * Calculate Bayesian-smoothed save rate.
 * Uses empirical Bayes to stabilize rates for low-volume items.
 */
function calculateBayesianSaveRate(saves: number, impressions: number): number {
  // (saves + prior_saves) / (impressions + prior_impressions)
  return (saves + BAYESIAN_PRIOR_SAVES) / (impressions + BAYESIAN_PRIOR_IMPRESSIONS);
}

/**
 * Calculate volume score (0-100).
 * Rewards items with more impressions, maxing at ~500.
 */
function calculateVolumeScore(impressions: number): number {
  // Logarithmic scale, maxing at 100 around 500 impressions
  if (impressions === 0) return 0;
  const score = Math.log10(impressions + 1) / Math.log10(500) * 100;
  return Math.min(100, Math.max(0, score));
}

/**
 * Calculate confidence score (0-100).
 */
function calculateConfidenceScore(
  saves: number,
  impressions: number,
  clicks: number,
  skips: number,
  creativeHealthScore: number | null
): { score: number; metrics: ScoreMetrics; reasonCodes: ReasonCode[] } {
  // Calculate raw rates
  const saveRate = impressions > 0 ? saves / impressions : 0;
  const clickRate = impressions > 0 ? clicks / impressions : 0;
  const skipRate = impressions > 0 ? skips / impressions : 0;

  // Bayesian-smoothed save rate for scoring
  const bayesianSaveRate = calculateBayesianSaveRate(saves, impressions);

  // Component scores (0-100)
  const saveScore = Math.min(100, bayesianSaveRate * 2000); // 5% = 100
  const clickScore = Math.min(100, clickRate * 1000); // 10% = 100
  const volumeScore = calculateVolumeScore(impressions);
  const creativeScore = creativeHealthScore ?? 70; // Default to 70 if unknown

  // Weighted average
  const score = Math.round(
    (saveScore * WEIGHTS.saveRate +
      clickScore * WEIGHTS.clickRate +
      volumeScore * WEIGHTS.volume +
      creativeScore * WEIGHTS.creative) /
      100
  );

  const metrics: ScoreMetrics = {
    impressions,
    saves,
    saveRate: Math.round(saveRate * 10000) / 100, // As percentage with 2 decimals
    clicks,
    clickRate: Math.round(clickRate * 10000) / 100,
    skips,
    skipRate: Math.round(skipRate * 10000) / 100,
  };

  const reasonCodes = generateReasonCodes(saveRate, clickRate, impressions, skipRate, creativeHealthScore);

  return {
    score: Math.max(0, Math.min(100, score)),
    metrics,
    reasonCodes,
  };
}

interface ScoreMetrics {
  impressions: number;
  saves: number;
  saveRate: number;
  clicks: number;
  clickRate: number;
  skips: number;
  skipRate: number;
}

/**
 * Get date range for time window.
 */
function getDateRange(timeWindow: TimeWindow): { start: Date; end: Date } {
  const end = new Date();
  const start = new Date();

  switch (timeWindow) {
    case "7d":
      start.setDate(start.getDate() - 7);
      break;
    case "30d":
      start.setDate(start.getDate() - 30);
      break;
    case "90d":
      start.setDate(start.getDate() - 90);
      break;
  }

  return { start, end };
}

/**
 * Aggregate events for a product in a segment over a time window.
 */
async function aggregateProductEvents(
  productId: string,
  segmentId: string,
  timeWindow: TimeWindow
): Promise<{ impressions: number; saves: number; clicks: number; skips: number }> {
  const db = admin.firestore();
  const { start, end } = getDateRange(timeWindow);
  const startTimestamp = admin.firestore.Timestamp.fromDate(start);
  const endTimestamp = admin.firestore.Timestamp.fromDate(end);

  // Query events collection for this product
  // Note: In production, events would be pre-aggregated for efficiency
  const eventsRef = db.collection("events");

  // Count impressions (product shown)
  const impressionsSnap = await eventsRef
    .where("productId", "==", productId)
    .where("eventType", "==", "impression")
    .where("timestamp", ">=", startTimestamp)
    .where("timestamp", "<=", endTimestamp)
    .get();

  // Count saves (right swipe / like)
  const savesSnap = await eventsRef
    .where("productId", "==", productId)
    .where("eventType", "==", "save")
    .where("timestamp", ">=", startTimestamp)
    .where("timestamp", "<=", endTimestamp)
    .get();

  // Count clicks (detail view)
  const clicksSnap = await eventsRef
    .where("productId", "==", productId)
    .where("eventType", "==", "click")
    .where("timestamp", ">=", startTimestamp)
    .where("timestamp", "<=", endTimestamp)
    .get();

  // Count skips (left swipe / reject)
  const skipsSnap = await eventsRef
    .where("productId", "==", productId)
    .where("eventType", "==", "skip")
    .where("timestamp", ">=", startTimestamp)
    .where("timestamp", "<=", endTimestamp)
    .get();

  return {
    impressions: impressionsSnap.size,
    saves: savesSnap.size,
    clicks: clicksSnap.size,
    skips: skipsSnap.size,
  };
}

/**
 * Get creative health score for a product.
 */
async function getCreativeHealthScore(productId: string): Promise<number | null> {
  const db = admin.firestore();
  const itemDoc = await db.collection("items").doc(productId).get();
  if (!itemDoc.exists) return null;

  const data = itemDoc.data();
  return data?.creativeHealthScore ?? null;
}

/**
 * Calculate and store scores for all products in a segment.
 */
async function calculateSegmentScores(segmentId: string): Promise<number> {
  const db = admin.firestore();
  console.log(`Calculating scores for segment: ${segmentId}`);

  // Get all active products
  // In production, this would filter by segment criteria
  const itemsSnap = await db.collection("items")
    .where("status", "==", "active")
    .limit(1000) // Batch limit
    .get();

  let processedCount = 0;
  const batch = db.batch();
  const batchSize = 500;
  let currentBatchCount = 0;

  for (const itemDoc of itemsSnap.docs) {
    const productId = itemDoc.id;
    const creativeHealthScore = await getCreativeHealthScore(productId);

    for (const timeWindow of TIME_WINDOWS) {
      // Aggregate events
      const events = await aggregateProductEvents(productId, segmentId, timeWindow);

      // Calculate score
      const { score, metrics, reasonCodes } = calculateConfidenceScore(
        events.saves,
        events.impressions,
        events.clicks,
        events.skips,
        creativeHealthScore
      );

      // Create score document ID: productId_segmentId_timeWindow
      const scoreId = `${productId}_${segmentId}_${timeWindow}`;
      const scoreRef = db.collection("scores").doc(scoreId);

      batch.set(scoreRef, {
        id: scoreId,
        productId,
        segmentId,
        timeWindow,
        score,
        ...metrics,
        creativeHealthScore,
        reasonCodes,
        calculatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      currentBatchCount++;

      // Commit batch if it's getting large
      if (currentBatchCount >= batchSize) {
        await batch.commit();
        currentBatchCount = 0;
      }
    }

    processedCount++;
  }

  // Commit remaining
  if (currentBatchCount > 0) {
    await batch.commit();
  }

  console.log(`Processed ${processedCount} products for segment ${segmentId}`);
  return processedCount;
}

/**
 * Scheduled function to calculate confidence scores.
 * Runs hourly to update scores for all segments.
 */
export const calculateConfidenceScores = functions.pubsub
  .schedule("every 1 hours")
  .timeZone("Europe/Stockholm")
  .onRun(async (_context) => {
    const db = admin.firestore();
    console.log("Starting confidence score calculation...");

    const startTime = Date.now();
    let totalProcessed = 0;

    try {
      // Process system segment templates
      for (const template of SEGMENT_TEMPLATES) {
        const count = await calculateSegmentScores(template.id);
        totalProcessed += count;
      }

      // Process custom segments
      const customSegmentsSnap = await db.collection("segments")
        .where("isTemplate", "==", false)
        .limit(50) // Limit custom segments per run
        .get();

      for (const segmentDoc of customSegmentsSnap.docs) {
        const count = await calculateSegmentScores(segmentDoc.id);
        totalProcessed += count;
      }

      // Check for manual recalculation jobs
      const pendingJobsSnap = await db.collection("scoreRecalculationJobs")
        .where("status", "==", "pending")
        .limit(10)
        .get();

      for (const jobDoc of pendingJobsSnap.docs) {
        const jobData = jobDoc.data();

        if (jobData.segmentId) {
          await calculateSegmentScores(jobData.segmentId);
        }

        // Mark job as completed
        await jobDoc.ref.update({
          status: "completed",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const duration = Date.now() - startTime;
      console.log(`Confidence score calculation completed. Processed ${totalProcessed} products in ${duration}ms`);

      // Log summary
      await db.collection("scoreCalculationLogs").add({
        productsProcessed: totalProcessed,
        durationMs: duration,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "success",
      });

      return null;
    } catch (error) {
      console.error("Error calculating confidence scores:", error);

      // Log error
      await db.collection("scoreCalculationLogs").add({
        productsProcessed: totalProcessed,
        durationMs: Date.now() - startTime,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "error",
        error: String(error),
      });

      throw error;
    }
  });

/**
 * HTTP trigger for manual score recalculation (for testing).
 * In production, use the scheduled function.
 */
export async function manualScoreRecalculation(segmentId?: string): Promise<{ processed: number }> {
  let totalProcessed = 0;

  if (segmentId) {
    totalProcessed = await calculateSegmentScores(segmentId);
  } else {
    // Process all templates
    for (const template of SEGMENT_TEMPLATES) {
      const count = await calculateSegmentScores(template.id);
      totalProcessed += count;
    }
  }

  return { processed: totalProcessed };
}
