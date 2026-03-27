import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

/**
 * GovernanceConfig stored in Firestore `governance` collection.
 * The document ID is always 'default' for the global config.
 */
export interface GovernanceConfig {
  id: "default";
  frequencyCap: number;          // max 1 in N cards (default: 12)
  relevanceThreshold: number;   // min match score 0-100 (default: 30)
  pacingStrategy: "even" | "frontload" | "backload";  // how to spread budget
  brandSafetyEnabled: boolean;
  featuredLabelText: string;    // e.g. "Featured" or "Sponsored"
  updatedAt: admin.firestore.Timestamp | null;
  updatedBy: string;
}

const DEFAULT_GOVERNANCE: Omit<GovernanceConfig, "id" | "updatedAt" | "updatedBy"> = {
  frequencyCap: 12,
  relevanceThreshold: 30,
  pacingStrategy: "even",
  brandSafetyEnabled: true,
  featuredLabelText: "Featured",
};

function toSerializable(doc: admin.firestore.DocumentSnapshot): GovernanceConfig {
  const data = doc.data()!;
  return {
    id: doc.id as "default",
    frequencyCap: data.frequencyCap,
    relevanceThreshold: data.relevanceThreshold,
    pacingStrategy: data.pacingStrategy,
    brandSafetyEnabled: data.brandSafetyEnabled,
    featuredLabelText: data.featuredLabelText,
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() ?? null,
    updatedBy: data.updatedBy,
  };
}

/**
 * GET /api/admin/governance
 * Get the current global governance config.
 */
export async function adminGovernanceGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  try {
    const doc = await db.collection("governance").doc("default").get();

    if (!doc.exists) {
      // Return defaults if no config exists yet
      res.status(200).json({
        id: "default",
        ...DEFAULT_GOVERNANCE,
        updatedAt: null,
        updatedBy: "",
      });
      return;
    }

    res.status(200).json(toSerializable(doc));
  } catch (error) {
    console.error("Error fetching governance config:", error);
    res.status(500).json({ error: "Failed to fetch governance config" });
  }
}

/**
 * PATCH /api/admin/governance
 * Partially update the global governance config.
 */
export async function adminGovernancePatch(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const body = req.body as Partial<Omit<GovernanceConfig, "id" | "updatedAt" | "updatedBy">>;

  // Validate pacingStrategy if provided
  if (body.pacingStrategy !== undefined) {
    if (!["even", "frontload", "backload"].includes(body.pacingStrategy)) {
      res.status(400).json({
        error: "pacingStrategy must be one of: even, frontload, backload",
      });
      return;
    }
  }

  // Validate frequencyCap
  if (body.frequencyCap !== undefined) {
    if (!Number.isInteger(body.frequencyCap) || body.frequencyCap < 1) {
      res.status(400).json({ error: "frequencyCap must be a positive integer" });
      return;
    }
  }

  // Validate relevanceThreshold
  if (body.relevanceThreshold !== undefined) {
    if (
      typeof body.relevanceThreshold !== "number" ||
      body.relevanceThreshold < 0 ||
      body.relevanceThreshold > 100
    ) {
      res.status(400).json({ error: "relevanceThreshold must be a number between 0 and 100" });
      return;
    }
  }

  try {
    const ref = db.collection("governance").doc("default");
    const existing = await ref.get();

    const updates: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
      // Carry forward updatedBy from auth header, default to "unknown"
      updatedBy: (req.headers["x-admin-email"] as string) || "unknown",
    };

    if (body.frequencyCap !== undefined) updates.frequencyCap = body.frequencyCap;
    if (body.relevanceThreshold !== undefined) updates.relevanceThreshold = body.relevanceThreshold;
    if (body.pacingStrategy !== undefined) updates.pacingStrategy = body.pacingStrategy;
    if (body.brandSafetyEnabled !== undefined) updates.brandSafetyEnabled = body.brandSafetyEnabled;
    if (body.featuredLabelText !== undefined) updates.featuredLabelText = body.featuredLabelText;

    if (!existing.exists) {
      // Create with defaults merged
      await ref.set({
        ...DEFAULT_GOVERNANCE,
        ...updates,
      });
    } else {
      await ref.update(updates);
    }

    const updated = await ref.get();
    res.status(200).json(toSerializable(updated));
  } catch (error) {
    console.error("Error updating governance config:", error);
    res.status(500).json({ error: "Failed to update governance config" });
  }
}

/**
 * POST /api/admin/governance/reset
 * Reset governance config to defaults.
 */
export async function adminGovernanceReset(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  try {
    const ref = db.collection("governance").doc("default");
    const updatedBy = (req.headers["x-admin-email"] as string) || "unknown";

    await ref.set({
      ...DEFAULT_GOVERNANCE,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy,
    });

    const updated = await ref.get();
    res.status(200).json(toSerializable(updated));
  } catch (error) {
    console.error("Error resetting governance config:", error);
    res.status(500).json({ error: "Failed to reset governance config" });
  }
}
