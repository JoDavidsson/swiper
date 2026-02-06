import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";

const SUPPLY_ENGINE_URL = process.env.SUPPLY_ENGINE_URL || "http://localhost:8081";

/**
 * Check if a source has a recent active run.
 * Returns the active run ID if one exists, null otherwise.
 */
async function getActiveRun(sourceId: string): Promise<string | null> {
  const db = admin.firestore();
  
  // Check for runs that are either:
  // 1. Still in "running" status
  // 2. Started within the cooldown window
  const recentRuns = await db.collection("runs")
    .where("sourceId", "==", sourceId)
    .where("status", "==", "running")
    .limit(1)
    .get();
  
  if (!recentRuns.empty) {
    const runDoc = recentRuns.docs[0];
    const data = runDoc.data();
    const startedAt = data.startedAt?.toMillis?.() || 0;
    
    // If it's been running for more than 30 minutes, consider it stale
    if (Date.now() - startedAt > 30 * 60 * 1000) {
      console.log(`[admin_run_trigger] Marking stale run ${runDoc.id} as failed`);
      await runDoc.ref.update({ 
        status: "failed", 
        error: "Stale run - exceeded 30 minute timeout",
        updatedAt: FieldValue.serverTimestamp() 
      });
      return null;
    }
    
    return runDoc.id;
  }
  
  return null;
}

/**
 * Create a run record in Firestore.
 */
async function createRunRecord(sourceId: string): Promise<string> {
  const db = admin.firestore();
  const runRef = await db.collection("runs").add({
    sourceId,
    status: "running",
    startedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return runRef.id;
}

/**
 * Update a run record with results.
 */
async function updateRunRecord(runId: string, result: Record<string, unknown>): Promise<void> {
  const db = admin.firestore();
  await db.collection("runs").doc(runId).update({
    ...result,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

export async function adminRunTriggerPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sourceId = body?.sourceId as string;
  const force = body?.force === true; // Allow forcing a run even if one is active
  
  if (!sourceId) {
    res.status(400).json({ error: "sourceId required" });
    return;
  }
  
  // Check for duplicate/active runs (unless forced)
  if (!force) {
    const activeRunId = await getActiveRun(sourceId);
    if (activeRunId) {
      console.log(`[admin_run_trigger] Rejecting duplicate run for source ${sourceId}, active run: ${activeRunId}`);
      res.status(409).json({ 
        error: "Run already in progress",
        details: {
          sourceId,
          activeRunId,
          hint: "Wait for the current run to complete, or pass force=true to override",
        }
      });
      return;
    }
  }
  
  // Create run record before triggering
  const runId = await createRunRecord(sourceId);
  console.log(`[admin_run_trigger] Created run record: ${runId} for source: ${sourceId}`);
  
  // Log the URL being called for debugging
  const url = `${SUPPLY_ENGINE_URL.replace(/\/$/, "")}/run/${sourceId}`;
  console.log(`[admin_run_trigger] Calling Supply Engine: ${url}`);
  
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000); // 30s timeout
    
    const r = await fetch(url, { 
      method: "POST", 
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
    });
    clearTimeout(timeout);
    
    const text = await r.text();
    if (!r.ok) {
      console.error(`[admin_run_trigger] Supply Engine returned ${r.status}: ${text}`);
      
      // Update run record with failure
      await updateRunRecord(runId, {
        status: "failed",
        error: text || "Supply engine error",
        statusCode: r.status,
      });
      
      res.status(r.status).json({ 
        error: text || "Supply engine error",
        details: {
          supplyEngineUrl: SUPPLY_ENGINE_URL,
          statusCode: r.status,
          sourceId,
          runId,
        }
      });
      return;
    }
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      data = { message: text };
    }
    
    // Update run record with success and results
    await updateRunRecord(runId, {
      status: "completed",
      ...data,
    });
    
    res.status(200).json({ ...data, runId });
  } catch (e) {
    console.error(`[admin_run_trigger] Error calling Supply Engine:`, e);
    
    const error = e as Error;
    const isConnectionError = 
      error.message?.includes("ECONNREFUSED") ||
      error.message?.includes("fetch failed") ||
      error.name === "AbortError" ||
      error.message?.includes("network");
    
    // Update run record with failure
    await updateRunRecord(runId, {
      status: "failed",
      error: error.message || String(e),
      isConnectionError,
    });
    
    if (isConnectionError) {
      res.status(503).json({ 
        error: "Supply Engine is not reachable",
        details: {
          supplyEngineUrl: SUPPLY_ENGINE_URL,
          sourceId,
          runId,
          hint: "Make sure the Supply Engine is running. Start it with: ./scripts/run_supply_engine.sh",
          originalError: error.message,
        }
      });
      return;
    }
    
    res.status(500).json({ 
      error: String(e),
      details: {
        supplyEngineUrl: SUPPLY_ENGINE_URL,
        sourceId,
        runId,
      }
    });
  }
}
