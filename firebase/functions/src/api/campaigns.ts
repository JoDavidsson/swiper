import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { requireUserAuth } from "../middleware/require_user_auth";

type CampaignStatus = "draft" | "active" | "paused" | "ended";
type ProductMode = "all" | "selected" | "auto";

/**
 * POST /api/retailer/campaigns
 * Create a new campaign (requires retailer auth).
 */
export async function retailerCampaignsPost(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const {
    retailerId,
    name,
    segmentId,
    productIds,
    productMode,
    budgetTotal,
    budgetDaily,
    startDate,
    endDate,
    frequencyCap,
  } = req.body;

  if (!retailerId || !name || !segmentId) {
    res.status(400).json({ error: "retailerId, name, and segmentId are required" });
    return;
  }

  try {
    // Verify user owns the retailer
    const retailerDoc = await db.collection("retailers").doc(retailerId).get();
    if (!retailerDoc.exists) {
      res.status(404).json({ error: "Retailer not found" });
      return;
    }

    const retailerData = retailerDoc.data()!;
    if (!retailerData.ownerUserIds?.includes(user.uid)) {
      res.status(403).json({ error: "You don't own this retailer" });
      return;
    }

    // Verify segment exists
    const segmentDoc = await db.collection("segments").doc(segmentId).get();
    if (!segmentDoc.exists) {
      res.status(404).json({ error: "Segment not found" });
      return;
    }

    const campaignRef = db.collection("campaigns").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Validate productMode
    const validProductModes: ProductMode[] = ["all", "selected", "auto"];
    const mode: ProductMode = validProductModes.includes(productMode) ? productMode : "all";

    // If productMode is "selected", productIds must be provided
    if (mode === "selected" && (!productIds || !Array.isArray(productIds) || productIds.length === 0)) {
      res.status(400).json({ error: "productIds required when productMode is 'selected'" });
      return;
    }

    const campaignData = {
      id: campaignRef.id,
      retailerId,
      name,
      segmentId,
      productIds: mode === "selected" ? productIds : [],
      productMode: mode,
      budgetTotal: budgetTotal ?? null,
      budgetDaily: budgetDaily ?? null,
      budgetSpent: 0,
      startDate: startDate ? admin.firestore.Timestamp.fromDate(new Date(startDate)) : null,
      endDate: endDate ? admin.firestore.Timestamp.fromDate(new Date(endDate)) : null,
      status: "draft" as CampaignStatus,
      frequencyCap: frequencyCap ?? null, // Max impressions per user
      impressions: 0,
      clicks: 0,
      createdBy: user.uid,
      createdAt: now,
      updatedAt: now,
    };

    await campaignRef.set(campaignData);

    res.status(201).json({
      ...campaignData,
      startDate: startDate || null,
      endDate: endDate || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error("Error creating campaign:", error);
    res.status(500).json({ error: "Failed to create campaign" });
  }
}

/**
 * GET /api/retailer/campaigns
 * List campaigns for a retailer (requires auth).
 */
export async function retailerCampaignsGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const retailerId = req.query.retailerId as string | undefined;
  const status = req.query.status as CampaignStatus | undefined;
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);

  try {
    // If no retailerId, find user's retailers first
    let retailerIds: string[] = [];
    
    if (retailerId) {
      // Verify user owns this retailer
      const retailerDoc = await db.collection("retailers").doc(retailerId).get();
      if (!retailerDoc.exists || !retailerDoc.data()?.ownerUserIds?.includes(user.uid)) {
        res.status(403).json({ error: "Access denied to this retailer" });
        return;
      }
      retailerIds = [retailerId];
    } else {
      // Find all retailers owned by user
      const retailersSnap = await db.collection("retailers")
        .where("ownerUserIds", "array-contains", user.uid)
        .get();
      retailerIds = retailersSnap.docs.map(doc => doc.id);
    }

    if (retailerIds.length === 0) {
      res.json({ campaigns: [] });
      return;
    }

    // Query campaigns for these retailers
    let query = db.collection("campaigns")
      .where("retailerId", "in", retailerIds.slice(0, 10)) // Firestore limit
      .orderBy("createdAt", "desc")
      .limit(limit);

    if (status) {
      query = db.collection("campaigns")
        .where("retailerId", "in", retailerIds.slice(0, 10))
        .where("status", "==", status)
        .orderBy("createdAt", "desc")
        .limit(limit);
    }

    const snapshot = await query.get();
    const campaigns = snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        ...data,
        startDate: data.startDate?.toDate?.()?.toISOString() || null,
        endDate: data.endDate?.toDate?.()?.toISOString() || null,
        createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
        updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
      };
    });

    res.json({ campaigns });
  } catch (error) {
    console.error("Error listing campaigns:", error);
    res.status(500).json({ error: "Failed to list campaigns" });
  }
}

/**
 * GET /api/retailer/campaigns/:id
 * Get campaign by ID (requires auth).
 */
export async function retailerCampaignsGetById(req: Request, res: Response, campaignId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const doc = await db.collection("campaigns").doc(campaignId).get();

    if (!doc.exists) {
      res.status(404).json({ error: "Campaign not found" });
      return;
    }

    const data = doc.data()!;

    // Verify user owns the campaign's retailer
    const retailerDoc = await db.collection("retailers").doc(data.retailerId).get();
    if (!retailerDoc.exists || !retailerDoc.data()?.ownerUserIds?.includes(user.uid)) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    res.json({
      id: doc.id,
      ...data,
      startDate: data.startDate?.toDate?.()?.toISOString() || null,
      endDate: data.endDate?.toDate?.()?.toISOString() || null,
      createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
      updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
    });
  } catch (error) {
    console.error("Error getting campaign:", error);
    res.status(500).json({ error: "Failed to get campaign" });
  }
}

/**
 * PATCH /api/retailer/campaigns/:id
 * Update a campaign (requires auth).
 */
export async function retailerCampaignsPatch(req: Request, res: Response, campaignId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const campaignRef = db.collection("campaigns").doc(campaignId);
    const doc = await campaignRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Campaign not found" });
      return;
    }

    const data = doc.data()!;

    // Verify user owns the campaign's retailer
    const retailerDoc = await db.collection("retailers").doc(data.retailerId).get();
    if (!retailerDoc.exists || !retailerDoc.data()?.ownerUserIds?.includes(user.uid)) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    const {
      name,
      segmentId,
      productIds,
      productMode,
      budgetTotal,
      budgetDaily,
      startDate,
      endDate,
      frequencyCap,
    } = req.body;

    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (name !== undefined) updates.name = name;
    if (segmentId !== undefined) {
      // Verify new segment exists
      const segmentDoc = await db.collection("segments").doc(segmentId).get();
      if (!segmentDoc.exists) {
        res.status(404).json({ error: "Segment not found" });
        return;
      }
      updates.segmentId = segmentId;
    }
    if (productIds !== undefined) updates.productIds = productIds;
    if (productMode !== undefined) {
      const validModes: ProductMode[] = ["all", "selected", "auto"];
      if (!validModes.includes(productMode)) {
        res.status(400).json({ error: "Invalid productMode" });
        return;
      }
      updates.productMode = productMode;
    }
    if (budgetTotal !== undefined) updates.budgetTotal = budgetTotal;
    if (budgetDaily !== undefined) updates.budgetDaily = budgetDaily;
    if (startDate !== undefined) {
      updates.startDate = startDate ? admin.firestore.Timestamp.fromDate(new Date(startDate)) : null;
    }
    if (endDate !== undefined) {
      updates.endDate = endDate ? admin.firestore.Timestamp.fromDate(new Date(endDate)) : null;
    }
    if (frequencyCap !== undefined) updates.frequencyCap = frequencyCap;

    await campaignRef.update(updates);

    const updated = await campaignRef.get();
    const updatedData = updated.data()!;
    res.json({
      id: updated.id,
      ...updatedData,
      startDate: updatedData.startDate?.toDate?.()?.toISOString() || null,
      endDate: updatedData.endDate?.toDate?.()?.toISOString() || null,
      createdAt: updatedData.createdAt?.toDate?.()?.toISOString() || null,
      updatedAt: updatedData.updatedAt?.toDate?.()?.toISOString() || null,
    });
  } catch (error) {
    console.error("Error updating campaign:", error);
    res.status(500).json({ error: "Failed to update campaign" });
  }
}

/**
 * POST /api/retailer/campaigns/:id/pause
 * Pause a campaign (requires auth).
 */
export async function retailerCampaignsPause(req: Request, res: Response, campaignId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const campaignRef = db.collection("campaigns").doc(campaignId);
    const doc = await campaignRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Campaign not found" });
      return;
    }

    const data = doc.data()!;

    // Verify user owns the campaign's retailer
    const retailerDoc = await db.collection("retailers").doc(data.retailerId).get();
    if (!retailerDoc.exists || !retailerDoc.data()?.ownerUserIds?.includes(user.uid)) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    // Can only pause active campaigns
    if (data.status !== "active") {
      res.status(400).json({ error: "Can only pause active campaigns" });
      return;
    }

    await campaignRef.update({
      status: "paused",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ success: true, message: "Campaign paused", campaignId });
  } catch (error) {
    console.error("Error pausing campaign:", error);
    res.status(500).json({ error: "Failed to pause campaign" });
  }
}

/**
 * POST /api/retailer/campaigns/:id/activate
 * Activate a campaign (requires auth).
 */
export async function retailerCampaignsActivate(req: Request, res: Response, campaignId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const campaignRef = db.collection("campaigns").doc(campaignId);
    const doc = await campaignRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Campaign not found" });
      return;
    }

    const data = doc.data()!;

    // Verify user owns the campaign's retailer
    const retailerDoc = await db.collection("retailers").doc(data.retailerId).get();
    if (!retailerDoc.exists || !retailerDoc.data()?.ownerUserIds?.includes(user.uid)) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    // Can only activate draft or paused campaigns
    if (!["draft", "paused"].includes(data.status)) {
      res.status(400).json({ error: "Can only activate draft or paused campaigns" });
      return;
    }

    await campaignRef.update({
      status: "active",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ success: true, message: "Campaign activated", campaignId });
  } catch (error) {
    console.error("Error activating campaign:", error);
    res.status(500).json({ error: "Failed to activate campaign" });
  }
}

/**
 * DELETE /api/retailer/campaigns/:id
 * Delete a campaign (requires auth, only draft campaigns).
 */
export async function retailerCampaignsDelete(req: Request, res: Response, campaignId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const campaignRef = db.collection("campaigns").doc(campaignId);
    const doc = await campaignRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Campaign not found" });
      return;
    }

    const data = doc.data()!;

    // Verify user owns the campaign's retailer
    const retailerDoc = await db.collection("retailers").doc(data.retailerId).get();
    if (!retailerDoc.exists || !retailerDoc.data()?.ownerUserIds?.includes(user.uid)) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    // Can only delete draft campaigns
    if (data.status !== "draft") {
      res.status(400).json({ error: "Can only delete draft campaigns. Pause or end active campaigns first." });
      return;
    }

    await campaignRef.delete();
    res.json({ success: true, message: "Campaign deleted" });
  } catch (error) {
    console.error("Error deleting campaign:", error);
    res.status(500).json({ error: "Failed to delete campaign" });
  }
}
