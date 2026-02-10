#!/usr/bin/env node
/* eslint-disable no-console */
const path = require("path");

const functionsRoot = path.resolve(__dirname, "..", "firebase", "functions");
// Load firebase-admin from functions workspace deps.
// eslint-disable-next-line import/no-dynamic-require, global-require
const admin = require(path.join(functionsRoot, "node_modules", "firebase-admin"));

const projectId = process.env.GCLOUD_PROJECT || "swiper-95482";
const pollMs = Number(process.env.POLL_MS || "3000");
const scanLimit = Number(process.env.SCAN_LIMIT || "400");
const sessionFilter = (process.env.SESSION_ID || "").trim();
const maxSeen = Number(process.env.MAX_SEEN || "2000");

admin.initializeApp({ projectId });
const db = admin.firestore();

const seen = new Set();

function toMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value === "number") return value;
  if (typeof value === "string") return Date.parse(value) || 0;
  return 0;
}

function fmtTime(ms) {
  if (!ms) return "unknown";
  return new Date(ms).toISOString().replace("T", " ").replace("Z", "Z");
}

function normalizeSource(card) {
  if (!card || typeof card !== "object") return "-";
  const sourceId = typeof card.sourceId === "string" ? card.sourceId : "";
  if (sourceId) return sourceId;
  return "-";
}

async function poll() {
  const snap = await db
    .collection("events_v1")
    .orderBy("createdAtServer", "desc")
    .limit(scanLimit)
    .get();

  const fresh = [];
  for (const doc of snap.docs) {
    if (seen.has(doc.id)) continue;
    const data = doc.data() || {};
    const eventName = typeof data.eventName === "string" ? data.eventName : "";
    if (eventName !== "deck_render_snapshot") continue;
    const sid = typeof data.sessionId === "string" ? data.sessionId : "";
    if (sessionFilter && sid !== sessionFilter) continue;
    fresh.push({ id: doc.id, data });
  }

  if (fresh.length === 0) return;
  fresh.reverse();

  for (const entry of fresh) {
    const data = entry.data;
    const createdMs = toMs(data.createdAtServer) || toMs(data.createdAtClient);
    const sid = typeof data.sessionId === "string" ? data.sessionId : "-";
    const rank = data.rank && typeof data.rank === "object" ? data.rank : {};
    const ext = data.ext && typeof data.ext === "object" ? data.ext : {};
    const topCards = Array.isArray(ext.topCards) ? ext.topCards : [];

    console.log("");
    console.log(
      `[${fmtTime(createdMs)}] session=${sid} request=${ext.requestId || rank.requestId || "-"} ` +
        `sourceConcTop8=${rank.sourceConcentrationTop8 ?? "-"} ` +
        `sourceDivTop8=${rank.sourceDiversityTop8 ?? "-"}`
    );
    topCards.slice(0, 12).forEach((card, idx) => {
      const title = card && typeof card.title === "string" ? card.title : "(no title)";
      const source = normalizeSource(card);
      const featured = card && card.isFeatured === true ? " featured" : "";
      console.log(`${String(idx + 1).padStart(2, "0")}. [${source}]${featured} ${title}`);
    });
    seen.add(entry.id);
  }

  if (seen.size > maxSeen) {
    const keep = Array.from(seen).slice(-Math.floor(maxSeen * 0.8));
    seen.clear();
    for (const id of keep) seen.add(id);
  }
}

async function main() {
  console.log(
    `Listening for deck_render_snapshot events (project=${projectId}${sessionFilter ? `, session=${sessionFilter}` : ""})...`
  );
  console.log("Press Ctrl+C to stop.");
  // Initial priming so we only show new events after startup.
  const initial = await db
    .collection("events_v1")
    .orderBy("createdAtServer", "desc")
    .limit(scanLimit)
    .get();
  for (const doc of initial.docs) seen.add(doc.id);

  // Poll loop
  // eslint-disable-next-line no-constant-condition
  while (true) {
    await poll();
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
}

main().catch((error) => {
  console.error("tail_deck_render_snapshots_failed", error);
  process.exit(1);
});

