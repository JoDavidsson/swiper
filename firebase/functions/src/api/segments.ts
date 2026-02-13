import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { requireUserAuth } from "../middleware/require_user_auth";
import { normalizeSegmentCriteriaInput } from "../targeting/segment_targeting";

function asTrimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function toBodyObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

/**
 * System-defined segment templates for v1 Sweden launch.
 */
export const SEGMENT_TEMPLATES = [
  {
    id: "budget-modern",
    name: "Budget-conscious modern",
    description: "Modern style at affordable prices",
    isTemplate: true,
    styleTags: ["modern", "minimalist"],
    budgetMin: 3000,
    budgetMax: 8000,
    sizeClasses: null,
    geoRegion: "sweden",
    retailerId: null,
  },
  {
    id: "premium-scandinavian",
    name: "Premium Scandinavian",
    description: "High-end Scandinavian design lovers",
    isTemplate: true,
    styleTags: ["scandinavian", "nordic"],
    budgetMin: 15000,
    budgetMax: null,
    sizeClasses: null,
    geoRegion: "sweden",
    retailerId: null,
  },
  {
    id: "compact-urban",
    name: "Compact urban",
    description: "Small space solutions for city living",
    isTemplate: true,
    styleTags: null,
    budgetMin: 5000,
    budgetMax: 12000,
    sizeClasses: ["small", "compact"],
    geoRegion: "sweden",
    retailerId: null,
  },
  {
    id: "family-friendly",
    name: "Family-friendly",
    description: "Durable, practical furniture for families",
    isTemplate: true,
    styleTags: ["modern", "classic"],
    budgetMin: 8000,
    budgetMax: 20000,
    sizeClasses: ["large", "medium"],
    geoRegion: "sweden",
    retailerId: null,
  },
  {
    id: "luxury-design",
    name: "Luxury design",
    description: "Premium designer furniture",
    isTemplate: true,
    styleTags: ["designer", "luxury"],
    budgetMin: 25000,
    budgetMax: null,
    sizeClasses: null,
    geoRegion: "sweden",
    retailerId: null,
  },
  {
    id: "all-sweden",
    name: "All Sweden",
    description: "All users in Sweden (no filtering)",
    isTemplate: true,
    styleTags: null,
    budgetMin: null,
    budgetMax: null,
    sizeClasses: null,
    geoRegion: "sweden",
    retailerId: null,
  },
];

/**
 * GET /api/segments/templates
 * List system segment templates (public).
 */
export async function segmentsTemplatesGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  try {
    // First check if templates exist in Firestore
    const snapshot = await db.collection("segments")
      .where("isTemplate", "==", true)
      .orderBy("name")
      .get();

    if (snapshot.empty) {
      // Return hardcoded templates if not seeded yet
      res.json({ 
        templates: SEGMENT_TEMPLATES,
        source: "hardcoded",
      });
      return;
    }

    const templates = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
    }));

    res.json({ 
      templates,
      source: "firestore",
    });
  } catch (error) {
    console.error("Error listing segment templates:", error);
    res.status(500).json({ error: "Failed to list segment templates" });
  }
}

/**
 * POST /api/segments
 * Create a custom segment (requires retailer auth).
 */
export async function segmentsPost(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const body = toBodyObject(req.body);
  const name = asTrimmedString(body.name);
  const description =
    Object.prototype.hasOwnProperty.call(body, "description")
      ? asTrimmedString(body.description)
      : null;
  const retailerId = asTrimmedString(body.retailerId);
  const baseTemplateId = asTrimmedString(body.baseTemplateId);
  const { normalized, issues } = normalizeSegmentCriteriaInput(body);

  if (!name) {
    res.status(400).json({ error: "name is required" });
    return;
  }
  if (issues.length > 0) {
    res.status(400).json({ error: "Invalid segment criteria", issues });
    return;
  }

  // Verify user owns the retailer if retailerId provided
  if (retailerId) {
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
  }

  try {
    const segmentRef = db.collection("segments").doc();
    const now = FieldValue.serverTimestamp();

    const segmentData = {
      id: segmentRef.id,
      name,
      description: description ?? null,
      isTemplate: false,
      styleTags: normalized.styleTags ?? null,
      budgetMin: normalized.budgetMin ?? null,
      budgetMax: normalized.budgetMax ?? null,
      sizeClasses: normalized.sizeClasses ?? null,
      geoRegion: normalized.geoRegion ?? "sweden",
      geoCity: normalized.geoCity ?? null,
      geoPostcodes: normalized.geoPostcodes ?? null,
      retailerId: retailerId ?? null,
      baseTemplateId: baseTemplateId ?? null,
      createdBy: user.uid,
      createdAt: now,
      updatedAt: now,
    };

    await segmentRef.set(segmentData);

    res.status(201).json({
      ...segmentData,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error("Error creating segment:", error);
    res.status(500).json({ error: "Failed to create segment" });
  }
}

/**
 * GET /api/segments
 * List segments for a retailer (requires auth).
 */
export async function segmentsGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const retailerId = req.query.retailerId as string | undefined;
  const includeTemplates = req.query.includeTemplates !== "false";

  try {
    const segments: Array<Record<string, unknown>> = [];

    // Get templates if requested
    if (includeTemplates) {
      const templatesSnap = await db.collection("segments")
        .where("isTemplate", "==", true)
        .get();

      if (templatesSnap.empty) {
        SEGMENT_TEMPLATES.forEach((template) => {
          segments.push({
            ...template,
            createdAt: null,
          });
        });
      } else {
        templatesSnap.docs.forEach(doc => {
          segments.push({
            id: doc.id,
            ...doc.data(),
            createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
          });
        });
      }
    }

    // Get retailer's custom segments if retailerId provided
    if (retailerId) {
      // Verify user owns the retailer
      const retailerDoc = await db.collection("retailers").doc(retailerId).get();
      if (retailerDoc.exists) {
        const retailerData = retailerDoc.data()!;
        if (retailerData.ownerUserIds?.includes(user.uid)) {
          const customSnap = await db.collection("segments")
            .where("retailerId", "==", retailerId)
            .get();
          
          customSnap.docs.forEach(doc => {
            segments.push({
              id: doc.id,
              ...doc.data(),
              createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
            });
          });
        }
      }
    }

    // Also get segments created by this user
    const userSegmentsSnap = await db.collection("segments")
      .where("createdBy", "==", user.uid)
      .where("isTemplate", "==", false)
      .get();
    
    userSegmentsSnap.docs.forEach(doc => {
      // Avoid duplicates
      if (!segments.some(s => s.id === doc.id)) {
        segments.push({
          id: doc.id,
          ...doc.data(),
          createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
        });
      }
    });

    res.json({ segments });
  } catch (error) {
    console.error("Error listing segments:", error);
    res.status(500).json({ error: "Failed to list segments" });
  }
}

/**
 * GET /api/segments/:id
 * Get segment by ID (public for templates, auth for custom).
 */
export async function segmentsGetById(req: Request, res: Response, segmentId: string): Promise<void> {
  const db = admin.firestore();
  try {
    const doc = await db.collection("segments").doc(segmentId).get();

    if (!doc.exists) {
      const fallbackTemplate = SEGMENT_TEMPLATES.find((template) => template.id === segmentId);
      if (!fallbackTemplate) {
        res.status(404).json({ error: "Segment not found" });
        return;
      }
      res.json({
        ...fallbackTemplate,
        createdAt: null,
      });
      return;
    }

    const data = doc.data()!;

    // Templates are public
    if (data.isTemplate) {
      res.json({
        id: doc.id,
        ...data,
        createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
      });
      return;
    }

    // Custom segments require auth
    const user = await requireUserAuth(req);
    if (!user) {
      res.status(401).json({ error: "Authentication required for custom segments" });
      return;
    }

    // Check if user owns this segment or its retailer
    const isOwner = data.createdBy === user.uid;
    let isRetailerOwner = false;
    
    if (data.retailerId) {
      const retailerDoc = await db.collection("retailers").doc(data.retailerId).get();
      if (retailerDoc.exists) {
        const retailerData = retailerDoc.data()!;
        isRetailerOwner = retailerData.ownerUserIds?.includes(user.uid);
      }
    }

    if (!isOwner && !isRetailerOwner) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    res.json({
      id: doc.id,
      ...data,
      createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    });
  } catch (error) {
    console.error("Error getting segment:", error);
    res.status(500).json({ error: "Failed to get segment" });
  }
}

/**
 * PATCH /api/segments/:id
 * Update a custom segment (requires auth).
 */
export async function segmentsPatch(req: Request, res: Response, segmentId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const segmentRef = db.collection("segments").doc(segmentId);
    const doc = await segmentRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Segment not found" });
      return;
    }

    const data = doc.data()!;

    // Cannot modify templates
    if (data.isTemplate) {
      res.status(403).json({ error: "Cannot modify system templates" });
      return;
    }

    // Check ownership
    const isOwner = data.createdBy === user.uid;
    let isRetailerOwner = false;
    
    if (data.retailerId) {
      const retailerDoc = await db.collection("retailers").doc(data.retailerId).get();
      if (retailerDoc.exists) {
        const retailerData = retailerDoc.data()!;
        isRetailerOwner = retailerData.ownerUserIds?.includes(user.uid);
      }
    }

    if (!isOwner && !isRetailerOwner) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    const body = toBodyObject(req.body);
    const { normalized, issues } = normalizeSegmentCriteriaInput(body);

    const updates: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (Object.prototype.hasOwnProperty.call(body, "name")) {
      const nextName = asTrimmedString(body.name);
      if (!nextName) {
        res.status(400).json({ error: "name cannot be empty" });
        return;
      }
      updates.name = nextName;
    }

    if (Object.prototype.hasOwnProperty.call(body, "description")) {
      if (body.description == null) {
        updates.description = null;
      } else {
        const nextDescription = asTrimmedString(body.description);
        if (nextDescription == null) {
          res.status(400).json({ error: "description must be a non-empty string or null" });
          return;
        }
        updates.description = nextDescription;
      }
    }

    const currentBudgetMin =
      typeof data.budgetMin === "number" && Number.isFinite(data.budgetMin) ? data.budgetMin : null;
    const currentBudgetMax =
      typeof data.budgetMax === "number" && Number.isFinite(data.budgetMax) ? data.budgetMax : null;
    const nextBudgetMin =
      Object.prototype.hasOwnProperty.call(normalized, "budgetMin") ? normalized.budgetMin ?? null : currentBudgetMin;
    const nextBudgetMax =
      Object.prototype.hasOwnProperty.call(normalized, "budgetMax") ? normalized.budgetMax ?? null : currentBudgetMax;
    if (nextBudgetMin != null && nextBudgetMax != null && nextBudgetMin > nextBudgetMax) {
      issues.push({
        field: "budgetMin/budgetMax",
        message: "budgetMin cannot be greater than budgetMax",
      });
    }

    if (issues.length > 0) {
      res.status(400).json({ error: "Invalid segment criteria", issues });
      return;
    }

    if (Object.prototype.hasOwnProperty.call(normalized, "styleTags")) {
      updates.styleTags = normalized.styleTags ?? null;
    }
    if (Object.prototype.hasOwnProperty.call(normalized, "budgetMin")) {
      updates.budgetMin = normalized.budgetMin ?? null;
    }
    if (Object.prototype.hasOwnProperty.call(normalized, "budgetMax")) {
      updates.budgetMax = normalized.budgetMax ?? null;
    }
    if (Object.prototype.hasOwnProperty.call(normalized, "sizeClasses")) {
      updates.sizeClasses = normalized.sizeClasses ?? null;
    }
    if (Object.prototype.hasOwnProperty.call(normalized, "geoRegion")) {
      updates.geoRegion = normalized.geoRegion ?? null;
    }
    if (Object.prototype.hasOwnProperty.call(normalized, "geoCity")) {
      updates.geoCity = normalized.geoCity ?? null;
    }
    if (Object.prototype.hasOwnProperty.call(normalized, "geoPostcodes")) {
      updates.geoPostcodes = normalized.geoPostcodes ?? null;
    }

    await segmentRef.update(updates);

    const updated = await segmentRef.get();
    res.json({
      id: updated.id,
      ...updated.data(),
      createdAt: updated.data()?.createdAt?.toDate?.()?.toISOString() || null,
      updatedAt: updated.data()?.updatedAt?.toDate?.()?.toISOString() || null,
    });
  } catch (error) {
    console.error("Error updating segment:", error);
    res.status(500).json({ error: "Failed to update segment" });
  }
}

/**
 * DELETE /api/segments/:id
 * Delete a custom segment (requires auth).
 */
export async function segmentsDelete(req: Request, res: Response, segmentId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const segmentRef = db.collection("segments").doc(segmentId);
    const doc = await segmentRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Segment not found" });
      return;
    }

    const data = doc.data()!;

    // Cannot delete templates
    if (data.isTemplate) {
      res.status(403).json({ error: "Cannot delete system templates" });
      return;
    }

    // Check ownership
    if (data.createdBy !== user.uid) {
      res.status(403).json({ error: "Access denied" });
      return;
    }

    // Check if segment is used by any campaigns
    const campaignsSnap = await db.collection("campaigns")
      .where("segmentId", "==", segmentId)
      .limit(1)
      .get();

    if (!campaignsSnap.empty) {
      res.status(400).json({ error: "Cannot delete segment that is used by campaigns" });
      return;
    }

    await segmentRef.delete();
    res.json({ success: true, message: "Segment deleted" });
  } catch (error) {
    console.error("Error deleting segment:", error);
    res.status(500).json({ error: "Failed to delete segment" });
  }
}
