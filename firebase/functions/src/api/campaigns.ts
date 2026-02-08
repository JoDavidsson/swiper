import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { requireUserAuth } from "../middleware/require_user_auth";
import { buildSegmentSnapshot } from "../targeting/segment_targeting";

type CampaignStatus = "draft" | "active" | "paused" | "ended";
type ProductMode = "all" | "selected" | "auto";

function asTrimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function toBodyObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function toProductMode(value: unknown): ProductMode {
  if (value === "all" || value === "selected" || value === "auto") return value;
  return "all";
}

function toStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out = new Set<string>();
  for (const entry of value) {
    const normalized = asTrimmedString(entry);
    if (normalized) out.add(normalized);
  }
  return Array.from(out);
}

function toNullableNumber(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value;
}

function parseDateToTimestamp(value: unknown): admin.firestore.Timestamp | null {
  if (value == null) return null;
  if (typeof value !== "string" && !(value instanceof Date)) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return admin.firestore.Timestamp.fromDate(date);
}

async function loadCampaignSegmentSnapshot(
  db: admin.firestore.Firestore,
  segmentId: string,
  retailerId: string,
  userUid: string
): Promise<
  | { ok: true; segmentSnapshot: ReturnType<typeof buildSegmentSnapshot> }
  | { ok: false; status: number; error: string }
> {
  const segmentDoc = await db.collection("segments").doc(segmentId).get();
  if (!segmentDoc.exists) {
    return { ok: false, status: 404, error: "Segment not found" };
  }

  const segmentData = (segmentDoc.data() || {}) as Record<string, unknown>;
  const isTemplate = segmentData.isTemplate === true;
  if (!isTemplate) {
    const segmentRetailerId = asTrimmedString(segmentData.retailerId);
    const segmentCreatedBy = asTrimmedString(segmentData.createdBy);
    const retailerMismatch = segmentRetailerId != null && segmentRetailerId !== retailerId;
    const ownerMismatch =
      segmentRetailerId == null && segmentCreatedBy != null && segmentCreatedBy !== userUid;
    if (retailerMismatch || ownerMismatch) {
      return {
        ok: false,
        status: 403,
        error: "Selected segment is not available for this retailer",
      };
    }
  }

  return {
    ok: true,
    segmentSnapshot: buildSegmentSnapshot(segmentDoc.id, segmentData),
  };
}

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

  const body = toBodyObject(req.body);
  const retailerId = asTrimmedString(body.retailerId);
  const name = asTrimmedString(body.name);
  const segmentId = asTrimmedString(body.segmentId);
  const productIds = toStringArray(body.productIds);
  const mode = toProductMode(body.productMode);
  const budgetTotal = toNullableNumber(body.budgetTotal);
  const budgetDaily = toNullableNumber(body.budgetDaily);
  const startDate = parseDateToTimestamp(body.startDate);
  const endDate = parseDateToTimestamp(body.endDate);
  const frequencyCap = toNullableNumber(body.frequencyCap);

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

    const segmentSnapshotResult = await loadCampaignSegmentSnapshot(db, segmentId, retailerId, user.uid);
    if (!segmentSnapshotResult.ok) {
      res.status(segmentSnapshotResult.status).json({ error: segmentSnapshotResult.error });
      return;
    }

    const campaignRef = db.collection("campaigns").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // If productMode is "selected", productIds must be provided
    if (mode === "selected" && productIds.length === 0) {
      res.status(400).json({ error: "productIds required when productMode is 'selected'" });
      return;
    }

    const campaignData = {
      id: campaignRef.id,
      retailerId,
      name,
      segmentId,
      segmentSnapshot: segmentSnapshotResult.segmentSnapshot,
      productIds: mode === "selected" ? productIds : [],
      productMode: mode,
      budgetTotal: budgetTotal ?? null,
      budgetDaily: budgetDaily ?? null,
      budgetSpent: 0,
      startDate,
      endDate,
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
      startDate: startDate?.toDate().toISOString() || null,
      endDate: endDate?.toDate().toISOString() || null,
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

    const body = toBodyObject(req.body);

    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (Object.prototype.hasOwnProperty.call(body, "name")) {
      const nextName = asTrimmedString(body.name);
      if (!nextName) {
        res.status(400).json({ error: "name cannot be empty" });
        return;
      }
      updates.name = nextName;
    }

    if (Object.prototype.hasOwnProperty.call(body, "segmentId")) {
      const nextSegmentId = asTrimmedString(body.segmentId);
      if (!nextSegmentId) {
        res.status(400).json({ error: "segmentId must be a non-empty string" });
        return;
      }
      const segmentSnapshotResult = await loadCampaignSegmentSnapshot(
        db,
        nextSegmentId,
        data.retailerId,
        user.uid
      );
      if (!segmentSnapshotResult.ok) {
        res.status(segmentSnapshotResult.status).json({ error: segmentSnapshotResult.error });
        return;
      }
      updates.segmentId = nextSegmentId;
      updates.segmentSnapshot = segmentSnapshotResult.segmentSnapshot;
    }

    let nextProductMode: ProductMode = toProductMode(data.productMode);
    if (Object.prototype.hasOwnProperty.call(body, "productMode")) {
      const requestedMode = body.productMode;
      if (requestedMode !== "all" && requestedMode !== "selected" && requestedMode !== "auto") {
        res.status(400).json({ error: "Invalid productMode" });
        return;
      }
      nextProductMode = requestedMode;
      updates.productMode = requestedMode;
    }

    let nextProductIds = Array.isArray(data.productIds) ? toStringArray(data.productIds) : [];
    if (Object.prototype.hasOwnProperty.call(body, "productIds")) {
      if (body.productIds != null && !Array.isArray(body.productIds)) {
        res.status(400).json({ error: "productIds must be an array" });
        return;
      }
      nextProductIds = toStringArray(body.productIds);
      updates.productIds = nextProductIds;
    }

    if (nextProductMode === "selected" && nextProductIds.length === 0) {
      res.status(400).json({ error: "productIds required when productMode is 'selected'" });
      return;
    }

    if (Object.prototype.hasOwnProperty.call(body, "budgetTotal")) {
      if (body.budgetTotal != null && toNullableNumber(body.budgetTotal) == null) {
        res.status(400).json({ error: "budgetTotal must be a number or null" });
        return;
      }
      updates.budgetTotal = toNullableNumber(body.budgetTotal);
    }

    if (Object.prototype.hasOwnProperty.call(body, "budgetDaily")) {
      if (body.budgetDaily != null && toNullableNumber(body.budgetDaily) == null) {
        res.status(400).json({ error: "budgetDaily must be a number or null" });
        return;
      }
      updates.budgetDaily = toNullableNumber(body.budgetDaily);
    }

    if (Object.prototype.hasOwnProperty.call(body, "startDate")) {
      if (body.startDate != null && parseDateToTimestamp(body.startDate) == null) {
        res.status(400).json({ error: "startDate must be a valid date string or null" });
        return;
      }
      updates.startDate = parseDateToTimestamp(body.startDate);
    }

    if (Object.prototype.hasOwnProperty.call(body, "endDate")) {
      if (body.endDate != null && parseDateToTimestamp(body.endDate) == null) {
        res.status(400).json({ error: "endDate must be a valid date string or null" });
        return;
      }
      updates.endDate = parseDateToTimestamp(body.endDate);
    }

    if (Object.prototype.hasOwnProperty.call(body, "frequencyCap")) {
      if (body.frequencyCap != null && toNullableNumber(body.frequencyCap) == null) {
        res.status(400).json({ error: "frequencyCap must be a number or null" });
        return;
      }
      updates.frequencyCap = toNullableNumber(body.frequencyCap);
    }

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
