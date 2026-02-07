import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

/**
 * POST /api/onboarding/picks
 * Store user's onboarding picks (visual card selections + optional budget).
 * 
 * Body:
 * {
 *   "sessionId": "abc123",
 *   "pickedItemIds": ["item1", "item2", "item3"],
 *   "budgetMin": 5000,  // optional
 *   "budgetMax": 15000  // optional
 * }
 */
export async function onboardingPicksPost(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  try {
    const { sessionId, pickedItemIds, budgetMin, budgetMax } = req.body;

    if (!sessionId) {
      res.status(400).json({ error: "sessionId required" });
      return;
    }

    if (!Array.isArray(pickedItemIds) || pickedItemIds.length === 0) {
      res.status(400).json({ error: "pickedItemIds required and must be an array" });
      return;
    }

    // Ensure anon session exists (session API stores in anonSessions)
    const sessionRef = db.collection("anonSessions").doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      await sessionRef.set(
        {
          createdAt: FieldValue.serverTimestamp(),
          lastSeenAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    // Build the picks document
    const picksData: Record<string, unknown> = {
      pickedItemIds,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (budgetMin !== undefined) {
      picksData.budgetMin = Number(budgetMin);
    }
    if (budgetMax !== undefined) {
      picksData.budgetMax = Number(budgetMax);
    }

    // Fetch picked items to extract attributes for cold-start fallback
    const pickedItemsSnap = await Promise.all(
      pickedItemIds.slice(0, 3).map((id: string) =>
        db.collection("items").doc(id).get()
      )
    );

    const extractedAttributes: {
      styleTags: string[];
      materials: string[];
      colorFamilies: string[];
    } = {
      styleTags: [],
      materials: [],
      colorFamilies: [],
    };

    for (const doc of pickedItemsSnap) {
      if (!doc.exists) continue;
      const data = doc.data();
      if (!data) continue;

      if (Array.isArray(data.styleTags)) {
        extractedAttributes.styleTags.push(...data.styleTags);
      }
      if (data.material) {
        extractedAttributes.materials.push(data.material);
      }
      if (data.colorFamily) {
        extractedAttributes.colorFamilies.push(data.colorFamily);
      }
    }

    // Deduplicate
    extractedAttributes.styleTags = [...new Set(extractedAttributes.styleTags)];
    extractedAttributes.materials = [...new Set(extractedAttributes.materials)];
    extractedAttributes.colorFamilies = [...new Set(extractedAttributes.colorFamilies)];

    picksData.extractedAttributes = extractedAttributes;

    // Compute a hash of picked item IDs for collaborative filtering lookup
    const pickHash = pickedItemIds.sort().join("-");
    picksData.pickHash = pickHash;

    // Store in onboardingPicks collection
    await db.collection("onboardingPicks").doc(sessionId).set(picksData, { merge: true });

    // Also update anon session with a reference to picks
    await sessionRef.set(
      {
        hasOnboardingPicks: true,
        onboardingPickHash: pickHash,
        updatedAt: FieldValue.serverTimestamp(),
        lastSeenAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    res.json({ ok: true, pickHash });
  } catch (e) {
    console.error("Error storing onboarding picks:", e);
    res.status(500).json({ error: "Failed to store onboarding picks" });
  }
}

/**
 * GET /api/onboarding/picks
 * Get user's onboarding picks.
 * 
 * Query params:
 * - sessionId: string
 */
export async function onboardingPicksGet(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  try {
    const sessionId = req.query.sessionId as string;

    if (!sessionId) {
      res.status(400).json({ error: "sessionId required" });
      return;
    }

    const picksDoc = await db.collection("onboardingPicks").doc(sessionId).get();
    
    if (!picksDoc.exists) {
      res.json({ picks: null });
      return;
    }

    const data = picksDoc.data();
    res.json({
      picks: {
        pickedItemIds: data?.pickedItemIds || [],
        budgetMin: data?.budgetMin ?? null,
        budgetMax: data?.budgetMax ?? null,
        pickHash: data?.pickHash || null,
        extractedAttributes: data?.extractedAttributes || null,
      },
    });
  } catch (e) {
    console.error("Error fetching onboarding picks:", e);
    res.status(500).json({ error: "Failed to fetch onboarding picks" });
  }
}
