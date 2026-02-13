import * as functions from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

/**
 * Persona Aggregation Pipeline
 *
 * This scheduled function computes collaborative persona signals from onboarding
 * pick-hash cohorts and behavior events. It combines:
 * - likes (strongest signal),
 * - right swipes,
 * - outbound clicks,
 * with recency decay so stale behavior has less influence.
 */

const MIN_GROUP_USERS = 2;
const MAX_ITEMS_PER_PERSONA = 50;
const MAX_TOP_ITEMS = 20;
const SESSION_CHUNK_SIZE = 10; // Firestore "in" query limit

const LIKE_WEIGHT = 1.0;
const RIGHT_SWIPE_WEIGHT = 0.35;
const OUTBOUND_CLICK_WEIGHT = 0.55;
const SIGNAL_HALF_LIFE_DAYS = 45;

interface ItemSignalAccumulator {
  score: number;
  likeCount: number;
  swipeRightCount: number;
  outboundClickCount: number;
  sessions: Set<string>;
}

interface PickGroupStats {
  sessionIds: string[];
  itemSignals: Map<string, ItemSignalAccumulator>;
}

function asString(value: unknown): string {
  if (typeof value !== "string") return "";
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : "";
}

function toMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function recencyMultiplier(createdAtMs: number | null, nowMs: number): number {
  if (createdAtMs == null) return 1;
  const ageMs = Math.max(0, nowMs - createdAtMs);
  const ageDays = ageMs / (24 * 60 * 60 * 1000);
  const decay = Math.exp((-Math.log(2) * ageDays) / SIGNAL_HALF_LIFE_DAYS);
  return Math.max(0.25, Math.min(1, decay));
}

function round(value: number, decimals = 4): number {
  const scale = Math.pow(10, decimals);
  return Math.round(value * scale) / scale;
}

function chunk<T>(values: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    out.push(values.slice(index, index + size));
  }
  return out;
}

function getOrCreateItemAccumulator(
  group: PickGroupStats,
  itemId: string
): ItemSignalAccumulator {
  const existing = group.itemSignals.get(itemId);
  if (existing) return existing;
  const created: ItemSignalAccumulator = {
    score: 0,
    likeCount: 0,
    swipeRightCount: 0,
    outboundClickCount: 0,
    sessions: new Set<string>(),
  };
  group.itemSignals.set(itemId, created);
  return created;
}

function applySignal(params: {
  group: PickGroupStats;
  itemId: string;
  sessionId: string;
  baseWeight: number;
  createdAtMs: number | null;
  nowMs: number;
  signalType: "like" | "swipeRight" | "outboundClick";
}): void {
  const item = getOrCreateItemAccumulator(params.group, params.itemId);
  const weighted = params.baseWeight * recencyMultiplier(params.createdAtMs, params.nowMs);
  item.score += weighted;
  item.sessions.add(params.sessionId);
  if (params.signalType === "like") item.likeCount += 1;
  if (params.signalType === "swipeRight") item.swipeRightCount += 1;
  if (params.signalType === "outboundClick") item.outboundClickCount += 1;
}

/**
 * Compute persona signals from onboarding picks and interactions.
 * Runs every 6 hours.
 */
export const computePersonaSignals = functions.onSchedule(
  {
    schedule: "0 */6 * * *",
    timeZone: "UTC",
    retryCount: 2,
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = admin.firestore();
    const nowMs = Date.now();
    console.log("Starting persona aggregation pipeline...");

    try {
      const picksSnap = await db.collection("onboardingPicks").get();
      if (picksSnap.empty) {
        console.log("No onboarding picks found. Skipping aggregation.");
        return;
      }

      const pickGroups = new Map<string, PickGroupStats>();
      for (const doc of picksSnap.docs) {
        const data = doc.data();
        const pickHash = asString(data.pickHash);
        const sessionId = doc.id;
        if (!pickHash) continue;

        if (!pickGroups.has(pickHash)) {
          pickGroups.set(pickHash, {
            sessionIds: [],
            itemSignals: new Map(),
          });
        }
        pickGroups.get(pickHash)!.sessionIds.push(sessionId);
      }

      console.log(`Found ${pickGroups.size} unique pick hash groups`);

      for (const [_pickHash, group] of pickGroups.entries()) {
        if (group.sessionIds.length < MIN_GROUP_USERS) continue;

        const seenSwipeRights = new Set<string>();
        const seenOutboundClicks = new Set<string>();
        const sessionChunks = chunk(group.sessionIds, SESSION_CHUNK_SIZE);

        for (const sessionChunk of sessionChunks) {
          const [likesSnap, swipesSnap, eventsSnap] = await Promise.all([
            db.collection("likes").where("sessionId", "in", sessionChunk).get(),
            db.collection("swipes").where("sessionId", "in", sessionChunk).get(),
            db.collection("events").where("sessionId", "in", sessionChunk).get(),
          ]);

          for (const likeDoc of likesSnap.docs) {
            const data = likeDoc.data();
            const itemId = asString(data.itemId);
            const sessionId = asString(data.sessionId);
            if (!itemId || !sessionId) continue;
            applySignal({
              group,
              itemId,
              sessionId,
              baseWeight: LIKE_WEIGHT,
              createdAtMs: toMillis(data.createdAt),
              nowMs,
              signalType: "like",
            });
          }

          for (const swipeDoc of swipesSnap.docs) {
            const data = swipeDoc.data();
            const direction = asString(data.direction);
            if (direction !== "right") continue;
            const itemId = asString(data.itemId);
            const sessionId = asString(data.sessionId);
            if (!itemId || !sessionId) continue;
            const dedupeKey = `${sessionId}::${itemId}`;
            if (seenSwipeRights.has(dedupeKey)) continue;
            seenSwipeRights.add(dedupeKey);
            applySignal({
              group,
              itemId,
              sessionId,
              baseWeight: RIGHT_SWIPE_WEIGHT,
              createdAtMs: toMillis(data.createdAt),
              nowMs,
              signalType: "swipeRight",
            });
          }

          for (const eventDoc of eventsSnap.docs) {
            const data = eventDoc.data();
            if (asString(data.eventType) !== "outbound_click") continue;
            const itemId = asString(data.itemId);
            const sessionId = asString(data.sessionId);
            if (!itemId || !sessionId) continue;
            const dedupeKey = `${sessionId}::${itemId}`;
            if (seenOutboundClicks.has(dedupeKey)) continue;
            seenOutboundClicks.add(dedupeKey);
            applySignal({
              group,
              itemId,
              sessionId,
              baseWeight: OUTBOUND_CLICK_WEIGHT,
              createdAtMs: toMillis(data.createdAt),
              nowMs,
              signalType: "outboundClick",
            });
          }
        }
      }

      let batch = db.batch();
      let pendingWrites = 0;
      let signalCount = 0;

      for (const [pickHash, group] of pickGroups.entries()) {
        if (group.sessionIds.length < MIN_GROUP_USERS || group.itemSignals.size === 0) continue;

        const sortedSignals = Array.from(group.itemSignals.entries())
          .sort((a, b) => b[1].score - a[1].score)
          .slice(0, MAX_ITEMS_PER_PERSONA);

        const totalUsers = group.sessionIds.length;
        const itemScores: Record<string, number> = {};
        const topItemSignals = sortedSignals.slice(0, MAX_TOP_ITEMS).map(([itemId, signal]) => {
          const normalizedScore = signal.score / totalUsers;
          itemScores[itemId] = round(normalizedScore);
          return {
            itemId,
            normalizedScore: round(normalizedScore),
            rawScore: round(signal.score),
            likeCount: signal.likeCount,
            swipeRightCount: signal.swipeRightCount,
            outboundClickCount: signal.outboundClickCount,
            supportingSessions: signal.sessions.size,
          };
        });

        for (const [itemId, signal] of sortedSignals.slice(MAX_TOP_ITEMS)) {
          itemScores[itemId] = round(signal.score / totalUsers);
        }

        const signalRef = db.collection("personaSignals").doc(pickHash);
        batch.set(signalRef, {
          pickHash,
          userCount: totalUsers,
          itemScores,
          itemScoresFromSimilarSessions: itemScores,
          topItems: sortedSignals.slice(0, MAX_TOP_ITEMS).map(([id]) => id),
          topItemSignals,
          signalWeights: {
            like: LIKE_WEIGHT,
            swipeRight: RIGHT_SWIPE_WEIGHT,
            outboundClick: OUTBOUND_CLICK_WEIGHT,
            halfLifeDays: SIGNAL_HALF_LIFE_DAYS,
          },
          updatedAt: FieldValue.serverTimestamp(),
        });

        pendingWrites += 1;
        signalCount += 1;
        if (pendingWrites >= 400) {
          await batch.commit();
          batch = db.batch();
          pendingWrites = 0;
        }
      }

      if (pendingWrites > 0) {
        await batch.commit();
      }

      if (signalCount > 0) {
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
    if (!signalDoc.exists) return null;

    const data = signalDoc.data();
    if (!data) return null;
    const itemScores = data.itemScores as Record<string, number> | undefined;
    if (itemScores && Object.keys(itemScores).length > 0) return itemScores;
    const compatScores = data.itemScoresFromSimilarSessions as Record<string, number> | undefined;
    if (compatScores && Object.keys(compatScores).length > 0) return compatScores;
    return null;
  } catch {
    return null;
  }
}
