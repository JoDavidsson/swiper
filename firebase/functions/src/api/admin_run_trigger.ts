import { Request } from "firebase-functions/v2/https";
import { Response } from "express";

const SUPPLY_ENGINE_URL = process.env.SUPPLY_ENGINE_URL || "http://localhost:8081";

export async function adminRunTriggerPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sourceId = body?.sourceId as string;
  if (!sourceId) {
    res.status(400).json({ error: "sourceId required" });
    return;
  }
  
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
      res.status(r.status).json({ 
        error: text || "Supply engine error",
        details: {
          supplyEngineUrl: SUPPLY_ENGINE_URL,
          statusCode: r.status,
          sourceId,
        }
      });
      return;
    }
    let data: unknown;
    try {
      data = JSON.parse(text);
    } catch {
      data = { message: text };
    }
    res.status(200).json(data);
  } catch (e) {
    console.error(`[admin_run_trigger] Error calling Supply Engine:`, e);
    
    const error = e as Error;
    const isConnectionError = 
      error.message?.includes("ECONNREFUSED") ||
      error.message?.includes("fetch failed") ||
      error.name === "AbortError" ||
      error.message?.includes("network");
    
    if (isConnectionError) {
      res.status(503).json({ 
        error: "Supply Engine is not reachable",
        details: {
          supplyEngineUrl: SUPPLY_ENGINE_URL,
          sourceId,
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
      }
    });
  }
}
