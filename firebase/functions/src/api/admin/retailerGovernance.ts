import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

/**
 * RetailerGovernance stored in Firestore `retailerGovernance` collection.
 * Per-retailer overrides for the global governance config.
 */
export interface RetailerGovernance {
  retailerId: string;
  frequencyCapOverride?: number | null;    // null = use global
  relevanceThresholdOverride?: number | null;
  pacingStrategyOverride?: "even" | "frontload" | "backload" | null;
  pausedCampaignIds: string[];              // instantly pause campaigns
  blockedProductIds: string[];             // brand safety block list
  updatedAt: string | null;
  updatedBy: string;
}

function toSerializable(doc: admin.firestore.DocumentSnapshot): RetailerGovernance {
  const data = doc.data()!;
  return {
    retailerId: doc.id,
    frequencyCapOverride: data.frequencyCapOverride ?? null,
    relevanceThresholdOverride: data.relevanceThresholdOverride ?? null,
    pacingStrategyOverride: data.pacingStrategyOverride ?? null,
    pausedCampaignIds: data.pausedCampaignIds || [],
    blockedProductIds: data.blockedProductIds || [],
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() ?? null,
    updatedBy: data.updatedBy || "",
  };
}

/**
 * GET /api/admin/retailers/:retailerId/governance
 * Get governance config for a specific retailer.
 */
export async function adminRetailerGovernanceGet(
  req: Request,
  res: Response,
  retailerId: string
): Promise<void> {
  const db = admin.firestore();
  try {
    const doc = await db.collection("retailerGovernance").doc(retailerId).get();

    if (!doc.exists) {
      // Return empty/default structure if no override exists
      res.status(200).json({
        retailerId,
        frequencyCapOverride: null,
        relevanceThresholdOverride: null,
        pacingStrategyOverride: null,
        pausedCampaignIds: [],
        blockedProductIds: [],
        updatedAt: null,
        updatedBy: "",
      });
      return;
    }

    res.status(200).json(toSerializable(doc));
  } catch (error) {
    console.error("Error fetching retailer governance:", error);
    res.status(500).json({ error: "Failed to fetch retailer governance" });
  }
}

/**
 * PATCH /api/admin/retailers/:retailerId/governance
 * Partially update governance overrides for a specific retailer.
 */
export async function adminRetailerGovernancePatch(
  req: Request,
  res: Response,
  retailerId: string
): Promise<void> {
  const db = admin.firestore();
  const body = req.body as Partial<Omit<RetailerGovernance, "retailerId" | "updatedAt" | "updatedBy">>;

  // Validate retailerId
  if (!retailerId || !retailerId.trim()) {
    res.status(400).json({ error: "retailerId is required" });
    return;
  }

  // Validate frequencyCapOverride
  if (body.frequencyCapOverride !== undefined) {
    if (body.frequencyCapOverride !== null) {
      if (!Number.isInteger(body.frequencyCapOverride) || body.frequencyCapOverride < 1) {
        res.status(400).json({ error: "frequencyCapOverride must be a positive integer or null" });
        return;
      }
    }
  }

  // Validate relevanceThresholdOverride
  if (body.relevanceThresholdOverride !== undefined) {
    if (body.relevanceThresholdOverride !== null) {
      if (
        typeof body.relevanceThresholdOverride !== "number" ||
        body.relevanceThresholdOverride < 0 ||
        body.relevanceThresholdOverride > 100
      ) {
        res.status(400).json({
          error: "relevanceThresholdOverride must be a number between 0 and 100 or null",
        });
        return;
      }
    }
  }

  // Validate pacingStrategyOverride
  if (body.pacingStrategyOverride !== undefined && body.pacingStrategyOverride !== null) {
    if (!["even", "frontload", "backload"].includes(body.pacingStrategyOverride)) {
      res.status(400).json({
        error: "pacingStrategyOverride must be one of: even, frontload, backload, or null",
      });
      return;
    }
  }

  // Validate pausedCampaignIds
  if (body.pausedCampaignIds !== undefined) {
    if (!Array.isArray(body.pausedCampaignIds)) {
      res.status(400).json({ error: "pausedCampaignIds must be an array of strings" });
      return;
    }
    for (const id of body.pausedCampaignIds) {
      if (typeof id !== "string") {
        res.status(400).json({ error: "pausedCampaignIds must be an array of strings" });
        return;
      }
    }
  }

  // Validate blockedProductIds
  if (body.blockedProductIds !== undefined) {
    if (!Array.isArray(body.blockedProductIds)) {
      res.status(400).json({ error: "blockedProductIds must be an array of strings" });
      return;
    }
    for (const id of body.blockedProductIds) {
      if (typeof id !== "string") {
        res.status(400).json({ error: "blockedProductIds must be an array of strings" });
        return;
      }
    }
  }

  try {
    const ref = db.collection("retailerGovernance").doc(retailerId);
    const existing = await ref.get();

    const updates: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
      // Carry forward updatedBy from auth header, default to "unknown"
      updatedBy: (req.headers["x-admin-email"] as string) || "unknown",
    };

    if (body.frequencyCapOverride !== undefined) {
      updates.frequencyCapOverride = body.frequencyCapOverride;
    }
    if (body.relevanceThresholdOverride !== undefined) {
      updates.relevanceThresholdOverride = body.relevanceThresholdOverride;
    }
    if (body.pacingStrategyOverride !== undefined) {
      updates.pacingStrategyOverride = body.pacingStrategyOverride;
    }
    if (body.pausedCampaignIds !== undefined) {
      updates.pausedCampaignIds = body.pausedCampaignIds;
    }
    if (body.blockedProductIds !== undefined) {
      updates.blockedProductIds = body.blockedProductIds;
    }

    if (!existing.exists) {
      // Create new retailer governance override
      await ref.set({
        frequencyCapOverride: body.frequencyCapOverride ?? null,
        relevanceThresholdOverride: body.relevanceThresholdOverride ?? null,
        pacingStrategyOverride: body.pacingStrategyOverride ?? null,
        pausedCampaignIds: body.pausedCampaignIds ?? [],
        blockedProductIds: body.blockedProductIds ?? [],
        ...updates,
      });
    } else {
      await ref.update(updates);
    }

    const updated = await ref.get();
    res.status(200).json(toSerializable(updated));
  } catch (error) {
    console.error("Error updating retailer governance:", error);
    res.status(500).json({ error: "Failed to update retailer governance" });
  }
}
