import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

/**
 * GET /api/admin/curated-sofas
 * Get all curated onboarding sofas (admin).
 */
export async function adminCuratedSofasGet(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  try {
    const curatedSnap = await db
      .collection("curatedOnboardingSofas")
      .orderBy("order", "asc")
      .get();

    const sofas = await Promise.all(
      curatedSnap.docs.map(async (doc: admin.firestore.DocumentSnapshot) => {
        const data = doc.data();
        if (!data) return null;
        const itemId = doc.id;

        // Get the actual item details
        const itemDoc = await db.collection("items").doc(itemId).get();
        const itemData = itemDoc.data();

        const images = (itemData?.images as Array<{ url?: string }>) || [];
        const firstImage = images[0]?.url || "";

        return {
          id: itemId,
          order: data.order,
          imageUrl: firstImage,
          title: itemData?.title || "",
          styleTags: itemData?.styleTags || [],
          addedAt: data.addedAt?.toDate?.() || null,
        };
      })
    );

    // Filter out null entries
    const validSofas = sofas.filter((s): s is NonNullable<typeof s> => s !== null);

    res.json({ sofas: validSofas });
  } catch (e) {
    console.error("Error fetching curated sofas (admin):", e);
    res.status(500).json({ error: "Failed to fetch curated sofas" });
  }
}

/**
 * POST /api/admin/curated-sofas
 * Add an item to curated onboarding sofas (admin).
 * 
 * Body:
 * {
 *   "itemId": "item123",
 *   "order": 0
 * }
 */
export async function adminCuratedSofasPost(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  try {
    const { itemId, order } = req.body;

    if (!itemId) {
      res.status(400).json({ error: "itemId required" });
      return;
    }

    // Verify item exists
    const itemDoc = await db.collection("items").doc(itemId).get();
    if (!itemDoc.exists) {
      res.status(404).json({ error: "Item not found" });
      return;
    }

    // Add to curated collection
    await db.collection("curatedOnboardingSofas").doc(itemId).set({
      order: order ?? 0,
      addedAt: FieldValue.serverTimestamp(),
    });

    res.json({ ok: true, itemId });
  } catch (e) {
    console.error("Error adding curated sofa (admin):", e);
    res.status(500).json({ error: "Failed to add curated sofa" });
  }
}

/**
 * DELETE /api/admin/curated-sofas/:itemId
 * Remove an item from curated onboarding sofas (admin).
 */
export async function adminCuratedSofasDelete(
  req: Request,
  res: Response,
  itemId: string
): Promise<void> {
  const db = admin.firestore();
  try {
    if (!itemId) {
      res.status(400).json({ error: "itemId required" });
      return;
    }

    await db.collection("curatedOnboardingSofas").doc(itemId).delete();

    res.json({ ok: true });
  } catch (e) {
    console.error("Error deleting curated sofa (admin):", e);
    res.status(500).json({ error: "Failed to delete curated sofa" });
  }
}

/**
 * PUT /api/admin/curated-sofas/reorder
 * Reorder curated onboarding sofas (admin).
 * 
 * Body:
 * {
 *   "itemIds": ["item1", "item2", "item3", ...]
 * }
 */
export async function adminCuratedSofasReorder(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  try {
    const { itemIds } = req.body;

    if (!Array.isArray(itemIds)) {
      res.status(400).json({ error: "itemIds must be an array" });
      return;
    }

    const batch = db.batch();

    itemIds.forEach((itemId: string, index: number) => {
      const ref = db.collection("curatedOnboardingSofas").doc(itemId);
      batch.update(ref, { order: index });
    });

    await batch.commit();

    res.json({ ok: true });
  } catch (e) {
    console.error("Error reordering curated sofas (admin):", e);
    res.status(500).json({ error: "Failed to reorder curated sofas" });
  }
}
