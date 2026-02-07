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

/**
 * Batch trigger: run multiple sources in parallel.
 * POST /api/admin/run-batch { sourceIds: ["id1", "id2", ...] }
 */
export async function adminRunBatchPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sourceIds = body?.sourceIds as string[] | undefined;

  if (!sourceIds || !Array.isArray(sourceIds) || sourceIds.length === 0) {
    res.status(400).json({ error: "sourceIds array required" });
    return;
  }

  console.log(`[admin_run_batch] Starting batch for ${sourceIds.length} sources: ${sourceIds.join(", ")}`);

  // Option A: Call the Supply Engine /run-batch endpoint (single HTTP call)
  const url = `${SUPPLY_ENGINE_URL.replace(/\/$/, "")}/run-batch`;
  
  try {
    const controller = new AbortController();
    // Generous timeout for batch: 10 minutes
    const timeout = setTimeout(() => controller.abort(), 10 * 60 * 1000);
    
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source_ids: sourceIds }),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    
    const text = await r.text();
    if (!r.ok) {
      console.error(`[admin_run_batch] Supply Engine returned ${r.status}: ${text}`);
      res.status(r.status).json({ error: text || "Supply engine error" });
      return;
    }
    
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      data = { message: text };
    }
    
    console.log(`[admin_run_batch] Batch complete: ${JSON.stringify(data).slice(0, 200)}`);
    res.status(200).json(data);
  } catch (e) {
    console.error(`[admin_run_batch] Error:`, e);
    const error = e as Error;
    
    if (error.name === "AbortError") {
      res.status(504).json({ error: "Batch timed out (10 min limit)" });
      return;
    }
    
    const isConnectionError = 
      error.message?.includes("ECONNREFUSED") ||
      error.message?.includes("fetch failed");
    
    if (isConnectionError) {
      res.status(503).json({
        error: "Supply Engine is not reachable",
        hint: "Start it with: ./scripts/run_supply_engine.sh",
      });
      return;
    }
    
    res.status(500).json({ error: String(e) });
  }
}


/**
 * Re-extract images for items with broken/missing images.
 * POST /api/admin/re-extract-images { source_ids?: ["id1"], limit?: 500, dry_run?: false }
 */
export async function adminReExtractImagesPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;

  console.log(`[admin_re_extract_images] Starting image re-extraction`);

  const url = `${SUPPLY_ENGINE_URL.replace(/\/$/, "")}/re-extract-images`;

  try {
    const controller = new AbortController();
    // Generous timeout: 30 minutes (re-extraction fetches many pages)
    const timeout = setTimeout(() => controller.abort(), 30 * 60 * 1000);

    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        source_ids: body?.source_ids || body?.sourceIds || null,
        limit: body?.limit || 500,
        dry_run: body?.dry_run || body?.dryRun || false,
      }),
      signal: controller.signal,
    });
    clearTimeout(timeout);

    const text = await r.text();
    if (!r.ok) {
      console.error(`[admin_re_extract_images] Supply Engine returned ${r.status}: ${text}`);
      res.status(r.status).json({ error: text || "Supply engine error" });
      return;
    }

    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      data = { message: text };
    }

    console.log(`[admin_re_extract_images] Complete: ${JSON.stringify(data).slice(0, 200)}`);
    res.status(200).json(data);
  } catch (e) {
    console.error(`[admin_re_extract_images] Error:`, e);
    const error = e as Error;

    if (error.name === "AbortError") {
      res.status(504).json({ error: "Re-extraction timed out (30 min limit)" });
      return;
    }

    const isConnectionError =
      error.message?.includes("ECONNREFUSED") ||
      error.message?.includes("fetch failed");

    if (isConnectionError) {
      res.status(503).json({
        error: "Supply Engine is not reachable",
        hint: "Start it with: ./scripts/run_supply_engine.sh",
      });
      return;
    }

    res.status(500).json({ error: String(e) });
  }
}


/**
 * Get image health statistics per retailer.
 * GET /api/admin/image-health?source_id=optional
 */
export async function adminImageHealthGet(req: Request, res: Response): Promise<void> {
  const sourceId = req.query.source_id as string | undefined;

  const params = sourceId ? `?source_id=${encodeURIComponent(sourceId)}` : "";
  const url = `${SUPPLY_ENGINE_URL.replace(/\/$/, "")}/image-health${params}`;

  console.log(`[admin_image_health] Fetching image health stats`);

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);

    const r = await fetch(url, { signal: controller.signal });
    clearTimeout(timeout);

    const text = await r.text();
    if (!r.ok) {
      res.status(r.status).json({ error: text || "Supply engine error" });
      return;
    }

    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      data = { message: text };
    }

    res.status(200).json(data);
  } catch (e) {
    const error = e as Error;
    const isConnectionError =
      error.message?.includes("ECONNREFUSED") ||
      error.message?.includes("fetch failed");

    if (isConnectionError) {
      res.status(503).json({
        error: "Supply Engine is not reachable",
        hint: "Start it with: ./scripts/run_supply_engine.sh",
      });
      return;
    }

    res.status(500).json({ error: String(e) });
  }
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


/**
 * Generic proxy function to forward requests to the Supply Engine.
 * Used for all EPIC C/D/F endpoints.
 */
export async function adminProxyToSupplyEngine(
  req: Request,
  res: Response,
  path: string,
  method: "GET" | "POST",
): Promise<void> {
  try {
    const url = new URL(path, SUPPLY_ENGINE_URL);

    // Forward query params for GET requests
    if (method === "GET" && req.query) {
      for (const [key, value] of Object.entries(req.query)) {
        if (typeof value === "string") {
          url.searchParams.set(key, value);
        }
      }
    }

    const fetchOptions: RequestInit = {
      method,
      headers: { "Content-Type": "application/json" },
    };

    if (method === "POST" && req.body) {
      fetchOptions.body = JSON.stringify(req.body);
    }

    const response = await fetch(url.toString(), fetchOptions);
    const data = await response.json();

    res.status(response.status).json(data);
  } catch (e) {
    console.error(`[adminProxy] Error proxying to ${path}:`, e);
    res.status(500).json({ error: `Proxy error: ${String(e)}`, path });
  }
}


/**
 * E4: Explainability – returns why an item was accepted/rejected.
 *
 * Reads classification, eligibility, and Gold status for a single item.
 */
export async function adminExplainGet(req: Request, res: Response, itemId: string): Promise<void> {
  const db = admin.firestore();

  const [itemSnap, goldSnap, reviewSnap] = await Promise.all([
    db.collection("items").doc(itemId).get(),
    db.collection("goldItems").doc(itemId).get(),
    db.collection("reviewQueue").doc(itemId).get(),
  ]);

  if (!itemSnap.exists) {
    res.status(404).json({ error: `Item ${itemId} not found` });
    return;
  }

  const itemData = itemSnap.data() || {};
  const goldData = goldSnap.exists ? goldSnap.data() : null;
  const reviewData = reviewSnap.exists ? reviewSnap.data() : null;

  res.status(200).json({
    itemId,
    title: itemData.title,
    sourceId: itemData.sourceId,
    canonicalUrl: itemData.canonicalUrl,
    classification: itemData.classification || null,
    eligibility: itemData.eligibility || null,
    isInGold: goldSnap.exists,
    goldDoc: goldData ? {
      eligibleSurfaces: goldData.eligibleSurfaces,
      predictedCategory: goldData.predictedCategory,
      categoryConfidence: goldData.categoryConfidence,
      humanVerified: goldData.humanVerified || false,
      promotedAt: goldData.promotedAt,
    } : null,
    isInReviewQueue: reviewSnap.exists,
    reviewStatus: reviewData?.status || null,
    enrichmentEvidence: itemData.enrichmentEvidence || [],
    breadcrumbs: itemData.breadcrumbs || [],
    productType: itemData.productType,
    facets: itemData.facets || {},
  });
}
