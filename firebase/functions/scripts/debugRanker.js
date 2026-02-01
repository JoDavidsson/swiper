/**
 * Debug loop: run recommendation engine with fixtures, log each step to NDJSON,
 * assert expected behaviour, and print test output.
 * Usage: npm run build && npm run debugRanker
 * Log path: <workspace>/.cursor/debug.log
 */
const fs = require("fs");
const path = require("path");

const workspaceRoot = path.resolve(__dirname, "../../..");
const LOG_PATH = path.join(workspaceRoot, ".cursor", "debug.log");

function log(entry) {
  const line =
    JSON.stringify({
      ...entry,
      timestamp: entry.timestamp ?? Date.now(),
      sessionId: entry.sessionId ?? "debug-ranker",
      runId: entry.runId ?? "run1",
    }) + "\n";
  try {
    const logDir = path.dirname(LOG_PATH);
    if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
    fs.appendFileSync(LOG_PATH, line);
  } catch (e) {
    console.error("debug log write failed:", e.message);
  }
}

const fixturesDir = path.join(__dirname, "fixtures");
const itemsPath = path.join(fixturesDir, "items.json");
const sessionPath = path.join(fixturesDir, "sessionContext.json");
const personaPath = path.join(fixturesDir, "personaSignals.json");

const items = JSON.parse(fs.readFileSync(itemsPath, "utf8"));
const sessionContext = JSON.parse(fs.readFileSync(sessionPath, "utf8"));
let personaSignals = null;
if (fs.existsSync(personaPath)) {
  personaSignals = JSON.parse(fs.readFileSync(personaPath, "utf8"));
}

const { scoreItem, PreferenceWeightsRanker, PersonalPlusPersonaRanker, applyExploration } = require("../lib/ranker");

const limit = 10;
const explorationRate = 0.05;
const seed = 12345;

const results = [];

// --- Step 1: scoreItem ---
log({
  hypothesisId: "scoreItem",
  location: "debugRanker.js:scoreItem",
  message: "scoreItem entry",
  data: { itemId: items[0]?.id, weightsKeys: Object.keys(sessionContext.preferenceWeights || {}) },
});
const score0 = items[0] ? scoreItem(items[0], sessionContext.preferenceWeights || {}) : 0;
log({
  hypothesisId: "scoreItem",
  location: "debugRanker.js:scoreItem",
  message: "scoreItem exit",
  data: { itemId: items[0]?.id, score: score0 },
});
const scoreItemOk = typeof score0 === "number" && (items[0] ? score0 >= 0 : true);
results.push({ step: "scoreItem", ok: scoreItemOk, detail: scoreItemOk ? `score=${score0}` : "unexpected" });

// --- Step 2: PreferenceWeightsRanker ---
log({
  hypothesisId: "PreferenceWeightsRanker",
  location: "debugRanker.js:PreferenceWeightsRanker",
  message: "PreferenceWeightsRanker entry",
  data: { candidatesCount: items.length, limit },
});
const r1 = PreferenceWeightsRanker.rank(sessionContext, items, { limit });
log({
  hypothesisId: "PreferenceWeightsRanker",
  location: "debugRanker.js:PreferenceWeightsRanker",
  message: "PreferenceWeightsRanker exit",
  data: { runId: r1.runId, itemIds: r1.itemIds, itemScoresKeys: Object.keys(r1.itemScores || {}) },
});
const rankerOk =
  r1.runId &&
  r1.algorithmVersion === "preference_weights_v1" &&
  Array.isArray(r1.itemIds) &&
  r1.itemIds.length <= limit &&
  r1.itemIds.length === Object.keys(r1.itemScores || {}).length;
results.push({
  step: "PreferenceWeightsRanker",
  ok: rankerOk,
  detail: rankerOk ? `runId=${r1.runId} items=${r1.itemIds.length}` : "unexpected",
});

// --- Step 3: applyExploration rate=0 (deterministic) ---
log({
  hypothesisId: "exploration_rate0",
  location: "debugRanker.js:applyExploration",
  message: "applyExploration rate=0 entry",
  data: { rankedIds: r1.itemIds.slice(0, 3), limit, explorationRate: 0 },
});
const explored0 = applyExploration(r1.itemIds, items, { explorationRate: 0, limit, seed });
log({
  hypothesisId: "exploration_rate0",
  location: "debugRanker.js:applyExploration",
  message: "applyExploration rate=0 exit",
  data: { exploredIds: explored0 },
});
const exploration0Ok =
  explored0.length <= limit &&
  (r1.itemIds.length >= limit ? explored0.join(",") === r1.itemIds.slice(0, limit).join(",") : explored0.length === r1.itemIds.length);
results.push({
  step: "applyExploration(rate=0)",
  ok: exploration0Ok,
  detail: exploration0Ok ? "order unchanged" : "unexpected",
});

// --- Step 4: applyExploration rate>0 (reproducible with seed) ---
log({
  hypothesisId: "exploration_rate_gt0",
  location: "debugRanker.js:applyExploration",
  message: "applyExploration rate>0 entry",
  data: { rankedIds: r1.itemIds, limit, explorationRate, seed },
});
const explored1 = applyExploration(r1.itemIds, items, { explorationRate, limit, seed });
const explored2 = applyExploration(r1.itemIds, items, { explorationRate, limit, seed });
log({
  hypothesisId: "exploration_rate_gt0",
  location: "debugRanker.js:applyExploration",
  message: "applyExploration rate>0 exit",
  data: { exploredIds: explored1, repeatMatch: explored1.join(",") === explored2.join(",") },
});
const exploration1Ok = explored1.length <= limit && explored1.join(",") === explored2.join(",");
results.push({
  step: "applyExploration(rate>0,seed)",
  ok: exploration1Ok,
  detail: exploration1Ok ? "reproducible" : "unexpected",
});

// --- Step 5: PersonalPlusPersonaRanker (with or without personaSignals) ---
log({
  hypothesisId: "PersonalPlusPersonaRanker",
  location: "debugRanker.js:PersonalPlusPersonaRanker",
  message: "PersonalPlusPersonaRanker entry",
  data: { hasPersonaSignals: !!personaSignals, candidatesCount: items.length, limit },
});
const r2 = PersonalPlusPersonaRanker.rank(sessionContext, items, { limit }, personaSignals || undefined);
log({
  hypothesisId: "PersonalPlusPersonaRanker",
  location: "debugRanker.js:PersonalPlusPersonaRanker",
  message: "PersonalPlusPersonaRanker exit",
  data: { runId: r2.runId, algorithmVersion: r2.algorithmVersion, itemIds: r2.itemIds },
});
const personaOk =
  r2.runId &&
  r2.algorithmVersion === "personal_plus_persona_v1" &&
  Array.isArray(r2.itemIds) &&
  r2.itemIds.length <= limit &&
  Object.keys(r2.itemScores || {}).length === r2.itemIds.length;
results.push({
  step: "PersonalPlusPersonaRanker",
  ok: personaOk,
  detail: personaOk ? `runId=${r2.runId} items=${r2.itemIds.length}` : "unexpected",
});

// --- Test output summary ---
const allOk = results.every((r) => r.ok);
log({
  hypothesisId: "summary",
  location: "debugRanker.js:summary",
  message: "debug loop summary",
  data: { allOk, results },
});

console.log("\n--- Recommendation engine debug loop ---");
results.forEach((r) => {
  console.log(r.ok ? `  PASS ${r.step}: ${r.detail}` : `  FAIL ${r.step}: ${r.detail}`);
});
console.log(allOk ? "\n  All checks passed.\n" : "\n  Some checks failed.\n");
process.exit(allOk ? 0 : 1);
