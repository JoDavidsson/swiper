/**
 * Optional runner: load fixtures and run ranker + exploration.
 * Usage: npm run build && npm run runRanker
 * Fixtures: scripts/fixtures/items.json, sessionContext.json, optional personaSignals.json
 */
const fs = require("fs");
const path = require("path");

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

const { PreferenceWeightsRanker, PersonalPlusPersonaRanker, applyExploration } = require("../lib/ranker");

const limit = 10;
const explorationRate = 0.05;
const seed = 12345;

console.log("--- PreferenceWeightsRanker ---");
const r1 = PreferenceWeightsRanker.rank(sessionContext, items, { limit });
console.log("runId:", r1.runId);
console.log("algorithmVersion:", r1.algorithmVersion);
console.log("itemIds:", r1.itemIds);
console.log("itemScores:", r1.itemScores);

console.log("\n--- applyExploration (rate=0.05, seed=12345) ---");
const exploredIds = applyExploration(r1.itemIds, items, { explorationRate, limit, seed });
console.log("exploredIds:", exploredIds);

if (personaSignals) {
  console.log("\n--- PersonalPlusPersonaRanker (with personaSignals) ---");
  const r2 = PersonalPlusPersonaRanker.rank(sessionContext, items, { limit }, personaSignals);
  console.log("runId:", r2.runId);
  console.log("algorithmVersion:", r2.algorithmVersion);
  console.log("itemIds:", r2.itemIds);
  console.log("itemScores:", r2.itemScores);
}
