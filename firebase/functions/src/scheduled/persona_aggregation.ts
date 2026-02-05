import * as functions from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

/**
 * Persona Aggregation Pipeline
 * 
 * This scheduled function runs periodically to compute persona signals
 * for collaborative filtering. It:
 * 
 * 1. Groups users by their onboarding pick hash (similar picks = similar preferences)
 * 2. For each pick hash group, aggregates liked item IDs from all users in the group
 * 3. Computes item scores based on how many times an item was liked within each persona group
 * 4. Stores the results in personaSignals collection for the ranker to use
 * 
 * The pick hash is created from the sorted list of picked item IDs during visual onboarding.
 * Users who pick the exact same 3 sofas will have the same pick hash.
 */

interface PickGroupStats {
  sessionIds: string[];
  likedItemIds: Map<string, number>; // itemId -> like count
}

/**
 * Compute persona signals from onboarding picks and likes.
 * Runs every 6 hours.
 */
export const computePersonaSignals = functions.onSchedule(
  {
    schedule: "0 */6 * * *", // Every 6 hours
    timeZone: "UTC",
    retryCount: 2,
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = admin.firestore();
    console.log("Starting persona aggregation pipeline...");

    try {
      // Step 1: Get all onboarding picks with pick hashes
      const picksSnap = await db.collection("onboardingPicks").get();

      if (picksSnap.empty) {
        console.log("No onboarding picks found. Skipping aggregation.");
        return;
      }

      // Group sessions by pick hash
      const pickGroups = new Map<string, PickGroupStats>();

      for (const doc of picksSnap.docs) {
        const data = doc.data();
        const pickHash = data.pickHash as string | undefined;
        const sessionId = doc.id;

        if (!pickHash) continue;

        if (!pickGroups.has(pickHash)) {
          pickGroups.set(pickHash, {
            sessionIds: [],
            likedItemIds: new Map(),
          });
        }

        pickGroups.get(pickHash)!.sessionIds.push(sessionId);
      }

      console.log(`Found ${pickGroups.size} unique pick hash groups`);

      // Step 2: For each group, aggregate liked items from all sessions
      for (const [_pickHash, group] of pickGroups.entries()) {
        // Skip groups with only one user (no collaborative signal)
        if (group.sessionIds.length < 2) continue;

        // Get likes for all sessions in this group
        for (const sessionId of group.sessionIds) {
          const likesSnap = await db
            .collection("likes")
            .where("sessionId", "==", sessionId)
            .get();

          for (const likeDoc of likesSnap.docs) {
            const itemId = likeDoc.data().itemId as string;
            if (!itemId) continue;

            const currentCount = group.likedItemIds.get(itemId) || 0;
            group.likedItemIds.set(itemId, currentCount + 1);
          }
        }
      }

      // Step 3: Compute and store persona signals
      const batch = db.batch();
      let signalCount = 0;

      for (const [pickHash, group] of pickGroups.entries()) {
        // Skip if no likes or only one user
        if (group.likedItemIds.size === 0 || group.sessionIds.length < 2) continue;

        // Sort items by like count descending
        const sortedItems = Array.from(group.likedItemIds.entries())
          .sort((a, b) => b[1] - a[1])
          .slice(0, 50); // Keep top 50 items per persona

        // Compute scores: normalize by number of users in group
        const totalUsers = group.sessionIds.length;
        const itemScores: Record<string, number> = {};

        for (const [itemId, likeCount] of sortedItems) {
          // Score = percentage of users in this persona who liked the item
          itemScores[itemId] = likeCount / totalUsers;
        }

        // Store the persona signal
        const signalRef = db.collection("personaSignals").doc(pickHash);
        batch.set(signalRef, {
          pickHash,
          userCount: totalUsers,
          itemScores,
          topItems: sortedItems.slice(0, 20).map(([id]) => id),
          updatedAt: FieldValue.serverTimestamp(),
        });

        signalCount++;
      }

      if (signalCount > 0) {
        await batch.commit();
        console.log(`Updated ${signalCount} persona signals`);
      } else {
        console.log("No persona signals to update (insufficient collaborative data)");
      }

      console.log("Persona aggregation pipeline completed successfully");
    } catch (error) {
      console.error("Persona aggregation pipeline failed:", error);
      throw error;
    }
  }
);

/**
 * Get persona signals for a given pick hash.
 * Used by the ranker to boost items liked by similar users.
 */
export async function getPersonaSignals(
  pickHash: string
): Promise<Record<string, number> | null> {
  const db = admin.firestore();
  try {
    const signalDoc = await db.collection("personaSignals").doc(pickHash).get();

    if (!signalDoc.exists) {
      return null;
    }

    const data = signalDoc.data();
    return (data?.itemScores as Record<string, number>) || null;
  } catch {
    return null;
  }
}
