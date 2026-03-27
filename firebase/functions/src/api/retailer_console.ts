import { Request, Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { randomUUID } from "crypto";
import { requireUserAuth } from "../middleware/require_user_auth";
import { getScoreBand } from "./scores";

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 250;
const DEFAULT_REPORT_SHARE_TTL_DAYS = 14;

type RetailerAccessResult =
  | {
      ok: true;
      retailerId: string;
      retailerData: Record<string, unknown>;
    }
  | {
      ok: false;
      status: number;
      error: string;
    };

type CampaignReportRow = {
  campaignId: string;
  name: string;
  status: string;
  segmentId: string | null;
  spend: number;
  impressions: number;
  featuredImpressions: number;
  outcomes: number;
  cpScore: number;
};

function asTrimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function asBoolean(value: unknown): boolean | null {
  if (typeof value === "boolean") return value;
  return null;
}

function toBodyObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function toDateKeyUTC(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function normalizeRetailerSlug(value: unknown): string | null {
  const token = asTrimmedString(value);
  return token ? token.toLowerCase() : null;
}

function toRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

function toDateMillis(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof value === "object") {
    const candidate = value as { toMillis?: () => number; toDate?: () => Date };
    if (typeof candidate.toMillis === "function") {
      const ms = candidate.toMillis();
      return Number.isFinite(ms) ? ms : null;
    }
    if (typeof candidate.toDate === "function") {
      const ms = candidate.toDate().getTime();
      return Number.isFinite(ms) ? ms : null;
    }
  }
  return null;
}

function formatTimestamp(value: unknown): string | null {
  const ms = toDateMillis(value);
  return ms == null ? null : new Date(ms).toISOString();
}

function isDateWithinRange(ms: number, fromMs: number | null, toMs: number | null): boolean {
  if (fromMs != null && ms < fromMs) return false;
  if (toMs != null && ms > toMs) return false;
  return true;
}

function sumNumberRecordWithinDateRange(
  value: unknown,
  fromMs: number | null,
  toMs: number | null
): number {
  const record = toRecord(value);
  if (!record) return 0;
  let total = 0;
  for (const [dateKey, entry] of Object.entries(record)) {
    const ms = Date.parse(`${dateKey}T00:00:00.000Z`);
    if (!Number.isFinite(ms)) continue;
    if (!isDateWithinRange(ms, fromMs, toMs)) continue;
    total += asFiniteNumber(entry) ?? 0;
  }
  return total;
}

function parseDateRange(req: Request): { fromMs: number | null; toMs: number | null } {
  const dateFromParam = asTrimmedString(req.query.dateFrom);
  const dateToParam = asTrimmedString(req.query.dateTo);
  const fromMs = dateFromParam ? Date.parse(`${dateFromParam}T00:00:00.000Z`) : null;
  const toMs = dateToParam ? Date.parse(`${dateToParam}T23:59:59.999Z`) : null;
  return {
    fromMs: Number.isFinite(fromMs ?? Number.NaN) ? (fromMs as number) : null,
    toMs: Number.isFinite(toMs ?? Number.NaN) ? (toMs as number) : null,
  };
}

function itemBelongsToRetailer(itemData: Record<string, unknown>, retailerId: string): boolean {
  const itemRetailer =
    normalizeRetailerSlug(itemData.retailer) || normalizeRetailerSlug(itemData.retailerId);
  return itemRetailer === normalizeRetailerSlug(retailerId);
}

function escapeCsvCell(value: unknown): string {
  const text = value == null ? "" : String(value);
  if (text.includes(",") || text.includes('"') || text.includes("\n")) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

async function resolveRetailerAccess(
  db: admin.firestore.Firestore,
  userUid: string,
  requestedRetailerId: string | null
): Promise<RetailerAccessResult> {
  const ownedRetailersSnap = await db
    .collection("retailers")
    .where("ownerUserIds", "array-contains", userUid)
    .limit(20)
    .get();

  if (ownedRetailersSnap.empty) {
    return {
      ok: false,
      status: 404,
      error: "No retailer found for this user. Claim a retailer first.",
    };
  }

  const retailerDocs = ownedRetailersSnap.docs;
  const selectedDoc =
    requestedRetailerId != null
      ? retailerDocs.find((doc) => doc.id === requestedRetailerId)
      : retailerDocs[0];

  if (!selectedDoc) {
    return {
      ok: false,
      status: 403,
      error: "Access denied for requested retailer",
    };
  }

  return {
    ok: true,
    retailerId: selectedDoc.id,
    retailerData: (selectedDoc.data() || {}) as Record<string, unknown>,
  };
}

async function loadItemById(
  db: admin.firestore.Firestore,
  itemId: string
): Promise<Record<string, unknown> | null> {
  const [goldDoc, itemDoc] = await Promise.all([
    db.collection("goldItems").doc(itemId).get(),
    db.collection("items").doc(itemId).get(),
  ]);
  if (goldDoc.exists) return (goldDoc.data() || {}) as Record<string, unknown>;
  if (itemDoc.exists) return (itemDoc.data() || {}) as Record<string, unknown>;
  return null;
}

async function loadRetailerCatalogRows(
  db: admin.firestore.Firestore,
  retailerId: string,
  limit: number
): Promise<Array<Record<string, unknown>>> {
  const cappedLimit = Math.max(1, Math.min(limit, MAX_LIMIT));
  const fetchLimit = Math.max(cappedLimit * 2, 150);

  const [itemsByRetailer, itemsByRetailerId, controlsSnap] = await Promise.all([
    db.collection("items").where("retailer", "==", retailerId).limit(fetchLimit).get(),
    db.collection("items").where("retailerId", "==", retailerId).limit(fetchLimit).get(),
    db
      .collection("retailerCatalogControls")
      .where("retailerId", "==", retailerId)
      .limit(1000)
      .get(),
  ]);

  const controlsByItemId = new Map<string, Record<string, unknown>>();
  for (const doc of controlsSnap.docs) {
    controlsByItemId.set(doc.id.split("_").slice(1).join("_"), (doc.data() || {}) as Record<string, unknown>);
  }

  const docs = [...itemsByRetailer.docs, ...itemsByRetailerId.docs];
  const itemById = new Map<string, Record<string, unknown>>();
  for (const doc of docs) {
    const data = (doc.data() || {}) as Record<string, unknown>;
    if (!itemBelongsToRetailer(data, retailerId)) continue;
    if (data.isActive === false) continue;
    itemById.set(doc.id, data);
    if (itemById.size >= cappedLimit) break;
  }

  const itemIds = Array.from(itemById.keys());
  const scoresByProductId = new Map<
    string,
    { score: number; band: string; reasonCodes: string[]; impressions: number; lowData: boolean }
  >();

  for (let start = 0; start < itemIds.length; start += 30) {
    const chunk = itemIds.slice(start, start + 30);
    if (chunk.length === 0) continue;
    const scoreSnap = await db
      .collection("scores")
      .where("productId", "in", chunk)
      .limit(400)
      .get();
    for (const scoreDoc of scoreSnap.docs) {
      const scoreData = (scoreDoc.data() || {}) as Record<string, unknown>;
      if (asTrimmedString(scoreData.timeWindow) !== "30d") continue;
      const productId = asTrimmedString(scoreData.productId);
      const score = asFiniteNumber(scoreData.score);
      if (!productId || score == null) continue;
      const previous = scoresByProductId.get(productId);
      if (!previous || score > previous.score) {
        scoresByProductId.set(productId, {
          score,
          band: getScoreBand(score),
          reasonCodes: Array.isArray(scoreData.reasonCodes)
            ? scoreData.reasonCodes
                .map((entry) => asTrimmedString(entry))
                .filter((entry): entry is string => entry != null)
            : [],
          impressions: asFiniteNumber(scoreData.impressions) ?? 0,
          lowData: scoreData.lowData === true,
        });
      }
    }
  }

  const rows: Array<Record<string, unknown>> = [];
  for (const itemId of itemIds) {
    const itemData = itemById.get(itemId);
    if (!itemData) continue;
    const control = controlsByItemId.get(itemId);
    const included = control != null ? control.included !== false : itemData.retailerCatalogIncluded !== false;
    const score = scoresByProductId.get(itemId);
    const creativeHealth = toRecord(itemData.creativeHealth);
    const classification = toRecord(itemData.classification);
    const environment = asTrimmedString(
      itemData.environment ??
        classification?.environment
    );

    rows.push({
      id: itemId,
      title: asTrimmedString(itemData.title) || "Untitled",
      priceAmount: asFiniteNumber(itemData.priceAmount),
      priceCurrency: asTrimmedString(itemData.priceCurrency) || "SEK",
      images: Array.isArray(itemData.images) ? itemData.images : [],
      primaryCategory:
        asTrimmedString(itemData.primaryCategory) ||
        asTrimmedString(classification?.primaryCategory) ||
        asTrimmedString(classification?.predictedCategory),
      sofaTypeShape:
        asTrimmedString(itemData.sofaTypeShape) ||
        asTrimmedString(classification?.sofaTypeShape),
      sofaFunction:
        asTrimmedString(itemData.sofaFunction) ||
        asTrimmedString(classification?.sofaFunction),
      seatCountBucket:
        asTrimmedString(itemData.seatCountBucket) ||
        asTrimmedString(classification?.seatCountBucket),
      environment: environment && environment.toLowerCase() !== "unknown" ? environment : null,
      roomTypes: Array.isArray(itemData.roomTypes)
        ? itemData.roomTypes
        : (Array.isArray(classification?.roomTypes) ? classification?.roomTypes : []),
      subCategory: asTrimmedString(itemData.subCategory) || asTrimmedString(classification?.subCategory),
      included,
      inclusionReason: asTrimmedString(control?.reason) || null,
      score:
        score != null
          ? {
              value: Number(score.score.toFixed(2)),
              band: score.band,
              reasonCodes: score.reasonCodes,
              impressions: score.impressions,
              lowData: score.lowData,
            }
          : null,
      creativeHealth: {
        score: asFiniteNumber(creativeHealth?.["score"]),
        band: asTrimmedString(creativeHealth?.["band"]),
        issues: Array.isArray(creativeHealth?.["issues"])
          ? (creativeHealth?.["issues"] as unknown[])
              .map((entry) => asTrimmedString(entry))
              .filter((entry): entry is string => entry != null)
          : [],
      },
      updatedAt: formatTimestamp(itemData.updatedAt),
    });
  }

  return rows;
}

async function buildRetailerReport(
  db: admin.firestore.Firestore,
  retailerId: string,
  fromMs: number | null,
  toMs: number | null
): Promise<Record<string, unknown>> {
  const campaignsSnap = await db.collection("campaigns").where("retailerId", "==", retailerId).limit(500).get();
  const bySegment = new Map<string, { spend: number; impressions: number; outcomes: number }>();
  const campaignRows: CampaignReportRow[] = [];

  let spend = 0;
  let impressions = 0;
  let featuredImpressions = 0;
  let confidenceOutcomes = 0;

  for (const doc of campaignsSnap.docs) {
    const data = (doc.data() || {}) as Record<string, unknown>;
    const segmentId = asTrimmedString(data.segmentId) || null;
    const campaignSpend =
      fromMs == null && toMs == null
        ? asFiniteNumber(data.budgetSpent) ?? 0
        : sumNumberRecordWithinDateRange(data.dailySpendByDate, fromMs, toMs);
    const campaignFeaturedImpressions =
      fromMs == null && toMs == null
        ? asFiniteNumber(data.featuredImpressions) ?? asFiniteNumber(data.impressions) ?? 0
        : sumNumberRecordWithinDateRange(data.dailyImpressionsByDate, fromMs, toMs);
    const campaignImpressions =
      fromMs == null && toMs == null
        ? asFiniteNumber(data.impressions) ?? campaignFeaturedImpressions
        : campaignFeaturedImpressions;
    const campaignOutcomes = asFiniteNumber(data.clicks) ?? 0;
    const campaignCpScore =
      campaignSpend > 0 ? Number(((campaignOutcomes / campaignSpend) * 100).toFixed(2)) : 0;

    spend += campaignSpend;
    impressions += campaignImpressions;
    featuredImpressions += campaignFeaturedImpressions;
    confidenceOutcomes += campaignOutcomes;

    campaignRows.push({
      campaignId: doc.id,
      name: asTrimmedString(data.name) || "Untitled campaign",
      status: asTrimmedString(data.status) || "unknown",
      segmentId,
      spend: Number(campaignSpend.toFixed(2)),
      impressions: Math.round(campaignImpressions),
      featuredImpressions: Math.round(campaignFeaturedImpressions),
      outcomes: Math.round(campaignOutcomes),
      cpScore: campaignCpScore,
    });

    if (segmentId) {
      const prev = bySegment.get(segmentId) || { spend: 0, impressions: 0, outcomes: 0 };
      prev.spend += campaignSpend;
      prev.impressions += campaignImpressions;
      prev.outcomes += campaignOutcomes;
      bySegment.set(segmentId, prev);
    }
  }

  const bySegmentRows = Array.from(bySegment.entries())
    .map(([segmentId, aggregate]) => ({
      segmentId,
      spend: Number(aggregate.spend.toFixed(2)),
      impressions: Math.round(aggregate.impressions),
      outcomes: Math.round(aggregate.outcomes),
      cpScore:
        aggregate.spend > 0 ? Number(((aggregate.outcomes / aggregate.spend) * 100).toFixed(2)) : 0,
    }))
    .sort((a, b) => b.impressions - a.impressions);

  const featuredImpressionsSnap = await db
    .collection("featuredImpressions")
    .where("retailerId", "==", retailerId)
    .limit(6000)
    .get();

  const byProduct = new Map<string, { impressions: number; campaignId: string | null }>();
  for (const doc of featuredImpressionsSnap.docs) {
    const data = (doc.data() || {}) as Record<string, unknown>;
    const createdAtMs = toDateMillis(data.createdAt);
    if (createdAtMs != null && !isDateWithinRange(createdAtMs, fromMs, toMs)) continue;
    const itemId = asTrimmedString(data.itemId);
    if (!itemId) continue;
    const prev = byProduct.get(itemId) || {
      impressions: 0,
      campaignId: asTrimmedString(data.campaignId),
    };
    prev.impressions += 1;
    if (!prev.campaignId) prev.campaignId = asTrimmedString(data.campaignId);
    byProduct.set(itemId, prev);
  }

  const topProductIds = Array.from(byProduct.entries())
    .sort((a, b) => b[1].impressions - a[1].impressions)
    .slice(0, 40)
    .map(([itemId]) => itemId);

  const topProductDocs =
    topProductIds.length > 0
      ? await db.getAll(...topProductIds.map((itemId) => db.collection("items").doc(itemId))
      )
      : [];
  const titleByProductId = new Map<string, string>();
  for (const doc of topProductDocs) {
    if (!doc.exists) continue;
    const data = (doc.data() || {}) as Record<string, unknown>;
    titleByProductId.set(doc.id, asTrimmedString(data.title) || "Untitled");
  }

  const byProductRows = topProductIds.map((itemId) => {
    const aggregate = byProduct.get(itemId) || { impressions: 0, campaignId: null };
    return {
      productId: itemId,
      title: titleByProductId.get(itemId) || "Untitled",
      impressions: aggregate.impressions,
      campaignId: aggregate.campaignId,
    };
  });

  const cpScore = spend > 0 ? Number(((confidenceOutcomes / spend) * 100).toFixed(2)) : 0;

  const period = {
    from: fromMs == null ? null : new Date(fromMs).toISOString().slice(0, 10),
    to: toMs == null ? null : new Date(toMs).toISOString().slice(0, 10),
  };

  return {
    retailerId,
    period,
    spend: Number(spend.toFixed(2)),
    impressions: Math.round(impressions),
    featuredImpressions: Math.round(featuredImpressions),
    confidenceOutcomes: Math.round(confidenceOutcomes),
    cpScore,
    bySegment: bySegmentRows,
    byCampaign: campaignRows.sort((a, b) => b.featuredImpressions - a.featuredImpressions),
    byProduct: byProductRows,
    generatedAt: new Date().toISOString(),
  };
}

function reportToCsv(report: Record<string, unknown>): string {
  const rows: string[] = [];
  rows.push([
    "retailerId",
    "campaignId",
    "campaignName",
    "status",
    "segmentId",
    "spend",
    "impressions",
    "featuredImpressions",
    "confidenceOutcomes",
    "cpScore",
  ].join(","));

  const retailerId = asTrimmedString(report.retailerId) || "";
  const campaignsRaw = Array.isArray(report.byCampaign) ? report.byCampaign : [];
  for (const entry of campaignsRaw) {
    const row = toRecord(entry);
    if (!row) continue;
    rows.push([
      escapeCsvCell(retailerId),
      escapeCsvCell(asTrimmedString(row.campaignId) || ""),
      escapeCsvCell(asTrimmedString(row.name) || ""),
      escapeCsvCell(asTrimmedString(row.status) || ""),
      escapeCsvCell(asTrimmedString(row.segmentId) || ""),
      escapeCsvCell(asFiniteNumber(row.spend) ?? 0),
      escapeCsvCell(asFiniteNumber(row.impressions) ?? 0),
      escapeCsvCell(asFiniteNumber(row.featuredImpressions) ?? 0),
      escapeCsvCell(asFiniteNumber(row.outcomes) ?? 0),
      escapeCsvCell(asFiniteNumber(row.cpScore) ?? 0),
    ].join(","));
  }

  rows.push([
    "TOTAL",
    "",
    "",
    "",
    "",
    escapeCsvCell(asFiniteNumber(report.spend) ?? 0),
    escapeCsvCell(asFiniteNumber(report.impressions) ?? 0),
    escapeCsvCell(asFiniteNumber(report.featuredImpressions) ?? 0),
    escapeCsvCell(asFiniteNumber(report.confidenceOutcomes) ?? 0),
    escapeCsvCell(asFiniteNumber(report.cpScore) ?? 0),
  ].join(","));

  return rows.join("\n");
}

export async function retailerCatalogGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const retailerIdParam = asTrimmedString(req.query.retailerId);
  const limitParam = parseInt(String(req.query.limit || DEFAULT_LIMIT), 10) || DEFAULT_LIMIT;
  const limit = Math.max(1, Math.min(limitParam, MAX_LIMIT));

  try {
    const access = await resolveRetailerAccess(db, user.uid, retailerIdParam);
    if (!access.ok) {
      res.status(access.status).json({ error: access.error });
      return;
    }

    const products = await loadRetailerCatalogRows(db, access.retailerId, limit);
    res.json({
      retailerId: access.retailerId,
      products,
      count: products.length,
    });
  } catch (error) {
    console.error("retailer_catalog_get_failed", error);
    res.status(500).json({ error: "Failed to load retailer catalog" });
  }
}

export async function retailerCatalogPatch(
  req: Request,
  res: Response,
  productId: string
): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const body = toBodyObject(req.body);
  const retailerIdParam = asTrimmedString(body.retailerId) || asTrimmedString(req.query.retailerId);
  const included = asBoolean(body.included);
  const reason = asTrimmedString(body.reason);

  if (included == null) {
    res.status(400).json({ error: "included (boolean) is required" });
    return;
  }

  try {
    const access = await resolveRetailerAccess(db, user.uid, retailerIdParam);
    if (!access.ok) {
      res.status(access.status).json({ error: access.error });
      return;
    }

    const itemData = await loadItemById(db, productId);
    if (!itemData) {
      res.status(404).json({ error: "Product not found" });
      return;
    }
    if (!itemBelongsToRetailer(itemData, access.retailerId)) {
      res.status(403).json({ error: "Product does not belong to this retailer" });
      return;
    }

    const now = FieldValue.serverTimestamp();
    const controlId = `${access.retailerId}_${productId}`;
    await db.collection("retailerCatalogControls").doc(controlId).set(
      {
        id: controlId,
        retailerId: access.retailerId,
        productId,
        included,
        reason: reason || null,
        updatedBy: user.uid,
        updatedAt: now,
        createdAt: now,
      },
      { merge: true }
    );

    const [itemDoc, goldDoc] = await Promise.all([
      db.collection("items").doc(productId).get(),
      db.collection("goldItems").doc(productId).get(),
    ]);
    const writeBatch = db.batch();
    if (itemDoc.exists) {
      writeBatch.update(itemDoc.ref, {
        retailerCatalogIncluded: included,
        retailerCatalogUpdatedAt: now,
      });
    }
    if (goldDoc.exists) {
      writeBatch.update(goldDoc.ref, {
        retailerCatalogIncluded: included,
        retailerCatalogUpdatedAt: now,
      });
    }
    await writeBatch.commit();

    res.json({
      success: true,
      retailerId: access.retailerId,
      productId,
      included,
      reason: reason || null,
    });
  } catch (error) {
    console.error("retailer_catalog_patch_failed", error);
    res.status(500).json({ error: "Failed to update catalog controls" });
  }
}

// ---------------------------------------------------------------------------
// Insight card types
// ---------------------------------------------------------------------------

type InsightPriority = "high" | "medium" | "low";

type InsightMetric = {
  label: string;
  value: string;
  unit?: string;
};

type InsightAction = {
  label: string;
  url: string;
};

type InsightCard = {
  id: string;
  type: string;
  priority: InsightPriority;
  headline: string;
  body: string;
  metric?: InsightMetric;
  action: InsightAction;
  createdAt: string;
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function insightId(prefix: string, suffix: string): string {
  return `${prefix}_${suffix}`.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function avgRound(values: number[]): number {
  if (values.length === 0) return 0;
  const sum = values.reduce((a, b) => a + b, 0);
  return Math.round(sum / values.length);
}

// ---------------------------------------------------------------------------
// Insight generators
// ---------------------------------------------------------------------------

async function buildLowConfidenceScoreInsight(
  db: admin.firestore.Firestore,
  retailerId: string
): Promise<InsightCard | null> {
  // Fetch active campaigns for this retailer to get segmentIds
  const campaignsSnap = await db
    .collection("campaigns")
    .where("retailerId", "==", retailerId)
    .where("status", "==", "active")
    .limit(200)
    .get();

  if (campaignsSnap.empty) return null;

  const segmentIds = [...new Set(campaignsSnap.docs.map((d) => (d.data() as Record<string, unknown>).segmentId as string).filter(Boolean))];
  if (segmentIds.length === 0) return null;

  // Fetch scores for those segments (30d window) with low scores
  const lowScoreThreshold = 45;
  const scorePromises = segmentIds.slice(0, 10).map((segmentId) =>
    db
      .collection("scores")
      .where("segmentId", "==", segmentId)
      .where("timeWindow", "==", "30d")
      .where("score", "<", lowScoreThreshold)
      .limit(100)
      .get()
  );

  const scoreSnapshots = await Promise.all(scorePromises);
  const lowScoringItems: { productId: string; score: number; impressions: number; saves: number }[] = [];

  for (const snap of scoreSnapshots) {
    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const productId = asTrimmedString(data.productId);
      const score = asFiniteNumber(data.score);
      const impressions = asFiniteNumber(data.impressions) ?? 0;
      const saves = asFiniteNumber(data.saves) ?? 0;
      if (!productId || score == null) continue;
      // Only include if has meaningful impressions but low saves ratio
      if (impressions >= 20 && saves < impressions * 0.05) {
        lowScoringItems.push({ productId, score, impressions, saves });
      }
    }
  }

  if (lowScoringItems.length === 0) return null;

  // Group by product to deduplicate
  const seen = new Set<string>();
  const unique = lowScoringItems.filter((item) => {
    if (seen.has(item.productId)) return false;
    seen.add(item.productId);
    return true;
  });

  const count = unique.length;
  const avgScore = avgRound(unique.map((i) => i.score));

  return {
    id: insightId("low_conf", retailerId),
    type: "low_confidence_score",
    priority: count >= 3 ? "high" : "medium",
    headline: count === 1
      ? "1 product has a red Confidence Score"
      : `${count} products have red Confidence Scores`,
    body: "These products are getting saves but few clicks. Review their pricing or images to improve performance.",
    metric: { label: "Avg score", value: String(avgScore), unit: "/100" },
    action: { label: "Review products", url: "/retailer/products?filter=low-score" },
    createdAt: new Date().toISOString(),
  };
}

async function buildCampaignUnderperformingInsight(
  db: admin.firestore.Firestore,
  retailerId: string
): Promise<InsightCard | null> {
  const campaignsSnap = await db
    .collection("campaigns")
    .where("retailerId", "==", retailerId)
    .where("status", "==", "active")
    .limit(100)
    .get();

  if (campaignsSnap.empty) return null;

  const underperforming: { id: string; name: string; fillRate: number; featuredImpressions: number }[] = [];

  for (const doc of campaignsSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const budget = asFiniteNumber(data.budget) ?? 0;
    const featuredImpressions = asFiniteNumber(data.featuredImpressions) ?? asFiniteNumber(data.impressions) ?? 0;
    const fillRate = budget > 0 ? (featuredImpressions / budget) * 100 : 0;
    if (budget > 0 && fillRate < 0.3) {
      underperforming.push({
        id: doc.id,
        name: asTrimmedString(data.name) || "Untitled campaign",
        fillRate: Math.round(fillRate * 10) / 10,
        featuredImpressions,
      });
    }
  }

  if (underperforming.length === 0) return null;

  // Sort by lowest fill rate
  underperforming.sort((a, b) => a.fillRate - b.fillRate);
  const worst = underperforming[0];

  return {
    id: insightId("underperform", worst.id),
    type: "campaign_underperforming",
    priority: worst.fillRate < 0.1 ? "high" : "medium",
    headline: `"${worst.name}" has low fill rate`,
    body: `This campaign has a ${worst.fillRate}% fill rate. Consider broadening your target segment or refreshing the product selection.`,
    metric: { label: "Fill rate", value: `${worst.fillRate}%`, unit: "" },
    action: { label: "View campaign", url: `/retailer/campaigns/${worst.id}` },
    createdAt: new Date().toISOString(),
  };
}

async function buildNewProductsNoTractionInsight(
  db: admin.firestore.Firestore,
  retailerId: string
): Promise<InsightCard | null> {
  const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
  const twoWeeksAgo = Date.now() - 2 * WEEK_MS;

  // Fetch items for this retailer ingested in the last 2 weeks
  const itemsSnap = await db
    .collection("items")
    .where("retailer", "==", retailerId)
    .where("lastUpdatedAt", ">=", admin.firestore.Timestamp.fromMillis(twoWeeksAgo))
    .limit(200)
    .get();

  if (itemsSnap.empty) return null;

  const itemIds = itemsSnap.docs.map((d) => d.id).slice(0, 100);

  // Fetch scores for these items (first segment, 7d window for recent traction)
  const scoresSnap = await db
    .collection("scores")
    .where("productId", "in", itemIds)
    .where("timeWindow", "==", "7d")
    .limit(200)
    .get();

  const noTraction: string[] = [];
  for (const doc of scoresSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const impressions = asFiniteNumber(data.impressions) ?? 0;
    if (impressions < 10) {
      const productId = asTrimmedString(data.productId);
      if (productId) noTraction.push(productId);
    }
  }

  if (noTraction.length === 0) return null;

  const count = noTraction.length;
  return {
    id: insightId("no_traction", retailerId),
    type: "new_products_no_traction",
    priority: count >= 5 ? "high" : "medium",
    headline: count === 1
      ? "1 newly added product isn't getting traction"
      : `${count} newly added products aren't getting traction`,
    body: "These products were added recently but have low impressions. Consider boosting them in a campaign or checking their images.",
    metric: { label: "Products <10 impressions", value: String(count), unit: "" },
    action: { label: "Review products", url: "/retailer/products?filter=new" },
    createdAt: new Date().toISOString(),
  };
}

async function buildBudgetPacingInsight(
  db: admin.firestore.Firestore,
  retailerId: string
): Promise<InsightCard | null> {
  const DAY_MS = 24 * 60 * 60 * 1000;
  const todayKey = toDateKeyUTC(Date.now());

  const campaignsSnap = await db
    .collection("campaigns")
    .where("retailerId", "==", retailerId)
    .where("status", "==", "active")
    .limit(80)
    .get();

  for (const doc of campaignsSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const budgetTotal = asFiniteNumber(data.budget);
    const budgetDaily = asFiniteNumber(data.budgetDaily);
    const endDate = data.endDate;

    // Check daily budget pacing first
    if (budgetDaily != null && budgetDaily > 0) {
      const todaySpend = sumNumberRecordWithinDateRange(
        toRecord(data.dailySpendByDate)?.[todayKey] ?? 0,
        null,
        null
      );
      if (todaySpend > budgetDaily * 0.85) {
        return {
          id: insightId("pacing_daily", doc.id),
          type: "budget_pacing",
          priority: todaySpend > budgetDaily ? "high" : "medium",
          headline: "Daily budget nearly exhausted",
          body: `This campaign has spent ${Math.round((todaySpend / budgetDaily) * 100)}% of its daily budget. Delivery may stop early today.`,
          metric: { label: "Daily budget used", value: `${Math.round((todaySpend / budgetDaily) * 100)}%`, unit: "" },
          action: { label: "Adjust budget", url: `/retailer/campaigns/${doc.id}` },
          createdAt: new Date().toISOString(),
        };
      }
    }

    // Check total budget pacing if endDate exists
    if (budgetTotal != null && budgetTotal > 0 && endDate) {
      const totalSpent = asFiniteNumber(data.budgetSpent) ?? 0;
      const endDateMs = toDateMillis(endDate);
      if (endDateMs != null) {
        const nowMs = Date.now();
        const totalDuration = endDateMs - ((data.createdAt as Timestamp)?.toMillis?.() ?? nowMs);
        const elapsed = nowMs - ((data.createdAt as Timestamp)?.toMillis?.() ?? nowMs);
        if (totalDuration > 0 && elapsed > 0) {
          const expectedSpend = (budgetTotal * elapsed) / totalDuration;
          if (totalSpent > expectedSpend * 1.1) {
            const daysLeft = Math.max(0, Math.ceil((endDateMs - nowMs) / DAY_MS));
            return {
              id: insightId("pacing_total", doc.id),
              type: "budget_pacing",
              priority: daysLeft <= 2 ? "high" : "medium",
              headline: "Campaign may run out of budget before end date",
              body: `With ${daysLeft} day${daysLeft !== 1 ? "s" : ""} left, this campaign is pacing faster than expected. Consider widening dates or adjusting budget.`,
              metric: { label: "Budget used", value: `${Math.round((totalSpent / budgetTotal) * 100)}%`, unit: "" },
              action: { label: "Adjust budget", url: `/retailer/campaigns/${doc.id}` },
              createdAt: new Date().toISOString(),
            };
          }
        }
      }
    }
  }

  return null;
}

async function buildTopPerformerInsight(
  db: admin.firestore.Firestore,
  retailerId: string
): Promise<InsightCard | null> {
  // Find campaigns with segment to get scores
  const campaignsSnap = await db
    .collection("campaigns")
    .where("retailerId", "==", retailerId)
    .where("status", "==", "active")
    .limit(50)
    .get();

  if (campaignsSnap.empty) return null;

  const segmentIds = [...new Set(campaignsSnap.docs
    .map((d) => (d.data() as Record<string, unknown>).segmentId as string)
    .filter(Boolean))];

  if (segmentIds.length === 0) return null;

  // Compare 7d vs 30d scores to find biggest improvers
  const score7dSnap = await db
    .collection("scores")
    .where("segmentId", "in", segmentIds.slice(0, 5))
    .where("timeWindow", "==", "7d")
    .orderBy("score", "desc")
    .limit(200)
    .get();

  const score30dSnap = await db
    .collection("scores")
    .where("segmentId", "in", segmentIds.slice(0, 5))
    .where("timeWindow", "==", "30d")
    .orderBy("score", "desc")
    .limit(200)
    .get();

  const score30dByProduct = new Map<string, number>();
  for (const doc of score30dSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const productId = asTrimmedString(data.productId);
    const score = asFiniteNumber(data.score);
    if (productId && score != null) {
      score30dByProduct.set(productId, score);
    }
  }

  let bestImprover: { productId: string; improvement: number; score7d: number } | null = null;
  for (const doc of score7dSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const productId = asTrimmedString(data.productId);
    const score7d = asFiniteNumber(data.score);
    if (!productId || score7d == null) continue;
    const score30d = score30dByProduct.get(productId) ?? score7d;
    const improvement = score7d - score30d;
    if (improvement > 5 && (!bestImprover || improvement > bestImprover.improvement)) {
      bestImprover = { productId, improvement, score7d };
    }
  }

  if (!bestImprover) return null;

  return {
    id: insightId("top_performer", bestImprover.productId),
    type: "top_performer",
    priority: "low",
    headline: "A product is trending up this week",
    body: `This product's Confidence Score increased by ${bestImprover.improvement.toFixed(0)} points recently. It's gaining traction — consider featuring it more prominently.`,
    metric: { label: "Confidence Score", value: String(Math.round(bestImprover.score7d)), unit: "/100" },
    action: { label: "View product", url: `/retailer/products?filter=top` },
    createdAt: new Date().toISOString(),
  };
}

async function buildNoActiveCampaignsInsight(
  db: admin.firestore.Firestore,
  retailerId: string
): Promise<InsightCard | null> {
  const campaignsSnap = await db
    .collection("campaigns")
    .where("retailerId", "==", retailerId)
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (!campaignsSnap.empty) return null;

  // Check if any campaigns exist at all (not just active)
  const anyCampaignsSnap = await db
    .collection("campaigns")
    .where("retailerId", "==", retailerId)
    .limit(1)
    .get();

  return {
    id: insightId("no_campaign", retailerId),
    type: "no_active_campaigns",
    priority: anyCampaignsSnap.empty ? "high" : "medium",
    headline: anyCampaignsSnap.empty
      ? "You don't have any campaigns yet"
      : "All your campaigns are paused",
    body: anyCampaignsSnap.empty
      ? "Create your first Featured campaign to start driving conversions."
      : "Activate a paused campaign or create a new one to continue featuring your products.",
    action: { label: "Create campaign", url: "/retailer/campaigns/new" },
    createdAt: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

export async function retailerInsightsGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const retailerIdParam = asTrimmedString(req.query.retailerId);
  try {
    const access = await resolveRetailerAccess(db, user.uid, retailerIdParam);
    if (!access.ok) {
      res.status(access.status).json({ error: access.error });
      return;
    }

    const retailerId = access.retailerId;

    // Run all insight generators in parallel
    const [
      lowConfInsight,
      underperformingInsight,
      noTractionInsight,
      pacingInsight,
      topPerformerInsight,
      noCampaignInsight,
    ] = await Promise.all([
      buildLowConfidenceScoreInsight(db, retailerId),
      buildCampaignUnderperformingInsight(db, retailerId),
      buildNewProductsNoTractionInsight(db, retailerId),
      buildBudgetPacingInsight(db, retailerId),
      buildTopPerformerInsight(db, retailerId),
      buildNoActiveCampaignsInsight(db, retailerId),
    ]);

    const insights: InsightCard[] = [
      lowConfInsight,
      underperformingInsight,
      noTractionInsight,
      pacingInsight,
      topPerformerInsight,
      noCampaignInsight,
    ].filter((i): i is InsightCard => i !== null);

    res.status(200).json({ insights });
  } catch (error) {
    console.error("retailer_insights_get_failed", error);
    res.status(500).json({ error: "Failed to load insights" });
  }
}

export async function retailerReportsGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const retailerIdParam = asTrimmedString(req.query.retailerId);
  const { fromMs, toMs } = parseDateRange(req);

  try {
    const access = await resolveRetailerAccess(db, user.uid, retailerIdParam);
    if (!access.ok) {
      res.status(access.status).json({ error: access.error });
      return;
    }

    const report = await buildRetailerReport(db, access.retailerId, fromMs, toMs);
    res.json(report);
  } catch (error) {
    console.error("retailer_reports_get_failed", error);
    res.status(500).json({ error: "Failed to load report" });
  }
}

export async function retailerReportsExportGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const retailerIdParam = asTrimmedString(req.query.retailerId);
  const { fromMs, toMs } = parseDateRange(req);

  try {
    const access = await resolveRetailerAccess(db, user.uid, retailerIdParam);
    if (!access.ok) {
      res.status(access.status).json({ error: access.error });
      return;
    }

    const report = await buildRetailerReport(db, access.retailerId, fromMs, toMs);
    const csv = reportToCsv(report);
    const fileTag = new Date().toISOString().slice(0, 10);
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="swiper_report_${access.retailerId}_${fileTag}.csv"`
    );
    res.status(200).send(csv);
  } catch (error) {
    console.error("retailer_reports_export_failed", error);
    res.status(500).json({ error: "Failed to export report" });
  }
}

export async function retailerReportsSharePost(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const body = toBodyObject(req.body);
  const retailerIdParam = asTrimmedString(body.retailerId) || asTrimmedString(req.query.retailerId);
  const dateFrom = asTrimmedString(body.dateFrom) || asTrimmedString(req.query.dateFrom);
  const dateTo = asTrimmedString(body.dateTo) || asTrimmedString(req.query.dateTo);
  const ttlDaysRaw = asFiniteNumber(body.ttlDays);
  const ttlDays =
    ttlDaysRaw != null ? Math.max(1, Math.min(Math.floor(ttlDaysRaw), 90)) : DEFAULT_REPORT_SHARE_TTL_DAYS;
  const fromMs = dateFrom ? Date.parse(`${dateFrom}T00:00:00.000Z`) : null;
  const toMs = dateTo ? Date.parse(`${dateTo}T23:59:59.999Z`) : null;

  try {
    const access = await resolveRetailerAccess(db, user.uid, retailerIdParam);
    if (!access.ok) {
      res.status(access.status).json({ error: access.error });
      return;
    }

    const report = await buildRetailerReport(
      db,
      access.retailerId,
      Number.isFinite(fromMs ?? Number.NaN) ? (fromMs as number) : null,
      Number.isFinite(toMs ?? Number.NaN) ? (toMs as number) : null
    );
    const token = randomUUID().replace(/-/g, "");
    const now = Date.now();
    const expiresAtMs = now + ttlDays * 24 * 60 * 60 * 1000;

    await db.collection("retailerReportShares").doc(token).set({
      id: token,
      token,
      retailerId: access.retailerId,
      report,
      createdBy: user.uid,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(expiresAtMs),
    });

    const host = req.get("host");
    const protocolHeader = req.headers["x-forwarded-proto"];
    const protocol = Array.isArray(protocolHeader)
      ? protocolHeader[0]
      : protocolHeader || req.protocol || "https";
    const sharePath = `/api/retailer/reports/share/${token}`;
    const shareUrl = host ? `${protocol}://${host}${sharePath}` : sharePath;

    res.json({
      token,
      sharePath,
      shareUrl,
      expiresAt: new Date(expiresAtMs).toISOString(),
      retailerId: access.retailerId,
    });
  } catch (error) {
    console.error("retailer_reports_share_post_failed", error);
    res.status(500).json({ error: "Failed to create share link" });
  }
}

export async function retailerReportsShareGet(
  req: Request,
  res: Response,
  token: string
): Promise<void> {
  const db = admin.firestore();
  try {
    const doc = await db.collection("retailerReportShares").doc(token).get();
    if (!doc.exists) {
      res.status(404).json({ error: "Share link not found" });
      return;
    }

    const data = (doc.data() || {}) as Record<string, unknown>;
    const expiresAtMs = toDateMillis(data.expiresAt);
    if (expiresAtMs != null && Date.now() > expiresAtMs) {
      res.status(410).json({ error: "Share link has expired" });
      return;
    }

    res.json({
      token,
      retailerId: asTrimmedString(data.retailerId),
      report: toRecord(data.report) || {},
      expiresAt: formatTimestamp(data.expiresAt),
    });
  } catch (error) {
    console.error("retailer_reports_share_get_failed", error);
    res.status(500).json({ error: "Failed to read share link" });
  }
}
