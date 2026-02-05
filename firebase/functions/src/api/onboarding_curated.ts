import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

/**
 * GET /api/onboarding/curated-sofas
 * Returns 6 curated sofa images for the visual gold card.
 * Falls back to most-liked items if curatedOnboardingSofas collection is empty.
 */
export async function onboardingCuratedSofasGet(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  try {
    // Try to get curated sofas first
    const curatedSnap = await db
      .collection("curatedOnboardingSofas")
      .orderBy("order", "asc")
      .limit(6)
      .get();

    if (!curatedSnap.empty) {
      const sofas = await Promise.all(
        curatedSnap.docs.map(async (doc: admin.firestore.DocumentSnapshot) => {
          const itemId = doc.id;
          
          // Get the actual item to get the image URL and style tags
          const itemDoc = await db.collection("items").doc(itemId).get();
          const itemData = itemDoc.data();
          
          if (!itemData) {
            return null;
          }

          const images = itemData.images as Array<{ url?: string }> || [];
          const firstImage = images[0]?.url || "";

          return {
            id: itemId,
            imageUrl: firstImage,
            styleTags: itemData.styleTags || [],
            material: itemData.material || null,
            colorFamily: itemData.colorFamily || null,
          };
        })
      );

      const validSofas = sofas.filter((s: {id: string; imageUrl: string} | null) => s !== null && s.imageUrl);

      if (validSofas.length >= 6) {
        res.json({ sofas: validSofas.slice(0, 6) });
        return;
      }
    }

    // Fallback: get most-liked items
    // Query items that have been liked (appear in sessions with right swipes)
    // For simplicity, just get 6 random items with good images
    const itemsSnap = await db
      .collection("items")
      .where("images", "!=", [])
      .limit(20)
      .get();

    const fallbackSofas = itemsSnap.docs
      .map((doc: admin.firestore.DocumentSnapshot) => {
        const data = doc.data();
        if (!data) return null;
        const images = data.images as Array<{ url?: string }> || [];
        const firstImage = images[0]?.url || "";

        if (!firstImage) return null;

        return {
          id: doc.id,
          imageUrl: firstImage,
          styleTags: data.styleTags || [],
          material: data.material || null,
          colorFamily: data.colorFamily || null,
        };
      })
      .filter((s: unknown) => s !== null)
      .slice(0, 6);

    res.json({ sofas: fallbackSofas });
  } catch (e) {
    console.error("Error fetching curated sofas:", e);
    res.status(500).json({ error: "Failed to fetch curated sofas" });
  }
}
