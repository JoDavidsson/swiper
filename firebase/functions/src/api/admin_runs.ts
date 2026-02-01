import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function adminRunsGet(req: Request, res: Response): Promise<void> {
  const sourceId = req.query.sourceId as string | undefined;
  const limit = Math.min(parseInt(String(req.query.limit || 50), 10) || 50, 100);
  const db = admin.firestore();
  const snap = await db.collection("ingestionRuns").orderBy("startedAt", "desc").limit(limit * 2).get();
  let docs = snap.docs;
  if (sourceId) {
    docs = docs.filter((d) => d.data().sourceId === sourceId);
  }
  docs = docs.slice(0, limit);
  const runs = docs.map((d) => ({ id: d.id, ...d.data(), startedAt: (d.data().startedAt as admin.firestore.Timestamp)?.toMillis?.() ?? null, finishedAt: (d.data().finishedAt as admin.firestore.Timestamp)?.toMillis?.() ?? null }));
  res.status(200).json({ runs });
}

export async function adminRunGet(req: Request, res: Response, runId: string): Promise<void> {
  const db = admin.firestore();
  const runSnap = await db.collection("ingestionRuns").doc(runId).get();
  if (!runSnap.exists) {
    res.status(404).json({ error: "Run not found" });
    return;
  }
  const jobsSnap = await db.collection("ingestionJobs").where("runId", "==", runId).orderBy("createdAt", "asc").get();
  const jobs = jobsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
  res.status(200).json({ id: runSnap.id, ...runSnap.data(), jobs });
}
