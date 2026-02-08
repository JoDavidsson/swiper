import { Request, Response } from "express";
import * as admin from "firebase-admin";
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

    rows.push({
      id: itemId,
      title: asTrimmedString(itemData.title) || "Untitled",
      priceAmount: asFiniteNumber(itemData.priceAmount),
      priceCurrency: asTrimmedString(itemData.priceCurrency) || "SEK",
      images: Array.isArray(itemData.images) ? itemData.images : [],
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

  const topProductDocs = await db.getAll(
    ...topProductIds.map((itemId) => db.collection("items").doc(itemId))
  );
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

    const now = admin.firestore.FieldValue.serverTimestamp();
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

    const report = await buildRetailerReport(db, access.retailerId, null, null);
    const byCampaignRaw = Array.isArray(report.byCampaign) ? report.byCampaign : [];
    const byCampaign = byCampaignRaw
      .map((entry) => toRecord(entry))
      .filter((entry): entry is Record<string, unknown> => entry != null);
    const todayKey = toDateKeyUTC(Date.now());

    const insights: Array<Record<string, unknown>> = [];

    if (byCampaign.length > 0) {
      const winner = byCampaign.reduce((a, b) =>
        (asFiniteNumber(a.cpScore) ?? 0) >= (asFiniteNumber(b.cpScore) ?? 0) ? a : b
      );
      insights.push({
        id: `winner_${asTrimmedString(winner.campaignId) || "unknown"}`,
        type: "winner",
        severity: "positive",
        title: "Top performing campaign",
        body: `${
          asTrimmedString(winner.name) || "Campaign"
        } is currently leading with CPScore ${
          asFiniteNumber(winner.cpScore)?.toFixed(2) ?? "0.00"
        }.`,
        ctaLabel: "Open campaign",
        campaignId: asTrimmedString(winner.campaignId),
      });
    }

    const lowMomentum = byCampaign.filter((campaign) => {
      const status = asTrimmedString(campaign.status);
      const campaignImpressions = asFiniteNumber(campaign.featuredImpressions) ?? 0;
      return status == "active" && campaignImpressions < 25;
    });
    if (lowMomentum.length > 0) {
      const campaign = lowMomentum[0];
      insights.push({
        id: `needs_help_${asTrimmedString(campaign.campaignId) || "unknown"}`,
        type: "needs_help",
        severity: "warning",
        title: "Campaign needs attention",
        body: `${
          asTrimmedString(campaign.name) || "Campaign"
        } is active but has low featured reach. Consider refreshing product set or broadening segment.`,
        ctaLabel: "Refresh products",
        campaignId: asTrimmedString(campaign.campaignId),
      });
    }

    const campaignsSnap = await db
      .collection("campaigns")
      .where("retailerId", "==", access.retailerId)
      .where("status", "==", "active")
      .limit(80)
      .get();
    const pacingRiskCampaign = campaignsSnap.docs
      .map((doc) => ({ id: doc.id, data: (doc.data() || {}) as Record<string, unknown> }))
      .find(({ data }) => {
        const budgetDaily = asFiniteNumber(data.budgetDaily);
        if (budgetDaily == null || budgetDaily <= 0) return false;
        const spentToday = sumNumberRecordWithinDateRange(
          toRecord(data.dailySpendByDate)?.[todayKey] == null
            ? {}
            : { [todayKey]: toRecord(data.dailySpendByDate)?.[todayKey] },
          null,
          null
        );
        return spentToday > budgetDaily * 0.9;
      });
    if (pacingRiskCampaign) {
      insights.push({
        id: `pacing_${pacingRiskCampaign.id}`,
        type: "anomaly",
        severity: "warning",
        title: "Daily pacing risk",
        body: `${
          asTrimmedString(pacingRiskCampaign.data.name) || "Campaign"
        } is close to today's daily budget cap. Lower frequency or widen dates to sustain delivery.`,
        ctaLabel: "Adjust budget",
        campaignId: pacingRiskCampaign.id,
      });
    }

    const byProductRaw = Array.isArray(report.byProduct) ? report.byProduct : [];
    if (byProductRaw.length > 0) {
      const top = toRecord(byProductRaw[0]);
      if (top) {
        insights.push({
          id: `trend_${asTrimmedString(top.productId) || "unknown"}`,
          type: "trend",
          severity: "neutral",
          title: "Demand trend spotted",
          body: `${
            asTrimmedString(top.title) || "A product"
          } is currently your most exposed featured product. Consider adding sibling variants to capture more intent.`,
          ctaLabel: "Open catalog",
          productId: asTrimmedString(top.productId),
        });
      }
    }

    res.json({
      retailerId: access.retailerId,
      generatedAt: new Date().toISOString(),
      insights,
    });
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
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
