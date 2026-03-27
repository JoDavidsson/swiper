import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import { sessionPost } from "./session";
import { deckGet } from "./deck";
import { itemsBatchGet } from "./items_batch";
import { swipePost } from "./swipe";
import { likesTogglePost } from "./likes";
import { likesGet } from "./likes_get";
import { shortlistsCreatePost, shortlistsByTokenGet } from "./shortlists";
import { eventsPost } from "./events";
import { eventsBatchPost } from "./events_batch";
import { adminVerifyPost } from "./admin";
import { adminStatsGet } from "./admin_stats";
import { 
  adminSourcesGet, 
  adminSourcesPost, 
  adminSourceGet, 
  adminSourcePut, 
  adminSourceDelete,
  adminSourcesPreview,
  adminSourcesCreateWithDiscovery,
} from "./admin_sources";
import { adminRunsGet, adminRunGet } from "./admin_runs";
import { adminRunTriggerPost, adminRunBatchPost, adminReExtractImagesPost, adminImageHealthGet, adminExplainGet, adminProxyToSupplyEngine, adminStopCrawlPost } from "./admin_run_trigger";
import { adminQaGet } from "./admin_qa";
import { adminItemsGet } from "./admin_items";
import {
  allowLegacyAdminPassword,
  isLegacyAdminPasswordValid,
  requireAdminAuth,
} from "./admin_auth";
import { onboardingCuratedSofasGet } from "./onboarding_curated";
import { onboardingPicksPost, onboardingPicksGet } from "./onboarding_picks";
import { onboardingV2Post, onboardingV2Get } from "./onboarding_v2";
import { adminCuratedSofasGet, adminCuratedSofasPost, adminCuratedSofasDelete, adminCuratedSofasReorder } from "./admin_curated";
import { adminValidateImagesPost, adminCreativeHealthStatsGet } from "./admin_image_validation";
import {
  adminReviewActionPost,
  adminReviewQueueGet,
  adminSamplingCandidatesGet,
  adminTrainCategorizerPost,
} from "./admin_review";
import { imageProxyGet, imageMetaGet } from "./image_proxy";
import { authLinkSessionPost, authMeGet } from "./auth";
import {
  decisionRoomsPost,
  decisionRoomsGet,
  decisionRoomsVotePost,
  decisionRoomsCommentPost,
  decisionRoomsCommentsGet,
  decisionRoomsSuggestPost,
  decisionRoomsFinalistsPost,
} from "./decision_rooms";
import {
  adminRetailersPost,
  adminRetailersGet,
  retailersGetById,
  adminRetailersPatch,
  retailersClaimPost,
  retailerMeGet,
} from "./retailers";
import {
  segmentsTemplatesGet,
  segmentsPost,
  segmentsGet,
  segmentsGetById,
  segmentsPatch,
  segmentsDelete,
} from "./segments";
import {
  retailerCampaignsPost,
  retailerCampaignsGet,
  retailerCampaignsGetById,
  retailerCampaignsPatch,
  retailerCampaignsPause,
  retailerCampaignsActivate,
  retailerCampaignsRecommendPost,
  retailerCampaignsDelete,
} from "./campaigns";
import {
  scoresGet,
  scoresGetByProduct,
  adminScoresSummaryGet,
  adminScoresRecalculatePost,
} from "./scores";
import {
  retailerCatalogGet,
  retailerCatalogPatch,
  retailerInsightsGet,
  retailerReportsGet,
  retailerReportsExportGet,
  retailerReportsSharePost,
  retailerReportsShareGet,
} from "./retailer_console";
import {
  adminGovernanceGet,
  adminGovernancePatch,
  adminGovernanceReset,
} from "./admin/governance";
import {
  adminRetailerGovernanceGet,
  adminRetailerGovernancePatch,
} from "./admin/retailerGovernance";

export async function apiHandler(req: Request, res: Response): Promise<void> {
  // Emulator: path can be /project/region/api/... ; prod/hosted: /api/... or /items/deck. Normalize to e.g. "session" or "items/deck".
  let path = (req.path || "")
    .replace(/^\/[^/]+\/[^/]+\/api\/?/, "") // strip /projectId/region/api only
    .replace(/^\/api\/?/, "")
    .replace(/^api\/?/, "")
    .replace(/\/$/, "")
    .replace(/^\//, "");
  const method = req.method;

  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Session-Id, X-Admin-Password",
  };

  if (method === "OPTIONS") {
    res.set(corsHeaders).status(204).send("");
    return;
  }

  res.set(corsHeaders);

  try {
    if (method === "POST" && path === "session") {
      await sessionPost(req, res);
      return;
    }
    if (method === "GET" && path === "items/deck") {
      await deckGet(req, res);
      return;
    }
    if (method === "GET" && path === "items/batch") {
      await itemsBatchGet(req, res);
      return;
    }
    if (method === "POST" && path === "swipe") {
      await swipePost(req, res);
      return;
    }
    if (method === "GET" && path === "likes") {
      await likesGet(req, res);
      return;
    }
    if (method === "POST" && path === "likes/toggle") {
      await likesTogglePost(req, res);
      return;
    }
    if (method === "POST" && path === "shortlists/create") {
      await shortlistsCreatePost(req, res);
      return;
    }
    if (method === "GET" && path.startsWith("shortlists/byToken/")) {
      const token = path.replace("shortlists/byToken/", "");
      await shortlistsByTokenGet(req, res, token);
      return;
    }
    if (method === "POST" && path === "events") {
      await eventsPost(req, res);
      return;
    }
    if (method === "POST" && path === "events/batch") {
      await eventsBatchPost(req, res);
      return;
    }

    // User auth routes
    if (method === "POST" && path === "auth/link-session") {
      await authLinkSessionPost(req, res);
      return;
    }
    if (method === "GET" && path === "auth/me") {
      await authMeGet(req, res);
      return;
    }

    // Decision Room routes
    if (method === "POST" && path === "decision-rooms") {
      await decisionRoomsPost(req, res);
      return;
    }
    if (method === "GET" && path.match(/^decision-rooms\/[^/]+$/)) {
      const roomId = path.replace("decision-rooms/", "");
      await decisionRoomsGet(req, res, roomId);
      return;
    }
    if (method === "POST" && path.match(/^decision-rooms\/[^/]+\/vote$/)) {
      const roomId = path.replace("decision-rooms/", "").replace("/vote", "");
      await decisionRoomsVotePost(req, res, roomId);
      return;
    }
    if (method === "POST" && path.match(/^decision-rooms\/[^/]+\/comment$/)) {
      const roomId = path.replace("decision-rooms/", "").replace("/comment", "");
      await decisionRoomsCommentPost(req, res, roomId);
      return;
    }
    if (method === "GET" && path.match(/^decision-rooms\/[^/]+\/comments$/)) {
      const roomId = path.replace("decision-rooms/", "").replace("/comments", "");
      await decisionRoomsCommentsGet(req, res, roomId);
      return;
    }
    if (method === "POST" && path.match(/^decision-rooms\/[^/]+\/suggest$/)) {
      const roomId = path.replace("decision-rooms/", "").replace("/suggest", "");
      await decisionRoomsSuggestPost(req, res, roomId);
      return;
    }
    if (method === "POST" && path.match(/^decision-rooms\/[^/]+\/finalists$/)) {
      const roomId = path.replace("decision-rooms/", "").replace("/finalists", "");
      await decisionRoomsFinalistsPost(req, res, roomId);
      return;
    }

    // Admin routes (except verify): require Bearer token + allowlist OR X-Admin-Password (password gate)
    if (path.startsWith("admin/") && !(method === "POST" && path === "admin/verify")) {
      const adminUser = await requireAdminAuth(req);
      const passwordHeader = req.headers["x-admin-password"] as string | undefined;
      const passwordOk = allowLegacyAdminPassword() && isLegacyAdminPasswordValid(passwordHeader);
      if (!adminUser && !passwordOk) {
        const message = allowLegacyAdminPassword() ?
          "Unauthorized. Use admin password or Sign in with Google." :
          "Unauthorized. Use Sign in with Google with an allowlisted admin account.";
        res.status(401).json({ error: message });
        return;
      }
    }
    if (method === "POST" && path === "admin/verify") {
      await adminVerifyPost(req, res);
      return;
    }
    if (method === "GET" && path === "admin/stats") {
      await adminStatsGet(req, res);
      return;
    }
    if (method === "GET" && path === "admin/sources") {
      await adminSourcesGet(req, res);
      return;
    }
    if (method === "POST" && path === "admin/sources") {
      await adminSourcesPost(req, res);
      return;
    }
    // New auto-discovery endpoints (must come before generic GET/PUT/DELETE)
    if (method === "POST" && path === "admin/sources/preview") {
      await adminSourcesPreview(req, res);
      return;
    }
    if (method === "POST" && path === "admin/sources/create-with-discovery") {
      await adminSourcesCreateWithDiscovery(req, res);
      return;
    }
    if (method === "GET" && path.startsWith("admin/sources/")) {
      const sourceId = path.replace("admin/sources/", "");
      await adminSourceGet(req, res, sourceId);
      return;
    }
    if (method === "PUT" && path.startsWith("admin/sources/")) {
      const sourceId = path.replace("admin/sources/", "");
      await adminSourcePut(req, res, sourceId);
      return;
    }
    if (method === "DELETE" && path.startsWith("admin/sources/")) {
      const sourceId = path.replace("admin/sources/", "");
      await adminSourceDelete(req, res, sourceId);
      return;
    }
    if (method === "GET" && path === "admin/runs") {
      await adminRunsGet(req, res);
      return;
    }
    if (method === "GET" && path.startsWith("admin/runs/")) {
      const runId = path.replace("admin/runs/", "");
      await adminRunGet(req, res, runId);
      return;
    }
    if (method === "POST" && path === "admin/run") {
      await adminRunTriggerPost(req, res);
      return;
    }
    if (method === "POST" && path === "admin/run-batch") {
      await adminRunBatchPost(req, res);
      return;
    }
    if (method === "POST" && path === "admin/stop-crawl") {
      await adminStopCrawlPost(req, res);
      return;
    }
    if (method === "POST" && path === "admin/re-extract-images") {
      await adminReExtractImagesPost(req, res);
      return;
    }
    if (method === "GET" && path === "admin/image-health") {
      await adminImageHealthGet(req, res);
      return;
    }
    // Sorting engine proxy endpoints (EPIC C)
    if (method === "POST" && path === "admin/classify") {
      await adminProxyToSupplyEngine(req, res, "/classify", "POST");
      return;
    }
    if (method === "GET" && path === "admin/classification-stats") {
      await adminProxyToSupplyEngine(req, res, "/classification-stats", "GET");
      return;
    }
    // Review queue proxy endpoints (EPIC D)
    if (method === "GET" && path === "admin/review-queue") {
      await adminReviewQueueGet(req, res);
      return;
    }
    if (method === "POST" && path === "admin/review-action") {
      await adminReviewActionPost(req, res);
      return;
    }
    if (method === "GET" && path === "admin/sampling-candidates") {
      await adminSamplingCandidatesGet(req, res);
      return;
    }
    if (method === "POST" && path === "admin/train-categorizer") {
      await adminTrainCategorizerPost(req, res);
      return;
    }
    if (method === "POST" && path === "admin/calibrate") {
      await adminProxyToSupplyEngine(req, res, "/calibrate", "POST");
      return;
    }
    if (method === "GET" && path === "admin/evaluation-report") {
      await adminProxyToSupplyEngine(req, res, "/evaluation-report", "GET");
      return;
    }
    // DevOps proxy endpoints (EPIC F)
    if (method === "POST" && path === "admin/retention-cleanup") {
      await adminProxyToSupplyEngine(req, res, "/retention-cleanup", "POST");
      return;
    }
    if (method === "GET" && path === "admin/domain-dashboard") {
      await adminProxyToSupplyEngine(req, res, "/domain-dashboard", "GET");
      return;
    }
    if (method === "POST" && path === "admin/drift-check") {
      await adminProxyToSupplyEngine(req, res, "/drift-check", "POST");
      return;
    }
    if (method === "POST" && path === "admin/kill-switch") {
      await adminProxyToSupplyEngine(req, res, "/kill-switch", "POST");
      return;
    }
    if (method === "GET" && path === "admin/cost-telemetry") {
      await adminProxyToSupplyEngine(req, res, "/cost-telemetry", "GET");
      return;
    }
    if (method === "GET" && path === "admin/qa") {
      await adminQaGet(req, res);
      return;
    }
    if (method === "GET" && path === "admin/items") {
      await adminItemsGet(req, res);
      return;
    }
    // E4: Explainability – why was an item accepted/rejected
    if (method === "GET" && path.match(/^admin\/explain\/[^/]+$/)) {
      const itemId = path.replace("admin/explain/", "");
      await adminExplainGet(req, res, itemId);
      return;
    }
    // Admin curated sofas routes
    if (method === "GET" && path === "admin/curated-sofas") {
      await adminCuratedSofasGet(req, res);
      return;
    }
    if (method === "POST" && path === "admin/curated-sofas") {
      await adminCuratedSofasPost(req, res);
      return;
    }
    if (method === "DELETE" && path.startsWith("admin/curated-sofas/")) {
      const itemId = path.replace("admin/curated-sofas/", "");
      await adminCuratedSofasDelete(req, res, itemId);
      return;
    }
    if (method === "PUT" && path === "admin/curated-sofas/reorder") {
      await adminCuratedSofasReorder(req, res);
      return;
    }
    // Admin image validation routes
    if (method === "POST" && path === "admin/validate-images") {
      await adminValidateImagesPost(req, res);
      return;
    }
    if (method === "GET" && path === "admin/creative-health-stats") {
      await adminCreativeHealthStatsGet(req, res);
      return;
    }

    // Image proxy (for serving external images through our domain)
    if (method === "GET" && path === "image-proxy") {
      await imageProxyGet(req, res);
      return;
    }
    
    // Image metadata (for validation without full download)
    if (method === "GET" && path === "image-meta") {
      await imageMetaGet(req, res);
      return;
    }

    // Public onboarding routes
    if (method === "GET" && path === "onboarding/curated-sofas") {
      await onboardingCuratedSofasGet(req, res);
      return;
    }
    if (method === "POST" && path === "onboarding/picks") {
      await onboardingPicksPost(req, res);
      return;
    }
    if (method === "GET" && path === "onboarding/picks") {
      await onboardingPicksGet(req, res);
      return;
    }
    if (method === "POST" && path === "onboarding/v2") {
      await onboardingV2Post(req, res);
      return;
    }
    if (method === "GET" && path === "onboarding/v2") {
      await onboardingV2Get(req, res);
      return;
    }

    // Retailer routes (admin)
    if (method === "POST" && path === "admin/retailers") {
      await adminRetailersPost(req, res);
      return;
    }
    if (method === "GET" && path === "admin/retailers") {
      await adminRetailersGet(req, res);
      return;
    }
    if (method === "PATCH" && path.match(/^admin\/retailers\/[^/]+$/)) {
      const retailerId = path.replace("admin/retailers/", "");
      await adminRetailersPatch(req, res, retailerId);
      return;
    }
    // Retailer routes (user)
    if (method === "GET" && path === "retailer/me") {
      await retailerMeGet(req, res);
      return;
    }
    if (method === "GET" && path === "retailer/catalog") {
      await retailerCatalogGet(req, res);
      return;
    }
    if (method === "PATCH" && path.match(/^retailer\/catalog\/[^/]+$/)) {
      const productId = path.replace("retailer/catalog/", "");
      await retailerCatalogPatch(req, res, productId);
      return;
    }
    if (method === "GET" && path === "retailer/insights") {
      await retailerInsightsGet(req, res);
      return;
    }
    if (method === "GET" && path === "retailer/reports") {
      await retailerReportsGet(req, res);
      return;
    }
    if (method === "GET" && path === "retailer/reports/export") {
      await retailerReportsExportGet(req, res);
      return;
    }
    if (method === "POST" && path === "retailer/reports/share") {
      await retailerReportsSharePost(req, res);
      return;
    }
    if (method === "GET" && path.match(/^retailer\/reports\/share\/[^/]+$/)) {
      const token = path.replace("retailer/reports/share/", "");
      await retailerReportsShareGet(req, res, token);
      return;
    }
    if (method === "GET" && path.match(/^retailers\/[^/]+$/)) {
      const retailerId = path.replace("retailers/", "");
      await retailersGetById(req, res, retailerId);
      return;
    }
    if (method === "POST" && path.match(/^retailers\/[^/]+\/claim$/)) {
      const retailerId = path.replace("retailers/", "").replace("/claim", "");
      await retailersClaimPost(req, res, retailerId);
      return;
    }

    // Segment routes
    if (method === "GET" && path === "segments/templates") {
      await segmentsTemplatesGet(req, res);
      return;
    }
    if (method === "POST" && path === "segments") {
      await segmentsPost(req, res);
      return;
    }
    if (method === "GET" && path === "segments") {
      await segmentsGet(req, res);
      return;
    }
    if (method === "GET" && path.match(/^segments\/[^/]+$/) && !path.includes("templates")) {
      const segmentId = path.replace("segments/", "");
      await segmentsGetById(req, res, segmentId);
      return;
    }
    if (method === "PATCH" && path.match(/^segments\/[^/]+$/)) {
      const segmentId = path.replace("segments/", "");
      await segmentsPatch(req, res, segmentId);
      return;
    }
    if (method === "DELETE" && path.match(/^segments\/[^/]+$/)) {
      const segmentId = path.replace("segments/", "");
      await segmentsDelete(req, res, segmentId);
      return;
    }

    // Campaign routes (retailer)
    if (method === "POST" && path === "retailer/campaigns") {
      await retailerCampaignsPost(req, res);
      return;
    }
    if (method === "GET" && path === "retailer/campaigns") {
      await retailerCampaignsGet(req, res);
      return;
    }
    if (method === "GET" && path.match(/^retailer\/campaigns\/[^/]+$/) && !path.includes("pause") && !path.includes("activate")) {
      const campaignId = path.replace("retailer/campaigns/", "");
      await retailerCampaignsGetById(req, res, campaignId);
      return;
    }
    if (method === "PATCH" && path.match(/^retailer\/campaigns\/[^/]+$/)) {
      const campaignId = path.replace("retailer/campaigns/", "");
      await retailerCampaignsPatch(req, res, campaignId);
      return;
    }
    if (method === "POST" && path.match(/^retailer\/campaigns\/[^/]+\/pause$/)) {
      const campaignId = path.replace("retailer/campaigns/", "").replace("/pause", "");
      await retailerCampaignsPause(req, res, campaignId);
      return;
    }
    if (method === "POST" && path.match(/^retailer\/campaigns\/[^/]+\/activate$/)) {
      const campaignId = path.replace("retailer/campaigns/", "").replace("/activate", "");
      await retailerCampaignsActivate(req, res, campaignId);
      return;
    }
    if (method === "POST" && path.match(/^retailer\/campaigns\/[^/]+\/recommend$/)) {
      const campaignId = path.replace("retailer/campaigns/", "").replace("/recommend", "");
      await retailerCampaignsRecommendPost(req, res, campaignId);
      return;
    }
    if (method === "DELETE" && path.match(/^retailer\/campaigns\/[^/]+$/)) {
      const campaignId = path.replace("retailer/campaigns/", "");
      await retailerCampaignsDelete(req, res, campaignId);
      return;
    }

    // Score routes
    if (method === "GET" && path === "scores") {
      await scoresGet(req, res);
      return;
    }
    if (method === "GET" && path.match(/^scores\/[^/]+$/)) {
      const productId = path.replace("scores/", "");
      await scoresGetByProduct(req, res, productId);
      return;
    }
    if (method === "GET" && path === "admin/scores/summary") {
      await adminScoresSummaryGet(req, res);
      return;
    }
    if (method === "POST" && path === "admin/scores/recalculate") {
      await adminScoresRecalculatePost(req, res);
      return;
    }

    // Governance routes (admin)
    if (method === "GET" && path === "admin/governance") {
      await adminGovernanceGet(req, res);
      return;
    }
    if (method === "PATCH" && path === "admin/governance") {
      await adminGovernancePatch(req, res);
      return;
    }
    if (method === "POST" && path === "admin/governance/reset") {
      await adminGovernanceReset(req, res);
      return;
    }
    if (method === "GET" && path.match(/^admin\/retailers\/[^/]+\/governance$/)) {
      const retailerId = path.replace("admin/retailers/", "").replace("/governance", "");
      await adminRetailerGovernanceGet(req, res, retailerId);
      return;
    }
    if (method === "PATCH" && path.match(/^admin\/retailers\/[^/]+\/governance$/)) {
      const retailerId = path.replace("admin/retailers/", "").replace("/governance", "");
      await adminRetailerGovernancePatch(req, res, retailerId);
      return;
    }

    res.status(404).json({ error: "Not found" });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e) });
  }
}
