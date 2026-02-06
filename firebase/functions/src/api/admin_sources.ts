import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";

// Supply engine URL (set via environment variable or default to localhost)
// Default port 8081 matches scripts/run_supply_engine.sh
const SUPPLY_ENGINE_URL = process.env.SUPPLY_ENGINE_URL || "http://localhost:8081";

/**
 * Normalize a URL to ensure it has https:// protocol.
 * Converts bare domains like "www.mio.se" to "https://www.mio.se"
 */
function normalizeUrl(url: string | undefined): string | undefined {
  if (!url || typeof url !== "string") return url;
  const trimmed = url.trim();
  if (!trimmed) return trimmed;
  
  // If no protocol, add https://
  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
    return `https://${trimmed}`;
  }
  return trimmed;
}

/**
 * Validate source data and return normalized data with any errors.
 */
function validateAndNormalizeSource(body: Record<string, unknown>): {
  normalized: Record<string, unknown>;
  errors: string[];
} {
  const errors: string[] = [];
  const normalized: Record<string, unknown> = { ...body };
  
  // Normalize URL fields
  if (normalized.url) {
    normalized.url = normalizeUrl(normalized.url as string);
  }
  if (normalized.baseUrl) {
    normalized.baseUrl = normalizeUrl(normalized.baseUrl as string);
  }
  
  // Normalize seedUrls array
  if (Array.isArray(normalized.seedUrls)) {
    normalized.seedUrls = (normalized.seedUrls as string[])
      .map((u) => normalizeUrl(u))
      .filter((u) => u); // Remove empty/undefined
  }
  
  // Validate: seedType=manual requires non-empty seedUrls
  const seedType = normalized.seedType as string | undefined;
  const seedUrls = normalized.seedUrls as string[] | undefined;
  
  if (seedType === "manual") {
    if (!seedUrls || seedUrls.length === 0) {
      errors.push("seedType 'manual' requires at least one URL in seedUrls");
    }
  }
  
  // Validate: must have either url, baseUrl, or seedUrls
  const hasUrl = normalized.url || normalized.baseUrl;
  const hasSeedUrls = seedUrls && seedUrls.length > 0;
  
  if (!hasUrl && !hasSeedUrls) {
    errors.push("Source must have either a url/baseUrl or seedUrls");
  }
  
  return { normalized, errors };
}

/**
 * Call the supply engine's /discover endpoint to auto-discover configuration.
 */
async function callSupplyEngineDiscover(url: string, rateLimitRps: number = 1.0): Promise<{
  discovery: Record<string, unknown>;
  derivedConfig: Record<string, unknown>;
} | null> {
  try {
    const response = await fetch(`${SUPPLY_ENGINE_URL}/discover`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url, rate_limit_rps: rateLimitRps }),
    });
    if (!response.ok) {
      console.error("Supply engine discover failed:", response.status, await response.text());
      return null;
    }
    return await response.json();
  } catch (error) {
    console.error("Supply engine discover error:", error);
    return null;
  }
}

export async function adminSourcesGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection("sources").orderBy("name").get();
  const sources = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  res.status(200).json({ sources });
}

export async function adminSourcesPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  if (!body) {
    res.status(400).json({ error: "Body required" });
    return;
  }
  
  // Validate and normalize the source data
  const { normalized, errors } = validateAndNormalizeSource(body);
  if (errors.length > 0) {
    res.status(400).json({ error: "Validation failed", details: errors });
    return;
  }
  
  const db = admin.firestore();
  const ref = await db.collection("sources").add({
    ...normalized,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  res.status(200).json({ id: ref.id });
}

export async function adminSourceGet(req: Request, res: Response, sourceId: string): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection("sources").doc(sourceId).get();
  if (!snap.exists) {
    res.status(404).json({ error: "Source not found" });
    return;
  }
  res.status(200).json({ id: snap.id, ...snap.data() });
}

export async function adminSourcePut(req: Request, res: Response, sourceId: string): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  if (!body) {
    res.status(400).json({ error: "Body required" });
    return;
  }
  
  const db = admin.firestore();
  
  // Check if URL changed - if so, we need to clear derived config
  // to force re-discovery on next run (prevents stale derived overrides)
  const existing = await db.collection("sources").doc(sourceId).get();
  if (!existing.exists) {
    res.status(404).json({ error: "Source not found" });
    return;
  }
  
  // Validate and normalize the source data
  const { normalized, errors } = validateAndNormalizeSource(body);
  if (errors.length > 0) {
    res.status(400).json({ error: "Validation failed", details: errors });
    return;
  }
  
  const existingData = existing.data() as Record<string, unknown>;
  const existingUrl = existingData?.url || existingData?.baseUrl;
  const newUrl = normalized.url || normalized.baseUrl;
  
  const updateData: Record<string, unknown> = {
    ...normalized,
    updatedAt: FieldValue.serverTimestamp(),
  };
  
  // Clear derived config if URL changed (forces re-discovery)
  if (newUrl && existingUrl && newUrl !== existingUrl) {
    console.log(`[adminSourcePut] URL changed from "${existingUrl}" to "${newUrl}", clearing derived config`);
    updateData.derived = FieldValue.delete();
  }
  
  await db.collection("sources").doc(sourceId).update(updateData);
  res.status(200).json({ ok: true });
}

export async function adminSourceDelete(req: Request, res: Response, sourceId: string): Promise<void> {
  const db = admin.firestore();
  await db.collection("sources").doc(sourceId).delete();
  res.status(200).json({ ok: true });
}

/**
 * Preview endpoint: Auto-discover crawl configuration from a URL.
 * 
 * POST /api/admin/sources/preview
 * Body: { url: string, rateLimitRps?: number }
 * 
 * Returns discovery results including:
 * - normalized URL components
 * - sitemaps found
 * - estimated product counts
 * - recommended strategy
 */
export async function adminSourcesPreview(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  if (!body || typeof body.url !== "string" || !body.url.trim()) {
    res.status(400).json({ error: "url is required" });
    return;
  }

  const url = (body.url as string).trim();
  const rateLimitRps = typeof body.rateLimitRps === "number" ? body.rateLimitRps : 1.0;

  const result = await callSupplyEngineDiscover(url, rateLimitRps);
  if (!result) {
    res.status(500).json({ 
      error: "Discovery failed", 
      message: "Could not connect to supply engine or discovery failed" 
    });
    return;
  }

  res.status(200).json(result);
}

/**
 * Create a source with auto-discovery.
 * 
 * POST /api/admin/sources/create-with-discovery
 * Body: { 
 *   url: string,           // User's raw input URL
 *   name?: string,         // Optional display name
 *   rateLimitRps?: number, // Optional rate limit (default: 1.0)
 *   isEnabled?: boolean,   // Optional enabled flag (default: true)
 *   includeKeywords?: string[], // Optional keyword filter overrides
 *   categoryFilter?: string[], // URL path patterns to filter (e.g., ["soffor", "soffa"])
 * }
 * 
 * This endpoint:
 * 1. Calls the supply engine /discover to get derived config
 * 2. Stores both user input and derived config in Firestore
 */
export async function adminSourcesCreateWithDiscovery(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  if (!body || typeof body.url !== "string" || !body.url.trim()) {
    res.status(400).json({ error: "url is required" });
    return;
  }

  const url = (body.url as string).trim();
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const rateLimitRps = typeof body.rateLimitRps === "number" ? body.rateLimitRps : 1.0;
  const isEnabled = body.isEnabled !== false; // Default true
  const includeKeywords = Array.isArray(body.includeKeywords) ? body.includeKeywords : null;
  const categoryFilter = Array.isArray(body.categoryFilter) ? body.categoryFilter : null;

  // Call supply engine for auto-discovery
  const discoveryResult = await callSupplyEngineDiscover(url, rateLimitRps);
  if (!discoveryResult) {
    res.status(500).json({ 
      error: "Discovery failed", 
      message: "Could not auto-discover configuration from URL" 
    });
    return;
  }

  const { discovery, derivedConfig } = discoveryResult;

  // Check for discovery errors
  const errors = (discovery as Record<string, unknown>).errors as string[] | undefined;
  if (errors && errors.length > 0) {
    res.status(400).json({ 
      error: "Discovery returned errors", 
      details: errors 
    });
    return;
  }

  // Build source document
  const domain = (derivedConfig as Record<string, unknown>).domain as string || "";
  const autoName = name || (domain ? domain.replace(/^www\./, "") : url);
  
  const sourceDoc: Record<string, unknown> = {
    // User input
    url,
    name: autoName,
    isEnabled,
    rateLimitRps,
    mode: "crawl", // Auto-discovered sources are always crawl mode
    
    // Auto-derived configuration
    derived: {
      ...derivedConfig,
      discoveredAt: new Date().toISOString(),
    },
    
    // Legacy fields for backward compatibility (populated from derived)
    baseUrl: (derivedConfig as Record<string, unknown>).baseUrl,
    seedUrls: [], // Not needed for derived sources
    seedType: (derivedConfig as Record<string, unknown>).strategy,
    
    // Optional overrides
    ...(includeKeywords && { includeKeywords }),
    ...(categoryFilter && { categoryFilter }),
    
    // Metadata
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  const db = admin.firestore();
  const ref = await db.collection("sources").add(sourceDoc);

  res.status(200).json({ 
    id: ref.id, 
    discovery,
    derivedConfig,
  });
}
