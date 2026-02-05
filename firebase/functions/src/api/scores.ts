import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { requireUserAuth } from "../middleware/require_user_auth";
import { requireAdmin } from "../middleware/require_admin";

/**
 * Score bands based on confidence score value.
 */
export type ScoreBand = "green" | "yellow" | "red";

export function getScoreBand(score: number): ScoreBand {
  if (score >= 60) return "green";
  if (score >= 30) return "yellow";
  return "red";
}

/**
 * GET /api/scores
 * Query scores for products (requires retailer auth).
 * 
 * Query params:
 * - segmentId (required): Segment to filter by
 * - productIds (optional): Comma-separated list of product IDs
 * - timeWindow (optional): "7d" | "30d" | "90d" (default: "30d")
 * - band (optional): Filter by score band "green" | "yellow" | "red"
 * - limit (optional): Max results (default: 50, max: 100)
 */
export async function scoresGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const segmentId = req.query.segmentId as string | undefined;
  const productIdsParam = req.query.productIds as string | undefined;
  const timeWindow = (req.query.timeWindow as string) || "30d";
  const band = req.query.band as ScoreBand | undefined;
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);

  if (!segmentId) {
    res.status(400).json({ error: "segmentId is required" });
    return;
  }

  // Validate time window
  const validTimeWindows = ["7d", "30d", "90d"];
  if (!validTimeWindows.includes(timeWindow)) {
    res.status(400).json({ error: "Invalid timeWindow. Use 7d, 30d, or 90d" });
    return;
  }

  try {
    // Build query
    let query = db.collection("scores")
      .where("segmentId", "==", segmentId)
      .where("timeWindow", "==", timeWindow)
      .orderBy("score", "desc")
      .limit(limit);

    // If productIds provided, filter by them
    const productIds = productIdsParam?.split(",").map(id => id.trim()).filter(Boolean);
    if (productIds && productIds.length > 0) {
      // Firestore "in" queries limited to 30 items
      if (productIds.length > 30) {
        res.status(400).json({ error: "Maximum 30 productIds allowed per query" });
        return;
      }
      query = db.collection("scores")
        .where("segmentId", "==", segmentId)
        .where("timeWindow", "==", timeWindow)
        .where("productId", "in", productIds)
        .orderBy("score", "desc")
        .limit(limit);
    }

    const snapshot = await query.get();
    let scores = snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        productId: data.productId,
        segmentId: data.segmentId,
        timeWindow: data.timeWindow,
        score: data.score,
        band: getScoreBand(data.score),
        reasonCodes: data.reasonCodes || [],
        metrics: {
          impressions: data.impressions || 0,
          saves: data.saves || 0,
          saveRate: data.saveRate || 0,
          clicks: data.clicks || 0,
          clickRate: data.clickRate || 0,
          skipRate: data.skipRate || 0,
        },
        creativeHealthScore: data.creativeHealthScore ?? null,
        calculatedAt: data.calculatedAt?.toDate?.()?.toISOString() || null,
      };
    });

    // Filter by band if specified (post-query since Firestore can't filter by computed field)
    if (band) {
      scores = scores.filter(s => s.band === band);
    }

    res.json({ scores });
  } catch (error) {
    console.error("Error querying scores:", error);
    res.status(500).json({ error: "Failed to query scores" });
  }
}

/**
 * GET /api/scores/:productId
 * Get scores for a specific product across segments.
 */
export async function scoresGetByProduct(req: Request, res: Response, productId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const timeWindow = (req.query.timeWindow as string) || "30d";

  try {
    const snapshot = await db.collection("scores")
      .where("productId", "==", productId)
      .where("timeWindow", "==", timeWindow)
      .orderBy("score", "desc")
      .get();

    const scores = snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        productId: data.productId,
        segmentId: data.segmentId,
        timeWindow: data.timeWindow,
        score: data.score,
        band: getScoreBand(data.score),
        reasonCodes: data.reasonCodes || [],
        metrics: {
          impressions: data.impressions || 0,
          saves: data.saves || 0,
          saveRate: data.saveRate || 0,
          clicks: data.clicks || 0,
          clickRate: data.clickRate || 0,
          skipRate: data.skipRate || 0,
        },
        creativeHealthScore: data.creativeHealthScore ?? null,
        calculatedAt: data.calculatedAt?.toDate?.()?.toISOString() || null,
      };
    });

    res.json({ productId, timeWindow, scores });
  } catch (error) {
    console.error("Error getting product scores:", error);
    res.status(500).json({ error: "Failed to get product scores" });
  }
}

/**
 * GET /api/admin/scores/summary
 * Get aggregate score statistics (admin only).
 */
export async function adminScoresSummaryGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const isAdmin = await requireAdmin(req);
  if (!isAdmin) {
    res.status(403).json({ error: "Admin access required" });
    return;
  }

  const segmentId = req.query.segmentId as string | undefined;
  const timeWindow = (req.query.timeWindow as string) || "30d";

  try {
    let query = db.collection("scores")
      .where("timeWindow", "==", timeWindow);

    if (segmentId) {
      query = query.where("segmentId", "==", segmentId);
    }

    const snapshot = await query.get();

    // Calculate summary stats
    let totalScores = 0;
    let scoreSum = 0;
    let greenCount = 0;
    let yellowCount = 0;
    let redCount = 0;

    snapshot.docs.forEach(doc => {
      const data = doc.data();
      totalScores++;
      scoreSum += data.score || 0;

      const band = getScoreBand(data.score || 0);
      if (band === "green") greenCount++;
      else if (band === "yellow") yellowCount++;
      else redCount++;
    });

    const averageScore = totalScores > 0 ? Math.round(scoreSum / totalScores) : 0;

    res.json({
      timeWindow,
      segmentId: segmentId || "all",
      totalProducts: totalScores,
      averageScore,
      distribution: {
        green: greenCount,
        yellow: yellowCount,
        red: redCount,
      },
      percentages: {
        green: totalScores > 0 ? Math.round((greenCount / totalScores) * 100) : 0,
        yellow: totalScores > 0 ? Math.round((yellowCount / totalScores) * 100) : 0,
        red: totalScores > 0 ? Math.round((redCount / totalScores) * 100) : 0,
      },
    });
  } catch (error) {
    console.error("Error getting score summary:", error);
    res.status(500).json({ error: "Failed to get score summary" });
  }
}

/**
 * POST /api/admin/scores/recalculate
 * Trigger score recalculation (admin only).
 */
export async function adminScoresRecalculatePost(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const isAdmin = await requireAdmin(req);
  if (!isAdmin) {
    res.status(403).json({ error: "Admin access required" });
    return;
  }

  const { segmentId, productIds } = req.body;

  try {
    // Create a recalculation job record
    const jobRef = db.collection("scoreRecalculationJobs").doc();
    await jobRef.set({
      id: jobRef.id,
      segmentId: segmentId || null,
      productIds: productIds || null,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Note: The actual recalculation is handled by the scheduled function
    // This just queues a job for immediate processing

    res.json({
      success: true,
      message: "Score recalculation job queued",
      jobId: jobRef.id,
    });
  } catch (error) {
    console.error("Error queuing recalculation:", error);
    res.status(500).json({ error: "Failed to queue recalculation" });
  }
}
