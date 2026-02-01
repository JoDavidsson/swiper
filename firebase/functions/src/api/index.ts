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
import { adminVerifyPost } from "./admin";
import { adminStatsGet } from "./admin_stats";
import { adminSourcesGet, adminSourcesPost, adminSourceGet, adminSourcePut, adminSourceDelete } from "./admin_sources";
import { adminRunsGet, adminRunGet } from "./admin_runs";
import { adminRunTriggerPost } from "./admin_run_trigger";
import { adminQaGet } from "./admin_qa";

export async function apiHandler(req: Request, res: Response): Promise<void> {
  const path = (req.path || "").replace(/^\/api\/?/, "").replace(/\/$/, "");
  const method = req.method;

  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Session-Id",
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
    if (method === "GET" && path === "admin/qa") {
      await adminQaGet(req, res);
      return;
    }

    res.status(404).json({ error: "Not found" });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e) });
  }
}
