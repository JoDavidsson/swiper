import * as functions from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

const DEFAULT_EVENTS_RETENTION_DAYS = 730;
const DELETE_BATCH_SIZE = 400;

function getRetentionDays(): number {
  const raw = parseInt(String(process.env.EVENTS_V1_RETENTION_DAYS || DEFAULT_EVENTS_RETENTION_DAYS), 10);
  if (!Number.isFinite(raw) || raw <= 0) return DEFAULT_EVENTS_RETENTION_DAYS;
  return raw;
}

async function deleteExpiredEvents(retentionDays: number): Promise<number> {
  const db = admin.firestore();
  const cutoffMs = Date.now() - retentionDays * 24 * 60 * 60 * 1000;
  const cutoff = admin.firestore.Timestamp.fromMillis(cutoffMs);

  let deleted = 0;
  while (true) {
    const snapshot = await db
      .collection("events_v1")
      .where("createdAtServer", "<", cutoff)
      .orderBy("createdAtServer", "asc")
      .limit(DELETE_BATCH_SIZE)
      .get();

    if (snapshot.empty) break;

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += snapshot.size;

    if (snapshot.size < DELETE_BATCH_SIZE) break;
  }

  return deleted;
}

export const cleanupAnalyticsEvents = functions.onSchedule(
  {
    schedule: "17 3 * * *",
    timeZone: "UTC",
    retryCount: 1,
    memory: "256MiB",
    timeoutSeconds: 540,
  },
  async () => {
    const retentionDays = getRetentionDays();
    const deleted = await deleteExpiredEvents(retentionDays);
    console.log("analytics_events_retention_cleanup", {
      retentionDays,
      deleted,
    });
  }
);
