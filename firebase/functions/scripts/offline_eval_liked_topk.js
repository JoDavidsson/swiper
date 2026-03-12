#!/usr/bin/env node
"use strict";

/**
 * Offline eval metric runner for autoresearch.
 *
 * Computes Liked-in-top-K style coverage for synthetic sessions by:
 * 1) Reading liked items from Firestore `likes` for source sessions.
 * 2) Materializing fresh eval sessions with copied preference weights.
 *    (avoids seen-item suppression from historical swipes/likes)
 * 3) Requesting served deck itemIds from the deck API for eval sessions.
 * 4) Computing per-source-session coverage = |liked ∩ served_union| / |liked|.
 * 5) Reporting average across sessions with at least one like.
 *
 * Requires FIRESTORE_EMULATOR_HOST to be set.
 */

const admin = require("firebase-admin");

const DEFAULT_PROJECT_ID = process.env.GCLOUD_PROJECT || "swiper-95482";
const DEFAULT_BASE_URL = `http://127.0.0.1:5002/${DEFAULT_PROJECT_ID}/europe-west1/api/items/deck`;

function parseArgs(argv) {
  const args = {
    sessionsPrefix: "synth_",
    maxSessions: 250,
    limit: 20,
    requestsPerSession: 1,
    baseUrl: DEFAULT_BASE_URL,
    concurrency: 8,
    evalSessionPrefix: "offline_eval_",
    groundTruthMode: process.env.EVAL_GROUND_TRUTH_MODE || "oracle_preference",
    oracleTopK: Math.max(1, Number.parseInt(process.env.EVAL_ORACLE_TOP_K || "30", 10)),
  };

  for (let i = 2; i < argv.length; i += 1) {
    const key = argv[i];
    const next = argv[i + 1];
    if (!next) continue;

    if (key === "--sessions-prefix") {
      args.sessionsPrefix = String(next);
      i += 1;
    } else if (key === "--max-sessions") {
      args.maxSessions = Math.max(1, Number.parseInt(next, 10) || args.maxSessions);
      i += 1;
    } else if (key === "--limit") {
      args.limit = Math.max(1, Number.parseInt(next, 10) || args.limit);
      i += 1;
    } else if (key === "--requests-per-session") {
      args.requestsPerSession = Math.max(1, Number.parseInt(next, 10) || args.requestsPerSession);
      i += 1;
    } else if (key === "--base-url") {
      args.baseUrl = String(next);
      i += 1;
    } else if (key === "--concurrency") {
      args.concurrency = Math.max(1, Number.parseInt(next, 10) || args.concurrency);
      i += 1;
    } else if (key === "--eval-session-prefix") {
      args.evalSessionPrefix = String(next);
      i += 1;
    } else if (key === "--ground-truth-mode") {
      args.groundTruthMode = String(next);
      i += 1;
    } else if (key === "--oracle-top-k") {
      args.oracleTopK = Math.max(1, Number.parseInt(next, 10) || args.oracleTopK);
      i += 1;
    }
  }

  return args;
}

function startsWithPrefix(value, prefix) {
  return typeof value === "string" && value.startsWith(prefix);
}

async function fetchDeckItemIds(baseUrl, sessionId, limit) {
  const url = new URL(baseUrl);
  url.searchParams.set("sessionId", sessionId);
  url.searchParams.set("limit", String(limit));

  const response = await fetch(url.toString(), { headers: { accept: "application/json" } });
  if (!response.ok) {
    throw new Error(`deck_api_http_${response.status}`);
  }
  const payload = await response.json();

  if (Array.isArray(payload?.rank?.itemIds)) {
    return payload.rank.itemIds.filter((id) => typeof id === "string" && id.length > 0);
  }

  if (Array.isArray(payload?.items)) {
    return payload.items
      .map((item) => (item && typeof item.id === "string" ? item.id : ""))
      .filter((id) => id.length > 0);
  }

  throw new Error("deck_api_missing_item_ids");
}

async function runWithConcurrency(values, concurrency, worker) {
  if (values.length === 0) return [];
  const results = new Array(values.length);
  let cursor = 0;

  const workers = Array.from({ length: Math.min(concurrency, values.length) }, async () => {
    while (true) {
      const index = cursor;
      cursor += 1;
      if (index >= values.length) return;
      results[index] = await worker(values[index], index);
    }
  });

  await Promise.all(workers);
  return results;
}

async function cleanupEvalSessions(db, evalSessionPrefix) {
  const FieldPath = admin.firestore.FieldPath;
  let deleted = 0;

  while (true) {
    const snap = await db
      .collection("anonSessions")
      .where(FieldPath.documentId(), ">=", evalSessionPrefix)
      .where(FieldPath.documentId(), "<", `${evalSessionPrefix}\uf8ff`)
      .limit(100)
      .get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      if (typeof db.recursiveDelete === "function") {
        await db.recursiveDelete(doc.ref);
      } else {
        await doc.ref.delete();
      }
      deleted += 1;
    }
  }

  return deleted;
}

function scoreByPreferenceWeights(item, weights) {
  let score = 0;

  const styleTags = Array.isArray(item.styleTags) ? item.styleTags : [];
  for (const tag of styleTags) {
    if (typeof tag === "string") score += Number(weights[tag] || 0);
  }

  if (typeof item.material === "string") score += Number(weights[`material:${item.material}`] || 0);
  if (typeof item.colorFamily === "string") score += Number(weights[`color:${item.colorFamily}`] || 0);
  if (typeof item.sizeClass === "string") score += Number(weights[`size:${item.sizeClass}`] || 0);

  return score;
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error("offline_eval_status: error");
    console.error("offline_eval_error: FIRESTORE_EMULATOR_HOST is required");
    process.exit(1);
  }

  const args = parseArgs(process.argv);

  if (!admin.apps.length) {
    admin.initializeApp({ projectId: DEFAULT_PROJECT_ID });
  }
  const db = admin.firestore();
  const FieldPath = admin.firestore.FieldPath;

  const likesBySession = new Map();
  if (args.groundTruthMode === "likes") {
    const likesSnap = await db.collection("likes").get();
    for (const doc of likesSnap.docs) {
      const data = doc.data();
      const sessionId = data?.sessionId;
      const itemId = data?.itemId;
      if (!startsWithPrefix(sessionId, args.sessionsPrefix)) continue;
      if (typeof itemId !== "string" || itemId.length === 0) continue;
      if (!likesBySession.has(sessionId)) likesBySession.set(sessionId, new Set());
      likesBySession.get(sessionId).add(itemId);
    }
  }

  let sourceSessionIds;
  if (args.groundTruthMode === "likes") {
    sourceSessionIds = Array.from(likesBySession.keys()).sort().slice(0, args.maxSessions);
  } else {
    const sourceSessionsSnap = await db
      .collection("anonSessions")
      .where(FieldPath.documentId(), ">=", args.sessionsPrefix)
      .where(FieldPath.documentId(), "<", `${args.sessionsPrefix}\uf8ff`)
      .limit(args.maxSessions)
      .get();
    sourceSessionIds = sourceSessionsSnap.docs.map((doc) => doc.id).sort();
  }

  if (sourceSessionIds.length === 0) {
    console.log("offline_eval_status: insufficient_data");
    console.log(`offline_eval_ground_truth_mode: ${args.groundTruthMode}`);
    console.log("offline_eval_sessions_total: 0");
    console.log("offline_eval_sessions_scored: 0");
    console.log("offline_eval_sessions_failed: 0");
    console.log("offline_eval_liked_in_top_k: 0.000000");
    return;
  }

  const cleanedEvalSessions = await cleanupEvalSessions(db, args.evalSessionPrefix);

  const materialized = await runWithConcurrency(
    sourceSessionIds,
    args.concurrency,
    async (sourceSessionId) => {
      const weightsDoc = await db
        .collection("anonSessions")
        .doc(sourceSessionId)
        .collection("preferenceWeights")
        .doc("weights")
        .get();

      if (!weightsDoc.exists) {
        return null;
      }

      return {
        sourceSessionId,
        evalSessionId: `${args.evalSessionPrefix}${sourceSessionId}`,
        weights: weightsDoc.data() || {},
      };
    }
  );

  const sessionPairs = materialized.filter((pair) => pair != null);
  const groundTruthBySession = new Map();

  if (args.groundTruthMode === "likes") {
    for (const pair of sessionPairs) {
      groundTruthBySession.set(pair.sourceSessionId, likesBySession.get(pair.sourceSessionId) || new Set());
    }
  } else {
    const itemsSnap = await db.collection("items").where("isActive", "==", true).get();
    const activeItems = itemsSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    for (const pair of sessionPairs) {
      const sorted = activeItems
        .map((item) => ({ id: item.id, score: scoreByPreferenceWeights(item, pair.weights) }))
        .sort((a, b) => {
          if (b.score !== a.score) return b.score - a.score;
          return a.id.localeCompare(b.id);
        })
        .slice(0, args.oracleTopK)
        .filter((row) => row.score > 0);
      groundTruthBySession.set(pair.sourceSessionId, new Set(sorted.map((row) => row.id)));
    }
  }

  const nowTs = admin.firestore.Timestamp.now();
  for (let i = 0; i < sessionPairs.length; i += 250) {
    const batch = db.batch();
    const chunk = sessionPairs.slice(i, i + 250);
    for (const pair of chunk) {
      const sessionRef = db.collection("anonSessions").doc(pair.evalSessionId);
      batch.set(sessionRef, { createdAt: nowTs, lastSeenAt: nowTs });
      batch.set(sessionRef.collection("preferenceWeights").doc("weights"), pair.weights);
    }
    await batch.commit();
  }

  const sessionResults = await runWithConcurrency(sessionPairs, args.concurrency, async (pair) => {
    const likedSet = groundTruthBySession.get(pair.sourceSessionId) || new Set();
    if (likedSet.size === 0) {
      return { sourceSessionId: pair.sourceSessionId, scored: false, failed: false, score: 0 };
    }

    try {
      const servedUnion = new Set();
      for (let i = 0; i < args.requestsPerSession; i += 1) {
        const itemIds = await fetchDeckItemIds(args.baseUrl, pair.evalSessionId, args.limit);
        for (const itemId of itemIds) servedUnion.add(itemId);
      }

      let covered = 0;
      for (const likedItemId of likedSet) {
        if (servedUnion.has(likedItemId)) covered += 1;
      }

      const score = covered / likedSet.size;
      return { sourceSessionId: pair.sourceSessionId, scored: true, failed: false, score };
    } catch (error) {
      return {
        sourceSessionId: pair.sourceSessionId,
        scored: false,
        failed: true,
        score: 0,
        error: String(error && error.message ? error.message : error),
      };
    }
  });

  let scoreSum = 0;
  let scoredCount = 0;
  let failedCount = 0;

  for (const row of sessionResults) {
    if (!row) {
      failedCount += 1;
      continue;
    }
    if (row.failed) {
      failedCount += 1;
      continue;
    }
    if (!row.scored) continue;
    scoreSum += row.score;
    scoredCount += 1;
  }

  const metric = scoredCount > 0 ? scoreSum / scoredCount : 0;
  const status = scoredCount > 0 ? "ok" : "insufficient_data";

  console.log(`offline_eval_status: ${status}`);
  console.log(`offline_eval_ground_truth_mode: ${args.groundTruthMode}`);
  if (args.groundTruthMode !== "likes") {
    console.log(`offline_eval_oracle_top_k: ${args.oracleTopK}`);
  }
  console.log(`offline_eval_sessions_total: ${sourceSessionIds.length}`);
  console.log(`offline_eval_sessions_materialized: ${sessionPairs.length}`);
  console.log(`offline_eval_eval_sessions_cleaned: ${cleanedEvalSessions}`);
  console.log(`offline_eval_sessions_scored: ${scoredCount}`);
  console.log(`offline_eval_sessions_failed: ${failedCount}`);
  console.log(`offline_eval_liked_in_top_k: ${metric.toFixed(6)}`);
  console.log(`primary_metric_liked_in_top_k: ${metric.toFixed(6)}`);
}

main().catch((error) => {
  console.error("offline_eval_status: error");
  console.error(`offline_eval_error: ${String(error && error.message ? error.message : error)}`);
  process.exit(1);
});
