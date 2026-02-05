import { Request, Response } from "express";
import * as admin from "firebase-admin";

/**
 * POST /api/admin/validate-images
 * 
 * Trigger image validation for items that haven't been validated yet.
 * Validates images and calculates Creative Health scores.
 * 
 * Request body:
 * - limit: Max items to validate (default: 50)
 * - retailer: Optional retailer slug to filter
 * - force: Re-validate even if already validated (default: false)
 */
export async function adminValidateImagesPost(req: Request, res: Response): Promise<void> {
  const { limit = 50, retailer, force = false } = req.body;
  const maxLimit = Math.min(100, limit);
  
  const db = admin.firestore();
  
  try {
    // Query items needing validation
    let query = db.collection("items")
      .where("isActive", "==", true);
    
    if (!force) {
      query = query.where("creativeHealth", "==", null);
    }
    
    if (retailer) {
      query = query.where("sourceId", "==", retailer);
    }
    
    const snapshot = await query.limit(maxLimit).get();
    
    if (snapshot.empty) {
      res.json({
        message: "No items need validation",
        validated: 0,
      });
      return;
    }
    
    const results: Array<{
      itemId: string;
      success: boolean;
      score?: number;
      band?: string;
      error?: string;
    }> = [];
    
    // Process items
    for (const doc of snapshot.docs) {
      const item = doc.data();
      const images = item.images as Array<{ url: string }> | undefined;
      
      if (!images || images.length === 0) {
        // No images - mark as invalid
        await doc.ref.update({
          imageValidation: {
            validated: true,
            validatedAt: admin.firestore.FieldValue.serverTimestamp(),
            primaryImageValid: false,
            validImageCount: 0,
            totalImageCount: 0,
            issues: ["no-images"],
          },
          creativeHealth: {
            score: 0,
            band: "red",
            issues: ["no-images"],
          },
        });
        
        results.push({
          itemId: doc.id,
          success: true,
          score: 0,
          band: "red",
        });
        continue;
      }
      
      // Validate primary image only (for speed)
      const primaryUrl = images[0].url;
      
      try {
        // Call our image-meta endpoint internally
        const metaResponse = await fetch(
          `${process.env.FUNCTIONS_URL || ""}/api/image-meta?url=${encodeURIComponent(primaryUrl)}`,
          { headers: { Accept: "application/json" } }
        );
        
        if (!metaResponse.ok) {
          throw new Error(`Meta API returned ${metaResponse.status}`);
        }
        
        const meta = await metaResponse.json() as {
          valid: boolean;
          width: number;
          height: number;
          aspectRatio: number;
          aspectCategory: string;
          format: string;
          size: number;
          issues: string[];
        };
        
        // Calculate Creative Health score
        const score = calculateCreativeHealthScore(meta);
        const band = score >= 75 ? "green" : score >= 45 ? "yellow" : "red";
        
        await doc.ref.update({
          imageValidation: {
            validated: true,
            validatedAt: admin.firestore.FieldValue.serverTimestamp(),
            primaryImage: {
              url: primaryUrl,
              valid: meta.valid,
              width: meta.width,
              height: meta.height,
              aspectRatio: meta.aspectRatio,
              aspectCategory: meta.aspectCategory,
              format: meta.format,
              issues: meta.issues,
            },
            primaryImageValid: meta.valid,
            validImageCount: meta.valid ? 1 : 0,
            totalImageCount: images.length,
            issues: meta.issues,
          },
          creativeHealth: {
            score,
            band,
            issues: meta.issues,
            validatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        });
        
        results.push({
          itemId: doc.id,
          success: true,
          score,
          band,
        });
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        
        await doc.ref.update({
          imageValidation: {
            validated: true,
            validatedAt: admin.firestore.FieldValue.serverTimestamp(),
            primaryImageValid: false,
            validImageCount: 0,
            totalImageCount: images.length,
            issues: ["validation-error"],
            error: errorMsg,
          },
          creativeHealth: {
            score: 0,
            band: "red",
            issues: ["validation-error"],
          },
        });
        
        results.push({
          itemId: doc.id,
          success: false,
          error: errorMsg,
        });
      }
    }
    
    const successCount = results.filter(r => r.success).length;
    const avgScore = results
      .filter(r => r.success && r.score !== undefined)
      .reduce((sum, r) => sum + (r.score || 0), 0) / (successCount || 1);
    
    res.json({
      message: `Validated ${results.length} items`,
      validated: results.length,
      successful: successCount,
      averageScore: Math.round(avgScore),
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
      averageScore: 0,
      commonIssues: {} as Record<string, number>,
    };
    
    let scoreSum = 0;
    let scoredCount = 0;
    
    for (const doc of snapshot.docs) {
      const item = doc.data();
      const health = item.creativeHealth;
      
      if (health && health.score !== undefined) {
        stats.validated++;
        scoreSum += health.score;
        scoredCount++;
        
        const band = health.band as "green" | "yellow" | "red";
        if (band && stats.byBand[band] !== undefined) {
          stats.byBand[band]++;
        }
        
        // Count issues
        const issues = health.issues as string[] | undefined;
        if (issues) {
          for (const issue of issues) {
            stats.commonIssues[issue] = (stats.commonIssues[issue] || 0) + 1;
          }
        }
      } else {
        stats.notValidated++;
      }
    }
    
    stats.averageScore = scoredCount > 0 ? Math.round(scoreSum / scoredCount) : 0;
    
    res.json(stats);
  } catch (error) {
    console.error("Creative health stats error:", error);
    res.status(500).json({ error: "Failed to get stats" });
  }
}

/**
 * Calculate Creative Health score from image metadata.
 */
function calculateCreativeHealthScore(meta: {
  valid: boolean;
  width: number;
  height: number;
  aspectRatio: number;
  issues: string[];
}): number {
  if (!meta.valid) {
    return 0;
  }
  
  let score = 100;
  
  // Resolution scoring
  const minDim = Math.min(meta.width, meta.height);
  if (minDim < 400) {
    score -= 40;
  } else if (minDim < 800) {
    score -= 15;
  }
  
  // Aspect ratio scoring
  if (meta.aspectRatio > 3.0 || meta.aspectRatio < 0.33) {
    score -= 25;
  } else if (meta.aspectRatio > 1.8 || meta.aspectRatio < 0.6) {
    score -= 10;
  }
  
  // Issue-based deductions
  for (const issue of meta.issues) {
    if (issue === "low-resolution") score -= 20;
    if (issue === "extreme-aspect-ratio") score -= 15;
    if (issue === "tiny-file-size") score -= 10;
  }
  
  return Math.max(0, Math.min(100, score));
}
