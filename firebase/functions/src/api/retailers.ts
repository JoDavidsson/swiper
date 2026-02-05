import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { requireUserAuth } from "../middleware/require_user_auth";

/**
 * POST /api/admin/retailers
 * Create a new retailer (admin only).
 */
export async function adminRetailersPost(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const { id, name, domain, logoUrl } = req.body;

  if (!id || !name || !domain) {
    res.status(400).json({ error: "id, name, and domain are required" });
    return;
  }

  // Validate id is a valid slug
  if (!/^[a-z0-9-]+$/.test(id)) {
    res.status(400).json({ error: "id must be a lowercase slug (letters, numbers, hyphens)" });
    return;
  }

  try {
    const retailerRef = db.collection("retailers").doc(id);
    const existing = await retailerRef.get();

    if (existing.exists) {
      res.status(409).json({ error: "Retailer with this id already exists" });
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    await retailerRef.set({
      id,
      name,
      domain,
      logoUrl: logoUrl || null,
      ownerUserIds: [],
      status: "pending", // pending until claimed
      createdAt: now,
      updatedAt: now,
    });

    res.status(201).json({
      id,
      name,
      domain,
      logoUrl: logoUrl || null,
      status: "pending",
    });
  } catch (error) {
    console.error("Error creating retailer:", error);
    res.status(500).json({ error: "Failed to create retailer" });
  }
}

/**
 * GET /api/admin/retailers
 * List all retailers (admin only).
 */
export async function adminRetailersGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);
  const status = req.query.status as string | undefined;

  try {
    let query = db.collection("retailers").orderBy("createdAt", "desc").limit(limit);

    if (status) {
      query = db.collection("retailers")
        .where("status", "==", status)
        .orderBy("createdAt", "desc")
        .limit(limit);
    }

    const snapshot = await query.get();
    const retailers = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
      updatedAt: doc.data().updatedAt?.toDate?.()?.toISOString() || null,
    }));

    res.json({ retailers });
  } catch (error) {
    console.error("Error listing retailers:", error);
    res.status(500).json({ error: "Failed to list retailers" });
  }
}

/**
 * GET /api/retailers/:id
 * Get retailer details (public for basic info).
 */
export async function retailersGetById(req: Request, res: Response, retailerId: string): Promise<void> {
  const db = admin.firestore();
  try {
    const doc = await db.collection("retailers").doc(retailerId).get();

    if (!doc.exists) {
      res.status(404).json({ error: "Retailer not found" });
      return;
    }

    const data = doc.data()!;
    res.json({
      id: doc.id,
      name: data.name,
      domain: data.domain,
      logoUrl: data.logoUrl,
      status: data.status,
      // Don't expose ownerUserIds publicly
    });
  } catch (error) {
    console.error("Error getting retailer:", error);
    res.status(500).json({ error: "Failed to get retailer" });
  }
}

/**
 * PATCH /api/admin/retailers/:id
 * Update retailer (admin only).
 */
export async function adminRetailersPatch(req: Request, res: Response, retailerId: string): Promise<void> {
  const db = admin.firestore();
  const { name, domain, logoUrl, status } = req.body;

  try {
    const retailerRef = db.collection("retailers").doc(retailerId);
    const doc = await retailerRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Retailer not found" });
      return;
    }

    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (name !== undefined) updates.name = name;
    if (domain !== undefined) updates.domain = domain;
    if (logoUrl !== undefined) updates.logoUrl = logoUrl;
    if (status !== undefined) {
      if (!["pending", "claimed", "active"].includes(status)) {
        res.status(400).json({ error: "Invalid status. Must be: pending, claimed, or active" });
        return;
      }
      updates.status = status;
    }

    await retailerRef.update(updates);

    const updated = await retailerRef.get();
    res.json({
      id: updated.id,
      ...updated.data(),
      createdAt: updated.data()?.createdAt?.toDate?.()?.toISOString() || null,
      updatedAt: updated.data()?.updatedAt?.toDate?.()?.toISOString() || null,
    });
  } catch (error) {
    console.error("Error updating retailer:", error);
    res.status(500).json({ error: "Failed to update retailer" });
  }
}

/**
 * POST /api/retailers/:id/claim
 * Claim ownership of a retailer (requires user auth).
 */
export async function retailersClaimPost(req: Request, res: Response, retailerId: string): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    const retailerRef = db.collection("retailers").doc(retailerId);
    const doc = await retailerRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Retailer not found" });
      return;
    }

    const data = doc.data()!;
    const ownerUserIds = data.ownerUserIds || [];

    // Check if user already owns this retailer
    if (ownerUserIds.includes(user.uid)) {
      res.json({
        success: true,
        message: "You already own this retailer",
        retailerId,
      });
      return;
    }

    // Check retailer status - only pending or claimed can be claimed
    if (data.status === "active") {
      // For active retailers, require verification (simplified for now)
      res.status(403).json({ 
        error: "This retailer is already active. Contact support to claim ownership." 
      });
      return;
    }

    // Add user to owners and update status
    await retailerRef.update({
      ownerUserIds: admin.firestore.FieldValue.arrayUnion(user.uid),
      status: "claimed",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      success: true,
      message: "Retailer claimed successfully",
      retailerId,
    });
  } catch (error) {
    console.error("Error claiming retailer:", error);
    res.status(500).json({ error: "Failed to claim retailer" });
  }
}

/**
 * GET /api/retailer/me
 * Get current user's retailer (requires auth).
 */
export async function retailerMeGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  try {
    // Find retailers where user is an owner
    const snapshot = await db.collection("retailers")
      .where("ownerUserIds", "array-contains", user.uid)
      .limit(10)
      .get();

    if (snapshot.empty) {
      res.status(404).json({ error: "No retailer found for this user" });
      return;
    }

    const retailers = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
      updatedAt: doc.data().updatedAt?.toDate?.()?.toISOString() || null,
    }));

    // Return first retailer (or all if user owns multiple)
    res.json({
      retailer: retailers[0],
      allRetailers: retailers.length > 1 ? retailers : undefined,
    });
  } catch (error) {
    console.error("Error getting retailer:", error);
    res.status(500).json({ error: "Failed to get retailer" });
  }
}
