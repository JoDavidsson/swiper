#!/usr/bin/env node
"use strict";

/**
 * Deep research evaluator (ranker-only, deterministic).
 *
 * Uses active emulator items + synth session weights to compare ranker variants:
 * - baseline (current pipeline)
 * - mmr rerank
 * - mmr + adaptive exploration
 *
 * Prints per-variant metric table with:
 * - oracle_coverage_top_k (primary)
 * - avg_relevance_top_k
 * - avg_diversity_top_k (1 - avg pairwise similarity)
 */

const admin = require("firebase-admin");

const DEFAULT_PROJECT_ID = process.env.GCLOUD_PROJECT || "swiper-95482";
const MIN_RANK_WINDOW = 120;

function parseArgs(argv) {
  const args = {
    sessionsPrefix: "synth_",
    maxSessions: 250,
    limit: 10,
    oracleTopK: 30,
    rankWindowMultiplier: 24,
    explorationRate: 0.08,
    explorationSeedOffset: 0,
    mmrLambda: 0.72,
    mmrTopNMultiplier: 4,
    itemLimit: 3000,
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
    } else if (key === "--oracle-top-k") {
      args.oracleTopK = Math.max(1, Number.parseInt(next, 10) || args.oracleTopK);
      i += 1;
    } else if (key === "--rank-window-multiplier") {
      args.rankWindowMultiplier = Math.max(1, Number.parseInt(next, 10) || args.rankWindowMultiplier);
      i += 1;
    } else if (key === "--exploration-rate") {
      args.explorationRate = Math.max(0, Math.min(0.2, Number.parseFloat(next) || args.explorationRate));
      i += 1;
    } else if (key === "--exploration-seed-offset") {
      args.explorationSeedOffset = Number.parseInt(next, 10) || 0;
      i += 1;
    } else if (key === "--mmr-lambda") {
      args.mmrLambda = Math.max(0, Math.min(1, Number.parseFloat(next) || args.mmrLambda));
      i += 1;
    } else if (key === "--mmr-topn-multiplier") {
      args.mmrTopNMultiplier = Math.max(1, Number.parseInt(next, 10) || args.mmrTopNMultiplier);
      i += 1;
    } else if (key === "--item-limit") {
      args.itemLimit = Math.max(1, Number.parseInt(next, 10) || args.itemLimit);
      i += 1;
    }
  }

  return args;
}

function startsWithPrefix(value, prefix) {
  return typeof value === "string" && value.startsWith(prefix);
}

function hashSessionId(sessionId) {
  let h = 0;
  for (let i = 0; i < sessionId.length; i += 1) {
    h = (h << 5) - h + sessionId.charCodeAt(i);
    h &= h;
  }
  return Math.abs(h);
}

function normalizeToken(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

function getStringArray(value) {
  if (!Array.isArray(value)) return [];
  return value.map((entry) => normalizeToken(entry)).filter(Boolean);
}

function itemFeatureTokens(item) {
  const tokens = new Set();
  const styleTags = getStringArray(item.styleTags);
  for (const tag of styleTags) tokens.add(`style:${tag}`);

  const material = normalizeToken(item.material);
  if (material) tokens.add(`material:${material}`);

  const color = normalizeToken(item.colorFamily);
  if (color) tokens.add(`color:${color}`);

  const sizeClass = normalizeToken(item.sizeClass);
  if (sizeClass) tokens.add(`size:${sizeClass}`);

  const subCategory = normalizeToken(item.subCategory);
  if (subCategory) tokens.add(`subcat:${subCategory}`);

  const seatCountBucket = normalizeToken(item.seatCountBucket);
  if (seatCountBucket) tokens.add(`seat_bucket:${seatCountBucket}`);

  return tokens;
}

function jaccardSimilarity(left, right) {
  if (!left.size || !right.size) return 0;
  let intersection = 0;
  for (const token of left) {
    if (right.has(token)) intersection += 1;
  }
  if (intersection === 0) return 0;
  return intersection / (left.size + right.size - intersection);
}

function averagePairwiseSimilarity(itemsById, ids) {
  if (ids.length < 2) return 0;
  const tokenCache = new Map();
  for (const id of ids) {
    tokenCache.set(id, itemFeatureTokens(itemsById.get(id) || {}));
  }
  let sum = 0;
  let pairs = 0;
  for (let i = 0; i < ids.length; i += 1) {
    for (let j = i + 1; j < ids.length; j += 1) {
      sum += jaccardSimilarity(tokenCache.get(ids[i]), tokenCache.get(ids[j]));
      pairs += 1;
    }
  }
  return pairs > 0 ? sum / pairs : 0;
}

function computePreferenceConfidence(weights) {
  const positives = Object.values(weights)
    .filter((value) => typeof value === "number" && Number.isFinite(value) && value > 0)
    .sort((a, b) => b - a);
  if (positives.length === 0) return 0;
  const sum = positives.reduce((acc, value) => acc + value, 0);
  if (sum <= 0) return 0;
  const topShare = positives[0] / sum;
  return Math.max(0, Math.min(1, topShare));
}

function deriveAdaptiveExplorationRate(baseRate, confidence) {
  const coldBoost = 1.25;
  const minRate = 0.04;
  const maxRate = 0.16;
  const boosted = baseRate * (1 + (1 - confidence) * coldBoost);
  return Math.max(minRate, Math.min(maxRate, boosted));
}

function average(values) {
  if (values.length === 0) return 0;
  return values.reduce((acc, value) => acc + value, 0) / values.length;
}

function rankByPreferenceDeterministic(items, weights, limit, scoreItemWithSignals, normalizeScore) {
  const scored = items
    .map((item) => {
      const scoreState = scoreItemWithSignals(item, weights);
      const score = normalizeScore(scoreState.score, scoreState.signalCount);
      return { id: String(item.id), score };
    })
    .sort((left, right) => {
      if (right.score !== left.score) return right.score - left.score;
      return left.id.localeCompare(right.id);
    })
    .slice(0, limit);

  const itemScores = {};
  for (const row of scored) {
    itemScores[row.id] = row.score;
  }

  return {
    itemIds: scored.map((row) => row.id),
    itemScores,
  };
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error("deep_eval_status: error");
    console.error("deep_eval_error: FIRESTORE_EMULATOR_HOST is required");
    process.exit(1);
  }

  // Load compiled ranker modules from lib output.
  let rankerModules;
  try {
    rankerModules = require("../lib/ranker");
  } catch (error) {
    console.error("deep_eval_status: error");
    console.error("deep_eval_error: ranker build artifacts missing. Run `npm run build` first.");
    process.exit(1);
  }

  const { applyExploration, applyMMRReRank, scoreItemWithSignals, normalizeScore } = rankerModules;

  const args = parseArgs(process.argv);
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: DEFAULT_PROJECT_ID });
  }
  const db = admin.firestore();
  const FieldPath = admin.firestore.FieldPath;

  const itemsSnap = await db.collection("items").where("isActive", "==", true).limit(args.itemLimit).get();
  const items = itemsSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((left, right) => String(left.id).localeCompare(String(right.id)));
  if (items.length === 0) {
    console.log("deep_eval_status: insufficient_data");
    console.log("deep_eval_error: no active items in emulator");
    return;
  }
  const itemsById = new Map(items.map((item) => [String(item.id), item]));

  const sessionsSnap = await db
    .collection("anonSessions")
    .where(FieldPath.documentId(), ">=", args.sessionsPrefix)
    .where(FieldPath.documentId(), "<", `${args.sessionsPrefix}\uf8ff`)
    .limit(args.maxSessions)
    .get();
  const sessionIds = sessionsSnap.docs.map((doc) => doc.id).sort();
  if (sessionIds.length === 0) {
    console.log("deep_eval_status: insufficient_data");
    console.log("deep_eval_error: no synth sessions found");
    return;
  }

  const weightDocs = await Promise.all(
    sessionIds.map((sessionId) =>
      db.collection("anonSessions").doc(sessionId).collection("preferenceWeights").doc("weights").get()
    )
  );

  const sessions = [];
  for (let i = 0; i < sessionIds.length; i += 1) {
    const weightsDoc = weightDocs[i];
    if (!weightsDoc.exists) continue;
    sessions.push({ sessionId: sessionIds[i], weights: weightsDoc.data() || {} });
  }
  if (sessions.length === 0) {
    console.log("deep_eval_status: insufficient_data");
    console.log("deep_eval_error: no synth preferenceWeights found");
    return;
  }

  const variants = [
    { id: "baseline", mmr: false, adaptiveExploration: false },
    { id: "mmr", mmr: true, adaptiveExploration: false },
    { id: "mmr_adaptive", mmr: true, adaptiveExploration: true },
  ];

  const aggregates = new Map();
  for (const variant of variants) {
    aggregates.set(variant.id, {
      coverage: [],
      relevance: [],
      diversity: [],
      explorationRate: [],
    });
  }

  for (const session of sessions) {
    const rankWindow = Math.min(items.length, Math.max(args.limit * args.rankWindowMultiplier, MIN_RANK_WINDOW));
    const rankResult = rankByPreferenceDeterministic(
      items,
      session.weights,
      rankWindow,
      scoreItemWithSignals,
      normalizeScore
    );

    const oracleRows = items
      .map((item) => {
        const scoreState = scoreItemWithSignals(item, session.weights);
        const score = normalizeScore(scoreState.score, scoreState.signalCount);
        return { id: String(item.id), score };
      })
      .sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        return a.id.localeCompare(b.id);
      })
      .slice(0, args.oracleTopK)
      .filter((row) => row.score > 0);

    if (oracleRows.length === 0) continue;
    const oracleSet = new Set(oracleRows.map((row) => row.id));
    const oracleScoreById = new Map(oracleRows.map((row) => [row.id, row.score]));
    const confidence = computePreferenceConfidence(session.weights);

    for (const variant of variants) {
      const aggregate = aggregates.get(variant.id);
      const mmrTopN = Math.min(rankResult.itemIds.length, Math.max(args.limit, args.limit * args.mmrTopNMultiplier));
      const rankedIds = variant.mmr
        ? applyMMRReRank(rankResult.itemIds, items, rankResult.itemScores, {
            lambda: args.mmrLambda,
            topN: mmrTopN,
          })
        : rankResult.itemIds;

      const explorationRate = variant.adaptiveExploration
        ? deriveAdaptiveExplorationRate(args.explorationRate, confidence)
        : args.explorationRate;
      const explored = applyExploration(rankedIds, items, {
        explorationRate,
        limit: args.limit,
        seed: hashSessionId(session.sessionId) + args.explorationSeedOffset,
      });

      let covered = 0;
      for (const id of oracleSet) {
        if (explored.includes(id)) covered += 1;
      }
      const coverage = covered / oracleSet.size;
      const relevance = average(explored.map((id) => oracleScoreById.get(id) || 0));
      const avgPairwiseSim = averagePairwiseSimilarity(itemsById, explored);
      const diversity = 1 - avgPairwiseSim;

      aggregate.coverage.push(coverage);
      aggregate.relevance.push(relevance);
      aggregate.diversity.push(diversity);
      aggregate.explorationRate.push(explorationRate);
    }
  }

  const rows = variants.map((variant) => {
    const agg = aggregates.get(variant.id);
    return {
      variant: variant.id,
      sessionsScored: agg.coverage.length,
      oracleCoverageTopK: average(agg.coverage),
      avgRelevanceTopK: average(agg.relevance),
      avgDiversityTopK: average(agg.diversity),
      avgExplorationRate: average(agg.explorationRate),
    };
  });

  const best = rows
    .filter((row) => row.sessionsScored > 0)
    .sort((a, b) => {
      if (b.oracleCoverageTopK !== a.oracleCoverageTopK) return b.oracleCoverageTopK - a.oracleCoverageTopK;
      if (b.avgRelevanceTopK !== a.avgRelevanceTopK) return b.avgRelevanceTopK - a.avgRelevanceTopK;
      return b.avgDiversityTopK - a.avgDiversityTopK;
    })[0];

  console.log("deep_eval_status: ok");
  console.log(`deep_eval_items: ${items.length}`);
  console.log(`deep_eval_sessions_total: ${sessions.length}`);
  console.log(
    "variant\tsessions_scored\toracle_coverage_top_k\tavg_relevance_top_k\tavg_diversity_top_k\tavg_exploration_rate"
  );
  for (const row of rows) {
    console.log(
      [
        row.variant,
        row.sessionsScored,
        row.oracleCoverageTopK.toFixed(6),
        row.avgRelevanceTopK.toFixed(6),
        row.avgDiversityTopK.toFixed(6),
        row.avgExplorationRate.toFixed(6),
      ].join("\t")
    );
  }

  if (!best) {
    console.log("deep_eval_best_variant: none");
    return;
  }

  console.log(`deep_eval_best_variant: ${best.variant}`);
  console.log(`primary_metric_oracle_coverage_top_k: ${best.oracleCoverageTopK.toFixed(6)}`);
}

main().catch((error) => {
  console.error("deep_eval_status: error");
  console.error(`deep_eval_error: ${String(error && error.message ? error.message : error)}`);
  process.exit(1);
});
