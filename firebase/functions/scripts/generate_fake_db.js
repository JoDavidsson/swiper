/**
 * Generate synthetic Firestore dataset for recommendation algorithm evaluation.
 * Purpose: multi-session interaction data (swipes, likes, preferenceWeights) so we can
 * evaluate personal and persona-based ranking, offline metrics, and A/B without production.
 *
 * Usage (from firebase/functions, with emulator running):
 *   npm run build
 *   FIRESTORE_EMULATOR_HOST=localhost:8180 node scripts/generate_fake_db.js [--users 1000] [--interactions-per-user 1000] [--seed 42] [--generate-items N]
 *
 * Requires FIRESTORE_EMULATOR_HOST to be set (safety: do not write to production).
 * Option A: Ingest items first (ingest_sample_feed.sh), then run this script.
 * Option B: --generate-items N to create N synthetic items (no prior ingest).
 */
"use strict";

const path = require("path");
const admin = require("firebase-admin");

const BATCH_LIMIT = 500;
const DEFAULT_USERS = 1000;
const DEFAULT_INTERACTIONS_PER_USER = 1000;
const LIKE_FRACTION_OF_RIGHTS = 0.3;
const PERSONA_CLUSTERS = [
  { modern: 3, scandinavian: 2, "material:fabric": 2, "color:gray": 1, "size:medium": 1 },
  { vintage: 3, "material:leather": 2, "color:brown": 2, "size:large": 1 },
  { modern: 2, "material:velvet": 2, "color:green": 1, "color:blue": 1, "size:small": 1 },
  { scandinavian: 2, minimal: 2, "material:wood": 1, "color:white": 2, "size:medium": 1 },
  { modern: 1, vintage: 1, "material:fabric": 1, "color:beige": 2, "size:large": 1 },
];

function parseArgs() {
  const args = { users: DEFAULT_USERS, interactionsPerUser: DEFAULT_INTERACTIONS_PER_USER, seed: 42, generateItems: null };
  for (let i = 2; i < process.argv.length; i++) {
    if (process.argv[i] === "--users" && process.argv[i + 1]) {
      args.users = Math.max(1, parseInt(process.argv[++i], 10) || DEFAULT_USERS);
    } else if (process.argv[i] === "--interactions-per-user" && process.argv[i + 1]) {
      args.interactionsPerUser = Math.max(1, parseInt(process.argv[++i], 10) || DEFAULT_INTERACTIONS_PER_USER);
    } else if (process.argv[i] === "--seed" && process.argv[i + 1]) {
      args.seed = parseInt(process.argv[++i], 10) || 42;
    } else if (process.argv[i] === "--generate-items" && process.argv[i + 1]) {
      args.generateItems = Math.max(1, parseInt(process.argv[++i], 10));
    }
  }
  return args;
}

function seededRandom(seed) {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function scoreItem(data, weights) {
  let score = 0;
  const tags = (data.styleTags || []);
  for (const t of tags) score += weights[t] ?? 0;
  if (data.material) score += weights["material:" + data.material] ?? 0;
  if (data.colorFamily) score += weights["color:" + data.colorFamily] ?? 0;
  if (data.sizeClass) score += weights["size:" + data.sizeClass] ?? 0;
  return score;
}

function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error("Safety: set FIRESTORE_EMULATOR_HOST (e.g. localhost:8180). Do not write to production.");
    process.exit(1);
  }

  const args = parseArgs();
  const totalInteractions = args.users * args.interactionsPerUser;
  console.log("Config: users=%d, interactionsPerUser=%d, total=%d, seed=%d, generateItems=%s",
    args.users, args.interactionsPerUser, totalInteractions, args.seed, args.generateItems || "no");

  if (!admin.apps.length) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "swiper-95482" });
  }
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const Timestamp = admin.firestore.Timestamp;

  const rng = seededRandom(args.seed);
  const now = Date.now();
  const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;

  let itemIds = [];
  let itemsById = {};

  async function loadOrGenerateItems() {
    if (args.generateItems) {
      const materials = ["fabric", "leather", "velvet", "wood", "metal"];
      const colors = ["gray", "brown", "green", "blue", "beige", "white", "black"];
      const sizes = ["small", "medium", "large"];
      const tagPool = ["modern", "scandinavian", "vintage", "minimal"];
      for (let i = 0; i < args.generateItems; i++) {
        const id = "synth_item_" + (i + 1);
        const numTags = 1 + Math.floor(rng() * 3);
        const styleTags = [];
        for (let t = 0; t < numTags; t++) styleTags.push(tagPool[Math.floor(rng() * tagPool.length)]);
        const item = {
          sourceId: "synth",
          sourceType: "manual",
          title: "Synthetic sofa " + (i + 1),
          brand: "Synth",
          priceAmount: 10000 + Math.floor(rng() * 20000),
          priceCurrency: "SEK",
          sizeClass: sizes[Math.floor(rng() * sizes.length)],
          material: materials[Math.floor(rng() * materials.length)],
          colorFamily: colors[Math.floor(rng() * colors.length)],
          styleTags,
          newUsed: "new",
          availabilityStatus: "in_stock",
          outboundUrl: "https://example.com/" + id,
          lastUpdatedAt: Timestamp.fromMillis(now),
          firstSeenAt: Timestamp.fromMillis(now),
          lastSeenAt: Timestamp.fromMillis(now),
          isActive: true,
        };
        itemsById[id] = item;
        itemIds.push(id);
      }
      let written = 0;
      for (let i = 0; i < itemIds.length; i += BATCH_LIMIT) {
        const batch = db.batch();
        const chunk = itemIds.slice(i, i + BATCH_LIMIT);
        for (const id of chunk) {
          const data = { ...itemsById[id] };
          batch.set(db.collection("items").doc(id), data);
          written++;
        }
        await batch.commit();
        console.log("Items: wrote batch %d-%d", i + 1, i + chunk.length);
      }
      console.log("Items: %d synthetic items written", written);
      return;
    }
    const snap = await db.collection("items").where("isActive", "==", true).limit(500).get();
    if (snap.empty) {
      console.error("No items in Firestore. Ingest items first (ingest_sample_feed.sh) or use --generate-items N");
      process.exit(1);
    }
    snap.docs.forEach((d) => {
      itemIds.push(d.id);
      const d_ = d.data();
      itemsById[d.id] = {
        styleTags: d_.styleTags || [],
        material: d_.material,
        colorFamily: d_.colorFamily,
        sizeClass: d_.sizeClass,
      };
    });
    console.log("Items: loaded %d from Firestore", itemIds.length);
  }

  async function createSessionsAndWeights() {
    const sessionIds = [];
    const sessionWeights = [];
    for (let u = 0; u < args.users; u++) {
      const sessionId = "synth_" + (u + 1);
      sessionIds.push(sessionId);
      const cluster = PERSONA_CLUSTERS[u % PERSONA_CLUSTERS.length];
      const weights = {};
      for (const [k, v] of Object.entries(cluster)) {
        weights[k] = v + (rng() - 0.5) * 0.5;
      }
      sessionWeights.push(weights);
    }

    for (let i = 0; i < sessionIds.length; i += 250) {
      const batch = db.batch();
      const chunk = sessionIds.slice(i, Math.min(i + 250, sessionIds.length));
      for (let j = 0; j < chunk.length; j++) {
        const sessionId = chunk[j];
        const idx = i + j;
        const createdAt = new Date(now - thirtyDaysMs + (rng() * thirtyDaysMs));
        const lastSeenAt = new Date(createdAt.getTime() + rng() * 7 * 24 * 60 * 60 * 1000);
        batch.set(db.collection("anonSessions").doc(sessionId), {
          createdAt: Timestamp.fromDate(createdAt),
          lastSeenAt: Timestamp.fromDate(lastSeenAt),
        });
        batch.set(
          db.collection("anonSessions").doc(sessionId).collection("preferenceWeights").doc("weights"),
          sessionWeights[idx]
        );
      }
      await batch.commit();
      console.log("Sessions + weights: batch %d-%d", i + 1, i + chunk.length);
    }
    console.log("Sessions: %d anonSessions + preferenceWeights written", sessionIds.length);
    return { sessionIds, sessionWeights };
  }

  async function generateSwipes(sessionIds, sessionWeights) {
    const rightSwipes = [];
    let batchOps = [];
    let batchCount = 0;
    for (let u = 0; u < args.users; u++) {
      const sessionId = sessionIds[u];
      const weights = sessionWeights[u];
      for (let k = 0; k < args.interactionsPerUser; k++) {
        const itemId = itemIds[Math.floor(rng() * itemIds.length)];
        const item = itemsById[itemId];
        const sc = scoreItem(item, weights);
        const maxScore = 15;
        const pRight = Math.min(0.9, Math.max(0.1, 0.2 + (sc / maxScore) * 0.6));
        const direction = rng() < pRight ? "right" : "left";
        if (direction === "right") rightSwipes.push({ sessionId, itemId });
        batchOps.push({
          sessionId,
          itemId,
          direction,
          positionInDeck: k % 20,
          createdAt: Timestamp.fromMillis(now - thirtyDaysMs + Math.floor(rng() * thirtyDaysMs)),
        });
        if (batchOps.length >= BATCH_LIMIT) {
          const batch = db.batch();
          for (const op of batchOps) {
            batch.set(db.collection("swipes").doc(), op);
          }
          await batch.commit();
          batchCount += batchOps.length;
          batchOps = [];
          if (batchCount % 100000 === 0) console.log("Swipes: %d written", batchCount);
        }
      }
    }
    if (batchOps.length) {
      const batch = db.batch();
      for (const op of batchOps) batch.set(db.collection("swipes").doc(), op);
      await batch.commit();
      batchCount += batchOps.length;
    }
    console.log("Swipes: %d total written", batchCount);
    return rightSwipes;
  }

  async function writeLikes(rightSwipes) {
    const nLikes = Math.max(1, Math.floor(rightSwipes.length * LIKE_FRACTION_OF_RIGHTS));
    const likeSet = new Set();
    const likes = [];
    const shuffled = rightSwipes.slice();
    for (let i = shuffled.length - 1; i > 0 && likes.length < nLikes; i--) {
      const j = Math.floor(rng() * (i + 1));
      [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    for (let i = 0; i < shuffled.length && likes.length < nLikes; i++) {
      const { sessionId, itemId } = shuffled[i];
      const key = sessionId + ":" + itemId;
      if (likeSet.has(key)) continue;
      likeSet.add(key);
      likes.push({ sessionId, itemId });
    }
    const ts = Timestamp.fromMillis(now);
    for (let i = 0; i < likes.length; i += 250) {
      const batch = db.batch();
      const chunk = likes.slice(i, i + 250);
      for (const { sessionId, itemId } of chunk) {
        const likeRef = db.collection("likes").doc();
        batch.set(likeRef, { sessionId, itemId, createdAt: ts });
        batch.set(
          db.collection("anonSessions").doc(sessionId).collection("likes").doc(itemId),
          { addedAt: ts }
        );
      }
      await batch.commit();
      if ((i + chunk.length) % 5000 === 0) console.log("Likes: %d written", i + chunk.length);
    }
    console.log("Likes: %d total (top-level + subcollection)", likes.length * 2);
  }

  (async () => {
    await loadOrGenerateItems();
    const { sessionIds, sessionWeights } = await createSessionsAndWeights();
    const rightSwipes = await generateSwipes(sessionIds, sessionWeights);
    await writeLikes(rightSwipes);
    console.log("Done. Synthetic dataset: %d users, %d interactions, %d right-swipes, ~%d%% likes.",
      args.users, totalInteractions, rightSwipes.length, Math.round(LIKE_FRACTION_OF_RIGHTS * 100));
  })().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

main();
