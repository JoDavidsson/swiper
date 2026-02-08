import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { requireUserAuth } from "../middleware/require_user_auth";
import { buildSegmentSnapshot } from "../targeting/segment_targeting";

type CampaignStatus = "draft" | "active" | "paused" | "ended";
type ProductMode = "all" | "selected" | "auto";
const DEFAULT_RECOMMENDATION_LIMIT = 24;

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

function toPositiveNumber(value: unknown): number | null {
  const parsed = toNullableNumber(value);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

function normalizeRetailerSlug(value: unknown): string | null {
  const token = asTrimmedString(value);
  return token ? token.toLowerCase() : null;
}

function parseDateToTimestamp(value: unknown): admin.firestore.Timestamp | null {
  if (value == null) return null;
  if (typeof value !== "string" && !(value instanceof Date)) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return admin.firestore.Timestamp.fromDate(date);
}

function formatTimestamp(value: unknown): string | null {
  if (!value) return null;
  const ts = value as { toDate?: () => Date };
  if (typeof ts.toDate !== "function") return null;
  return ts.toDate().toISOString();
}

function toCampaignResponse(id: string, data: Record<string, unknown>): Record<string, unknown> {
  return {
    id,
    ...data,
    startDate: formatTimestamp(data.startDate),
    endDate: formatTimestamp(data.endDate),
    createdAt: formatTimestamp(data.createdAt),
    updatedAt: formatTimestamp(data.updatedAt),
    recommendedAt: formatTimestamp(data.recommendedAt),
  };
}

function validateBudgetAndSchedule(input: {
  budgetTotal: number | null;
  budgetDaily: number | null;
  startDate: admin.firestore.Timestamp | null;
  endDate: admin.firestore.Timestamp | null;
  frequencyCap: number | null;
}): Array<{ field: string; message: string }> {
  const issues: Array<{ field: string; message: string }> = [];
  if (input.budgetTotal != null && input.budgetTotal <= 0) {
    issues.push({ field: "budgetTotal", message: "must be greater than 0 when provided" });
  }
  if (input.budgetDaily != null && input.budgetDaily <= 0) {
    issues.push({ field: "budgetDaily", message: "must be greater than 0 when provided" });
  }
  if (input.startDate != null && input.endDate != null) {
    if (input.startDate.toMillis() > input.endDate.toMillis()) {
      issues.push({ field: "startDate/endDate", message: "startDate cannot be after endDate" });
    }
  }
  if (input.frequencyCap != null) {
    if (!Number.isInteger(input.frequencyCap) || input.frequencyCap < 2 || input.frequencyCap > 60) {
      issues.push({
        field: "frequencyCap",
        message: "must be an integer between 2 and 60 when provided",
      });
    }
  }
  return issues;
}

async function requireRetailerOwnership(
  db: admin.firestore.Firestore,
  retailerId: string,
  userUid: string
): Promise<
  | { ok: true; retailerData: Record<string, unknown> }
  | { ok: false; status: number; error: string }
> {
  const retailerDoc = await db.collection("retailers").doc(retailerId).get();
  if (!retailerDoc.exists) {
    return { ok: false, status: 404, error: "Retailer not found" };
  }
  const retailerData = (retailerDoc.data() || {}) as Record<string, unknown>;
  const owners = Array.isArray(retailerData.ownerUserIds) ? retailerData.ownerUserIds : [];
  if (!owners.includes(userUid)) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  return { ok: true, retailerData };
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

function itemBelongsToRetailer(itemData: Record<string, unknown>, retailerId: string): boolean {
  const itemRetailer =
    normalizeRetailerSlug(itemData.retailer) || normalizeRetailerSlug(itemData.retailerId);
  return itemRetailer === normalizeRetailerSlug(retailerId);
}

function itemIncludedForRetailerCatalog(itemData: Record<string, unknown>): boolean {
  return itemData.retailerCatalogIncluded !== false;
}

async function fetchActiveItemDataByIds(
  db: admin.firestore.Firestore,
  ids: string[]
): Promise<Map<string, Record<string, unknown>>> {
  const uniqueIds = Array.from(new Set(ids.map((id) => id.trim()).filter((id) => id.length > 0)));
  if (uniqueIds.length === 0) return new Map();

  const [goldDocs, itemDocs] = await Promise.all([
    getDocsByIds(db, "goldItems", uniqueIds),
    getDocsByIds(db, "items", uniqueIds),
  ]);

  const output = new Map<string, Record<string, unknown>>();
  for (const doc of goldDocs) {
    const data = (doc.data() || {}) as Record<string, unknown>;
    if (!doc.exists || data.isActive !== true) continue;
    output.set(doc.id, data);
  }
  for (const doc of itemDocs) {
    const data = (doc.data() || {}) as Record<string, unknown>;
    if (!doc.exists || data.isActive !== true) continue;
    if (!output.has(doc.id)) output.set(doc.id, data);
  }
  return output;
}

async function computeRecommendedProductIdsForCampaign(
  db: admin.firestore.Firestore,
  retailerId: string,
  segmentId: string,
  limit = DEFAULT_RECOMMENDATION_LIMIT
): Promise<string[]> {
  const cappedLimit = Math.max(1, Math.min(limit, 60));
  const selectedIds: string[] = [];
  const seen = new Set<string>();

  const pushIfValid = (id: string) => {
    if (!id || seen.has(id)) return;
    seen.add(id);
    selectedIds.push(id);
  };

  let scoreProductIds: string[] = [];
  try {
    const scoresSnap = await db
      .collection("scores")
      .where("segmentId", "==", segmentId)
      .where("timeWindow", "==", "30d")
      .orderBy("score", "desc")
      .limit(Math.max(cappedLimit * 6, 60))
      .get();
    scoreProductIds = scoresSnap.docs
      .map((doc) => asTrimmedString(doc.data().productId))
      .filter((id): id is string => id != null);
  } catch (error) {
    console.warn("campaign_recommendations_scores_query_failed", {
      retailerId,
      segmentId,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  if (scoreProductIds.length > 0) {
    const itemDataById = await fetchActiveItemDataByIds(db, scoreProductIds);
    for (const productId of scoreProductIds) {
      if (selectedIds.length >= cappedLimit) break;
      const itemData = itemDataById.get(productId);
      if (!itemData) continue;
      if (!itemBelongsToRetailer(itemData, retailerId)) continue;
      if (!itemIncludedForRetailerCatalog(itemData)) continue;
      pushIfValid(productId);
    }
  }

  if (selectedIds.length < cappedLimit) {
    const fallbackGold = await db
      .collection("goldItems")
      .where("isActive", "==", true)
      .where("retailer", "==", retailerId)
      .limit(Math.max(cappedLimit * 4, 40))
      .get();
    fallbackGold.docs.forEach((doc) => {
      if (selectedIds.length >= cappedLimit) return;
      const data = (doc.data() || {}) as Record<string, unknown>;
      if (!itemIncludedForRetailerCatalog(data)) return;
      pushIfValid(doc.id);
    });
  }

  if (selectedIds.length < cappedLimit) {
    const fallbackItems = await db
      .collection("items")
      .where("isActive", "==", true)
      .where("retailer", "==", retailerId)
      .limit(Math.max(cappedLimit * 4, 40))
      .get();
    fallbackItems.docs.forEach((doc) => {
      if (selectedIds.length >= cappedLimit) return;
      const data = (doc.data() || {}) as Record<string, unknown>;
      if (!itemIncludedForRetailerCatalog(data)) return;
      pushIfValid(doc.id);
    });
  }

  return selectedIds.slice(0, cappedLimit);
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
  const budgetTotal = body.budgetTotal == null ? null : toPositiveNumber(body.budgetTotal);
  const budgetDaily = body.budgetDaily == null ? null : toPositiveNumber(body.budgetDaily);
  const startDate = parseDateToTimestamp(body.startDate);
  const endDate = parseDateToTimestamp(body.endDate);
  const frequencyCap = toNullableNumber(body.frequencyCap);

  if (!retailerId || !name || !segmentId) {
    res.status(400).json({ error: "retailerId, name, and segmentId are required" });
    return;
  }
  if (body.startDate != null && startDate == null) {
    res.status(400).json({ error: "startDate must be a valid date string or null" });
    return;
  }
  if (body.endDate != null && endDate == null) {
    res.status(400).json({ error: "endDate must be a valid date string or null" });
    return;
  }
  if (body.budgetTotal != null && budgetTotal == null) {
    res.status(400).json({ error: "budgetTotal must be a number > 0 or null" });
    return;
  }
  if (body.budgetDaily != null && budgetDaily == null) {
    res.status(400).json({ error: "budgetDaily must be a number > 0 or null" });
    return;
  }

  const validationIssues = validateBudgetAndSchedule({
    budgetTotal,
    budgetDaily,
    startDate,
    endDate,
    frequencyCap,
  });
  if (validationIssues.length > 0) {
    res.status(400).json({ error: "Invalid campaign budget/schedule", issues: validationIssues });
    return;
  }

  try {
    const retailerAccess = await requireRetailerOwnership(db, retailerId, user.uid);
    if (!retailerAccess.ok) {
      res.status(retailerAccess.status).json({ error: retailerAccess.error });
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

    let recommendedProductIds: string[] = [];
    if (mode === "auto") {
      recommendedProductIds = await computeRecommendedProductIdsForCampaign(
        db,
        retailerId,
        segmentId,
        DEFAULT_RECOMMENDATION_LIMIT
      );
    }

    const campaignData = {
      id: campaignRef.id,
      retailerId,
      name,
      segmentId,
      segmentSnapshot: segmentSnapshotResult.segmentSnapshot,
      productIds: mode === "selected" ? productIds : [],
      recommendedProductIds,
      productMode: mode,
      budgetTotal: budgetTotal ?? null,
      budgetDaily: budgetDaily ?? null,
      budgetSpent: 0,
      dailySpendByDate: {},
      dailyImpressionsByDate: {},
      startDate,
      endDate,
      status: "draft" as CampaignStatus,
      frequencyCap: frequencyCap ?? 12, // Max impressions per user
      impressions: 0,
      clicks: 0,
      featuredImpressions: 0,
      recommendedAt: mode === "auto" ? now : null,
      createdBy: user.uid,
      createdAt: now,
      updatedAt: now,
    };

    await campaignRef.set(campaignData);

    const nowIso = new Date().toISOString();
    res.status(201).json({
      ...campaignData,
      startDate: startDate?.toDate().toISOString() || null,
      endDate: endDate?.toDate().toISOString() || null,
      createdAt: nowIso,
      updatedAt: nowIso,
      recommendedAt: mode === "auto" ? nowIso : null,
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
    const campaigns = snapshot.docs.map((doc) =>
      toCampaignResponse(doc.id, (doc.data() || {}) as Record<string, unknown>)
    );

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

    res.json(toCampaignResponse(doc.id, data));
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
    const refreshRecommendations = body.refreshRecommendations === true;

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

    const nextSegmentId = (updates.segmentId as string | undefined) || asTrimmedString(data.segmentId);
    if (!nextSegmentId) {
      res.status(400).json({ error: "Campaign is missing segmentId" });
      return;
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

    const nextBudgetTotal = Object.prototype.hasOwnProperty.call(body, "budgetTotal")
      ? body.budgetTotal == null
        ? null
        : toPositiveNumber(body.budgetTotal)
      : toNullableNumber(data.budgetTotal);
    const nextBudgetDaily = Object.prototype.hasOwnProperty.call(body, "budgetDaily")
      ? body.budgetDaily == null
        ? null
        : toPositiveNumber(body.budgetDaily)
      : toNullableNumber(data.budgetDaily);
    if (Object.prototype.hasOwnProperty.call(body, "budgetTotal")) {
      if (body.budgetTotal != null && nextBudgetTotal == null) {
        res.status(400).json({ error: "budgetTotal must be a number > 0 or null" });
        return;
      }
      updates.budgetTotal = nextBudgetTotal;
    }
    if (Object.prototype.hasOwnProperty.call(body, "budgetDaily")) {
      if (body.budgetDaily != null && nextBudgetDaily == null) {
        res.status(400).json({ error: "budgetDaily must be a number > 0 or null" });
        return;
      }
      updates.budgetDaily = nextBudgetDaily;
    }

    const nextStartDate = Object.prototype.hasOwnProperty.call(body, "startDate")
      ? parseDateToTimestamp(body.startDate)
      : ((data.startDate as admin.firestore.Timestamp | undefined) || null);
    const nextEndDate = Object.prototype.hasOwnProperty.call(body, "endDate")
      ? parseDateToTimestamp(body.endDate)
      : ((data.endDate as admin.firestore.Timestamp | undefined) || null);

    if (Object.prototype.hasOwnProperty.call(body, "startDate")) {
      if (body.startDate != null && nextStartDate == null) {
        res.status(400).json({ error: "startDate must be a valid date string or null" });
        return;
      }
      updates.startDate = nextStartDate;
    }

    if (Object.prototype.hasOwnProperty.call(body, "endDate")) {
      if (body.endDate != null && nextEndDate == null) {
        res.status(400).json({ error: "endDate must be a valid date string or null" });
        return;
      }
      updates.endDate = nextEndDate;
    }

    const nextFrequencyCap = Object.prototype.hasOwnProperty.call(body, "frequencyCap")
      ? toNullableNumber(body.frequencyCap)
      : toNullableNumber(data.frequencyCap);
    if (Object.prototype.hasOwnProperty.call(body, "frequencyCap")) {
      if (body.frequencyCap != null && nextFrequencyCap == null) {
        res.status(400).json({ error: "frequencyCap must be a number or null" });
        return;
      }
      updates.frequencyCap = nextFrequencyCap;
    }

    const validationIssues = validateBudgetAndSchedule({
      budgetTotal: nextBudgetTotal,
      budgetDaily: nextBudgetDaily,
      startDate: nextStartDate,
      endDate: nextEndDate,
      frequencyCap: nextFrequencyCap,
    });
    if (validationIssues.length > 0) {
      res.status(400).json({ error: "Invalid campaign budget/schedule", issues: validationIssues });
      return;
    }

    if (nextProductMode === "auto") {
      const shouldRefreshAuto =
        refreshRecommendations ||
        Object.prototype.hasOwnProperty.call(body, "segmentId") ||
        Object.prototype.hasOwnProperty.call(body, "productMode") ||
        !Array.isArray(data.recommendedProductIds) ||
        (data.recommendedProductIds as unknown[]).length === 0;
      if (shouldRefreshAuto) {
        const recommendedProductIds = await computeRecommendedProductIdsForCampaign(
          db,
          asTrimmedString(data.retailerId) || "",
          nextSegmentId,
          DEFAULT_RECOMMENDATION_LIMIT
        );
        updates.recommendedProductIds = recommendedProductIds;
        updates.recommendedAt = admin.firestore.FieldValue.serverTimestamp();
      }
    } else if (
      Object.prototype.hasOwnProperty.call(body, "productMode") ||
      refreshRecommendations
    ) {
      updates.recommendedProductIds = [];
      updates.recommendedAt = null;
    }

    await campaignRef.update(updates);

    const updated = await campaignRef.get();
    const updatedData = (updated.data() || {}) as Record<string, unknown>;
    res.json(toCampaignResponse(updated.id, updatedData));
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

    const productMode = toProductMode(data.productMode);
    const productIds = Array.isArray(data.productIds) ? toStringArray(data.productIds) : [];
    const recommendedProductIds = Array.isArray(data.recommendedProductIds)
      ? toStringArray(data.recommendedProductIds)
      : [];

    if (productMode === "selected" && productIds.length === 0) {
      res.status(400).json({ error: "Cannot activate selected campaign without productIds" });
      return;
    }

    const validationIssues = validateBudgetAndSchedule({
      budgetTotal: toNullableNumber(data.budgetTotal),
      budgetDaily: toNullableNumber(data.budgetDaily),
      startDate: (data.startDate as admin.firestore.Timestamp | undefined) || null,
      endDate: (data.endDate as admin.firestore.Timestamp | undefined) || null,
      frequencyCap: toNullableNumber(data.frequencyCap),
    });
    if (validationIssues.length > 0) {
      res.status(400).json({
        error: "Cannot activate campaign with invalid budget/schedule",
        issues: validationIssues,
      });
      return;
    }

    const updates: Record<string, unknown> = {
      status: "active",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (productMode === "auto" && recommendedProductIds.length === 0 && productIds.length === 0) {
      const retailerId = asTrimmedString(data.retailerId);
      const segmentId = asTrimmedString(data.segmentId);
      if (retailerId && segmentId) {
        const generated = await computeRecommendedProductIdsForCampaign(
          db,
          retailerId,
          segmentId,
          DEFAULT_RECOMMENDATION_LIMIT
        );
        if (generated.length === 0) {
          res.status(400).json({
            error: "Cannot activate auto campaign without recommended products",
          });
          return;
        }
        updates.recommendedProductIds = generated;
        updates.recommendedAt = admin.firestore.FieldValue.serverTimestamp();
      } else {
        res.status(400).json({ error: "Cannot activate auto campaign without retailer/segment" });
        return;
      }
    }

    await campaignRef.update(updates);

    res.json({ success: true, message: "Campaign activated", campaignId });
  } catch (error) {
    console.error("Error activating campaign:", error);
    res.status(500).json({ error: "Failed to activate campaign" });
  }
}

/**
 * POST /api/retailer/campaigns/:id/recommend
 * Recompute recommended product set for an auto campaign (requires auth).
 */
export async function retailerCampaignsRecommendPost(
  req: Request,
  res: Response,
  campaignId: string
): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const campaignRef = db.collection("campaigns").doc(campaignId);
    const campaignDoc = await campaignRef.get();
    if (!campaignDoc.exists) {
      res.status(404).json({ error: "Campaign not found" });
      return;
    }

    const campaignData = (campaignDoc.data() || {}) as Record<string, unknown>;
    const retailerId = asTrimmedString(campaignData.retailerId);
    const segmentId = asTrimmedString(campaignData.segmentId);
    if (!retailerId || !segmentId) {
      res.status(400).json({ error: "Campaign missing retailerId or segmentId" });
      return;
    }

    const retailerAccess = await requireRetailerOwnership(db, retailerId, user.uid);
    if (!retailerAccess.ok) {
      res.status(retailerAccess.status).json({ error: retailerAccess.error });
      return;
    }

    const body = toBodyObject(req.body);
    const requestedLimit = toNullableNumber(body.limit);
    const recommendationLimit =
      requestedLimit != null ? Math.max(1, Math.min(Math.floor(requestedLimit), 60)) : DEFAULT_RECOMMENDATION_LIMIT;
    const apply = body.apply !== false;

    const recommendedProductIds = await computeRecommendedProductIdsForCampaign(
      db,
      retailerId,
      segmentId,
      recommendationLimit
    );

    if (apply) {
      await campaignRef.update({
        recommendedProductIds,
        recommendedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      campaignId,
      retailerId,
      segmentId,
      recommendationLimit,
      recommendedProductIds,
      applied: apply,
    });
  } catch (error) {
    console.error("Error computing campaign recommendations:", error);
    res.status(500).json({ error: "Failed to compute recommendations" });
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
