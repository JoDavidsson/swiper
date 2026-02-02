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

const admin = require("firebase-admin");

const BATCH_LIMIT = 500;
const DEFAULT_USERS = 1000;
const DEFAULT_INTERACTIONS_PER_USER = 1000;
const DEFAULT_DECK_SIZE = 20;
const LIKE_FRACTION_OF_RIGHTS = 0.3;
const PERSONA_CLUSTERS = [
  { modern: 3, scandinavian: 2, "material:fabric": 2, "color:gray": 1, "size:medium": 1 },
  { vintage: 3, "material:leather": 2, "color:brown": 2, "size:large": 1 },
  { modern: 2, "material:velvet": 2, "color:green": 1, "color:blue": 1, "size:small": 1 },
  { scandinavian: 2, minimal: 2, "material:wood": 1, "color:white": 2, "size:medium": 1 },
  { modern: 1, vintage: 1, "material:fabric": 1, "color:beige": 2, "size:large": 1 },
];
const MATERIALS = ["fabric", "leather", "velvet", "boucle", "wood", "metal", "mixed"];
const COLORS = ["white", "beige", "brown", "gray", "black", "green", "blue", "red", "yellow", "orange", "pink", "multi"];
const SIZES = ["small", "medium", "large"];
const TAG_POOL = ["modern", "scandinavian", "vintage", "minimal"];
const ECO_TAGS = ["fsc", "recycled", "low_voc", "eco_cert"];
const LOCATION_HINTS = ["Stockholm", "Gothenburg", "Malmo", "Uppsala", "Lund", "Umea"];
const DELIVERY_COMPLEXITY = ["low", "medium", "high"];
const IMAGE_TYPES = ["image/jpeg", "image/webp"];
const PLATFORMS = ["web", "ios", "android"];
const SCREEN_BUCKETS = ["xs", "s", "m", "l", "xl"];
const LOCALES = ["sv-SE", "en-SE"];

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

function randomChoice(rng, list) {
  return list[Math.floor(rng() * list.length)];
}

function randomInt(rng, min, max) {
  return Math.floor(rng() * (max - min + 1)) + min;
}

function hashString(value) {
  let h = 0;
  for (let i = 0; i < value.length; i++) {
    h = (h << 5) - h + value.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h);
}

function uuidV4(rng) {
  const bytes = new Array(16).fill(0).map(() => Math.floor(rng() * 256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const toHex = (b) => b.toString(16).padStart(2, "0");
  return [
    bytes.slice(0, 4).map(toHex).join(""),
    bytes.slice(4, 6).map(toHex).join(""),
    bytes.slice(6, 8).map(toHex).join(""),
    bytes.slice(8, 10).map(toHex).join(""),
    bytes.slice(10, 16).map(toHex).join(""),
  ].join("-");
}

function buildAppContext(rng, locale) {
  return {
    platform: randomChoice(rng, PLATFORMS),
    appVersion: "1.0.0",
    locale,
    timezoneOffsetMinutes: -60,
    screenBucket: randomChoice(rng, SCREEN_BUCKETS),
  };
}

function impressionBucket(durationMs) {
  if (durationMs < 1000) return "0_1s";
  if (durationMs < 3000) return "1_3s";
  if (durationMs < 8000) return "3_8s";
  return "8s_plus";
}

function scoreItemWithSignals(data, weights) {
  let score = 0;
  let signalCount = 0;
  const tags = data.styleTags || [];
  for (const t of tags) {
    const w = weights[t];
    if (typeof w === "number" && w !== 0) {
      score += w;
      signalCount += 1;
    }
  }
  if (data.material) {
    const w = weights["material:" + data.material];
    if (typeof w === "number" && w !== 0) {
      score += w;
      signalCount += 1;
    }
  }
  if (data.colorFamily) {
    const w = weights["color:" + data.colorFamily];
    if (typeof w === "number" && w !== 0) {
      score += w;
      signalCount += 1;
    }
  }
  if (data.sizeClass) {
    const w = weights["size:" + data.sizeClass];
    if (typeof w === "number" && w !== 0) {
      score += w;
      signalCount += 1;
    }
  }
  return { score, signalCount };
}

function normalizeScore(score, signalCount) {
  if (signalCount <= 0) return 0;
  return score / Math.sqrt(signalCount);
}

function scoreItem(data, weights) {
  return scoreItemWithSignals(data, weights).score;
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
  const Timestamp = admin.firestore.Timestamp;

  const rng = seededRandom(args.seed);
  const now = Date.now();
  const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;

  let itemIds = [];
  let itemsById = {};

  async function loadOrGenerateItems() {
    const buildStyleTags = (localRng) => {
      const numTags = 1 + Math.floor(localRng() * 3);
      const tags = new Set();
      while (tags.size < numTags) {
        tags.add(randomChoice(localRng, TAG_POOL));
      }
      return Array.from(tags);
    };

    const buildDimensions = (sizeClass, localRng) => {
      if (sizeClass === "small") {
        return {
          w: randomInt(localRng, 130, 170),
          h: randomInt(localRng, 70, 85),
          d: randomInt(localRng, 70, 85),
        };
      }
      if (sizeClass === "large") {
        return {
          w: randomInt(localRng, 230, 300),
          h: randomInt(localRng, 80, 95),
          d: randomInt(localRng, 90, 110),
        };
      }
      return {
        w: randomInt(localRng, 180, 230),
        h: randomInt(localRng, 75, 90),
        d: randomInt(localRng, 85, 100),
      };
    };

    const buildImages = (id, localRng) => {
      const count = randomInt(localRng, 1, 3);
      const images = [];
      for (let i = 0; i < count; i++) {
        const width = randomChoice(localRng, [800, 1024, 1200]);
        const height = randomChoice(localRng, [600, 768, 900]);
        images.push({
          url: "https://example.com/images/" + id + "_" + (i + 1) + ".jpg",
          width,
          height,
          alt: "Synthetic sofa " + id + " image " + (i + 1),
          type: randomChoice(localRng, IMAGE_TYPES),
        });
      }
      return images;
    };

    const buildEcoTags = (localRng) => {
      if (localRng() < 0.4) {
        const count = randomInt(localRng, 1, 2);
        const tags = new Set();
        while (tags.size < count) {
          tags.add(randomChoice(localRng, ECO_TAGS));
        }
        return Array.from(tags);
      }
      return [];
    };

    const ensureItemFields = (id, existing) => {
      const itemSeed = hashString(id + ":" + String(args.seed || 0));
      const localRng = seededRandom(itemSeed);
      const item = { ...existing };
      const updates = {};

      const setIfMissing = (key, value) => {
        if (item[key] === undefined || item[key] === null) {
          item[key] = value;
          updates[key] = value;
        }
      };

      const ensureArray = (key, defaultValue) => {
        if (!Array.isArray(item[key]) || item[key].length === 0) {
          item[key] = defaultValue;
          updates[key] = defaultValue;
        }
      };

      const title = item.title || "Synthetic sofa " + id;
      setIfMissing("sourceId", "synth");
      setIfMissing("sourceType", "manual");
      setIfMissing("sourceItemId", id);
      setIfMissing("sourceUrl", item.outboundUrl || "https://example.com/source/" + id);
      setIfMissing("canonicalUrl", item.sourceUrl || "https://example.com/item/" + id);
      setIfMissing("title", title);
      setIfMissing("brand", "Synth");
      setIfMissing("descriptionShort", title + " in a clean Scandinavian finish.");

      const sizeClass = item.sizeClass || randomChoice(localRng, SIZES);
      setIfMissing("sizeClass", sizeClass);
      setIfMissing("material", item.material || randomChoice(localRng, MATERIALS));
      setIfMissing("colorFamily", item.colorFamily || randomChoice(localRng, COLORS));
      ensureArray("styleTags", buildStyleTags(localRng));

      setIfMissing("priceAmount", item.priceAmount || (10000 + randomInt(localRng, 0, 20000)));
      setIfMissing("priceCurrency", "SEK");

      if (item.dimensionsCm == null || typeof item.dimensionsCm !== "object") {
        const dims = buildDimensions(item.sizeClass || sizeClass, localRng);
        item.dimensionsCm = dims;
        updates.dimensionsCm = dims;
      } else {
        const dims = { ...item.dimensionsCm };
        if (dims.w == null || dims.h == null || dims.d == null) {
          const filled = buildDimensions(item.sizeClass || sizeClass, localRng);
          item.dimensionsCm = { ...filled, ...dims };
          updates.dimensionsCm = item.dimensionsCm;
        }
      }

      const newUsed = item.newUsed || (localRng() < 0.7 ? "new" : "used");
      setIfMissing("newUsed", newUsed);
      setIfMissing("conditionNote", newUsed === "used" ? "Lightly used, well kept." : "Brand new.");
      setIfMissing("locationHint", randomChoice(localRng, LOCATION_HINTS));
      setIfMissing(
        "deliveryComplexity",
        item.deliveryComplexity ||
          (item.sizeClass === "large" ? "high" : item.sizeClass === "small" ? "low" : "medium")
      );
      setIfMissing("smallSpaceFriendly", item.smallSpaceFriendly ?? (item.sizeClass === "small"));
      setIfMissing("modular", item.modular ?? (localRng() < 0.3));
      ensureArray("ecoTags", buildEcoTags(localRng));

      setIfMissing("availabilityStatus", "in_stock");
      setIfMissing("outboundUrl", item.outboundUrl || "https://example.com/go/" + id);
      ensureArray("images", buildImages(id, localRng));

      setIfMissing("lastUpdatedAt", Timestamp.fromMillis(now));
      setIfMissing("firstSeenAt", Timestamp.fromMillis(now));
      setIfMissing("lastSeenAt", Timestamp.fromMillis(now));
      setIfMissing("isActive", true);

      return { item, updates };
    };

    if (args.generateItems) {
      for (let i = 0; i < args.generateItems; i++) {
        const id = "synth_item_" + (i + 1);
        const base = { title: "Synthetic sofa " + (i + 1) };
        const { item } = ensureItemFields(id, base);
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

    let pending = 0;
    let batch = db.batch();
    for (const d of snap.docs) {
      itemIds.push(d.id);
      const existing = d.data();
      const { item, updates } = ensureItemFields(d.id, existing);
      itemsById[d.id] = item;
      if (Object.keys(updates).length > 0) {
        batch.set(db.collection("items").doc(d.id), updates, { merge: true });
        pending++;
      }
      if (pending >= BATCH_LIMIT) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) {
      await batch.commit();
    }
    console.log("Items: loaded %d from Firestore (missing fields backfilled)", itemIds.length);
  }

  async function createSessionsAndWeights() {
    const sessionIds = [];
    const sessionWeights = [];
    const sessionMeta = [];
    const buildPreferences = (cluster, localRng) => {
      const styleTagsSelected = Object.keys(cluster).filter(
        (k) => !k.startsWith("material:") && !k.startsWith("color:") && !k.startsWith("size:")
      );
      const budgetMinSEK = 5000 + randomInt(localRng, 0, 5000);
      const budgetMaxSEK = budgetMinSEK + 10000 + randomInt(localRng, 0, 15000);
      return {
        styleTagsSelected,
        budgetMinSEK,
        budgetMaxSEK,
        ecoOnly: localRng() < 0.2,
        newOnly: localRng() < 0.7,
        smallSpaceOnly: localRng() < 0.3,
      };
    };

    for (let u = 0; u < args.users; u++) {
      const sessionId = "synth_" + (u + 1);
      sessionIds.push(sessionId);
      const cluster = PERSONA_CLUSTERS[u % PERSONA_CLUSTERS.length];
      const weights = {};
      for (const [k, v] of Object.entries(cluster)) {
        weights[k] = v + (rng() - 0.5) * 0.5;
      }
      sessionWeights.push(weights);
      const locale = randomChoice(rng, LOCALES);
      const preferences = buildPreferences(cluster, rng);
      const app = buildAppContext(rng, locale);
      const sessionStartMs = now - thirtyDaysMs + Math.floor(rng() * thirtyDaysMs);
      const anonUserId = "anon_" + sessionId;
      sessionMeta.push({ sessionId, locale, preferences, app, anonUserId, sessionStartMs });
    }

    for (let i = 0; i < sessionIds.length; i += 250) {
      const batch = db.batch();
      const chunk = sessionIds.slice(i, Math.min(i + 250, sessionIds.length));
      for (let j = 0; j < chunk.length; j++) {
        const sessionId = chunk[j];
        const idx = i + j;
        const meta = sessionMeta[idx];
        const createdAt = new Date(meta.sessionStartMs);
        const lastSeenAt = new Date(meta.sessionStartMs);
        batch.set(db.collection("anonSessions").doc(sessionId), {
          createdAt: Timestamp.fromDate(createdAt),
          lastSeenAt: Timestamp.fromDate(lastSeenAt),
          locale: meta.locale,
          preferences: meta.preferences,
          seenItemIdsRolling: [],
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
    return { sessionIds, sessionWeights, sessionMeta };
  }

  const sessionSeqs = new Map();

  const nextClientSeq = (sessionId) => {
    const next = (sessionSeqs.get(sessionId) || 0) + 1;
    sessionSeqs.set(sessionId, next);
    return next;
  };

  const buildBaseEvent = (sessionId, eventName, createdAtMs, app, anonUserId) => {
    const event = {
      schemaVersion: "1.0",
      eventId: uuidV4(rng),
      eventName,
      sessionId,
      clientSeq: nextClientSeq(sessionId),
      createdAtClient: new Date(createdAtMs).toISOString(),
      app,
      createdAtServer: Timestamp.fromMillis(createdAtMs),
    };
    if (anonUserId) event.anonUserId = anonUserId;
    return event;
  };

  let swipesBatch = db.batch();
  let swipesOps = 0;
  let swipesTotal = 0;
  const queueSwipe = async (doc) => {
    swipesBatch.set(db.collection("swipes").doc(), doc);
    swipesOps += 1;
    swipesTotal += 1;
    if (swipesOps >= BATCH_LIMIT) {
      await swipesBatch.commit();
      swipesBatch = db.batch();
      swipesOps = 0;
      if (swipesTotal % 100000 === 0) console.log("Swipes: %d written", swipesTotal);
    }
  };

  let eventsBatch = db.batch();
  let eventsOps = 0;
  let eventsTotal = 0;
  const queueEvent = async (event) => {
    eventsBatch.set(db.collection("events_v1").doc(event.eventId), event);
    eventsOps += 1;
    eventsTotal += 1;
    if (eventsOps >= BATCH_LIMIT) {
      await eventsBatch.commit();
      eventsBatch = db.batch();
      eventsOps = 0;
      if (eventsTotal % 100000 === 0) console.log("Events_v1: %d written", eventsTotal);
    }
  };

  let legacyBatch = db.batch();
  let legacyOps = 0;
  let legacyTotal = 0;
  const queueLegacyEvent = async (event) => {
    legacyBatch.set(db.collection("events").doc(), event);
    legacyOps += 1;
    legacyTotal += 1;
    if (legacyOps >= BATCH_LIMIT) {
      await legacyBatch.commit();
      legacyBatch = db.batch();
      legacyOps = 0;
      if (legacyTotal % 100000 === 0) console.log("Events (legacy): %d written", legacyTotal);
    }
  };

  let likesBatch = db.batch();
  let likesOps = 0;
  let likesTotal = 0;
  const queueLike = async (sessionId, itemId, createdAtMs) => {
    const ts = Timestamp.fromMillis(createdAtMs);
    if (likesOps + 2 > BATCH_LIMIT) {
      await likesBatch.commit();
      likesBatch = db.batch();
      likesOps = 0;
    }
    likesBatch.set(db.collection("likes").doc(), { sessionId, itemId, createdAt: ts });
    likesOps += 1;
    likesBatch.set(db.collection("anonSessions").doc(sessionId).collection("likes").doc(itemId), { addedAt: ts });
    likesOps += 1;
    likesTotal += 1;
    if (likesOps >= BATCH_LIMIT) {
      await likesBatch.commit();
      likesBatch = db.batch();
      likesOps = 0;
      if (likesTotal % 5000 === 0) console.log("Likes: %d written", likesTotal);
    }
  };

  const buildItemPayload = (item, itemId, positionInDeck) => {
    return {
      itemId,
      source: "deck",
      positionInDeck,
      priceSEKAtTime: typeof item.priceAmount === "number" ? item.priceAmount : 0,
      snapshot: {
        brand: item.brand || "Unknown",
        newUsed: item.newUsed || "unknown",
        sizeClass: item.sizeClass || "unknown",
        material: item.material || "unknown",
        colorFamily: item.colorFamily || "unknown",
        styleTags: Array.isArray(item.styleTags) ? item.styleTags : [],
      },
    };
  };

  const computeRightSwipeProb = (scoreAtRender, maxScore) => {
    if (maxScore <= 0) return 0.2;
    const norm = Math.max(0, Math.min(1, scoreAtRender / maxScore));
    return Math.min(0.9, Math.max(0.1, 0.2 + norm * 0.6));
  };

  const buildRankedItems = (weights) => {
    const scored = itemIds.map((id) => {
      const item = itemsById[id];
      const { score, signalCount } = scoreItemWithSignals(item, weights);
      const normalized = normalizeScore(score, signalCount);
      return { id, score: normalized };
    });
    scored.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.id.localeCompare(b.id);
    });
    const scoresById = {};
    for (const s of scored) scoresById[s.id] = s.score;
    const maxScore = scored.length > 0 ? scored[0].score : 0;
    return { rankedIds: scored.map((s) => s.id), scoresById, maxScore };
  };

  async function generateInteractions(sessionIds, sessionWeights, sessionMeta) {
    const sessionUpdates = [];
    let rightSwipeCount = 0;
    let likeCount = 0;
    for (let u = 0; u < args.users; u++) {
      const sessionId = sessionIds[u];
      const weights = sessionWeights[u];
      const meta = sessionMeta[u];
      const { rankedIds, scoresById, maxScore } = buildRankedItems(weights);
      const seen = new Set();
      const liked = new Set();
      const seenRolling = [];
      let cursor = 0;
      let remaining = args.interactionsPerUser;
      let currentMs = meta.sessionStartMs;

      await queueEvent(buildBaseEvent(sessionId, "session_start", currentMs, meta.app, meta.anonUserId));

      while (remaining > 0) {
        const deckItemIds = [];
        while (deckItemIds.length < DEFAULT_DECK_SIZE && cursor < rankedIds.length) {
          const nextId = rankedIds[cursor++];
          if (seen.has(nextId)) continue;
          deckItemIds.push(nextId);
          seen.add(nextId);
        }
        if (deckItemIds.length === 0) {
          seen.clear();
          cursor = 0;
          continue;
        }

        const rankerRunId = uuidV4(rng);
        const variantBucket = hashString(sessionId) % 100;
        const variant = "personal_only";
        const itemScores = {};
        for (const id of deckItemIds) itemScores[id] = scoresById[id] ?? 0;

        const deckRequestMs = currentMs + randomInt(rng, 150, 600);
        const latencyMs = randomInt(rng, 80, 400);
        const deckResponseMs = deckRequestMs + latencyMs;

        const deckRequestEvent = buildBaseEvent(sessionId, "deck_request", deckRequestMs, meta.app, meta.anonUserId);
        deckRequestEvent.perf = { endpoint: "deck" };
        await queueEvent(deckRequestEvent);

        const deckResponseEvent = buildBaseEvent(sessionId, "deck_response", deckResponseMs, meta.app, meta.anonUserId);
        deckResponseEvent.rank = {
          rankerRunId,
          algorithmVersion: "preference_weights_v1",
          variant,
          variantBucket,
          itemIds: deckItemIds,
        };
        deckResponseEvent.perf = { endpoint: "deck", latencyMs };
        deckResponseEvent.ext = { deckItemScores: itemScores };
        await queueEvent(deckResponseEvent);

        currentMs = deckResponseMs;

        for (let position = 0; position < deckItemIds.length && remaining > 0; position++) {
          const itemId = deckItemIds[position];
          const item = itemsById[itemId];
          const scoreAtRender = itemScores[itemId] ?? 0;

          const impressionId = uuidV4(rng);
          const impressionStartMs = currentMs + randomInt(rng, 50, 300);
          const visibleDurationMs = randomInt(rng, 400, 7000);
          const impressionEndMs = impressionStartMs + visibleDurationMs;
          const swipeMs = impressionEndMs + randomInt(rng, 20, 200);

          const itemPayload = buildItemPayload(item, itemId, position);
          const impressionStartEvent = buildBaseEvent(
            sessionId,
            "card_impression_start",
            impressionStartMs,
            meta.app,
            meta.anonUserId
          );
          impressionStartEvent.item = itemPayload;
          impressionStartEvent.impression = { impressionId };
          impressionStartEvent.surface = { name: "deck_card" };
          await queueEvent(impressionStartEvent);

          const impressionEndEvent = buildBaseEvent(
            sessionId,
            "card_impression_end",
            impressionEndMs,
            meta.app,
            meta.anonUserId
          );
          impressionEndEvent.item = itemPayload;
          impressionEndEvent.impression = {
            impressionId,
            visibleDurationMs,
            endReason: "swipe",
            bucket: impressionBucket(visibleDurationMs),
          };
          impressionEndEvent.surface = { name: "deck_card" };
          await queueEvent(impressionEndEvent);

          const direction = rng() < computeRightSwipeProb(scoreAtRender, maxScore) ? "right" : "left";
          if (direction === "right") rightSwipeCount += 1;

          const swipeEvent = buildBaseEvent(sessionId, direction === "right" ? "swipe_right" : "swipe_left", swipeMs, meta.app, meta.anonUserId);
          swipeEvent.item = itemPayload;
          swipeEvent.interaction = {
            gesture: "swipe",
            direction,
            velocity: Math.round((rng() * 2 + 0.5) * 100) / 100,
          };
          swipeEvent.rank = {
            rankerRunId,
            algorithmVersion: "preference_weights_v1",
            variant,
            variantBucket,
            scoreAtRender,
          };
          swipeEvent.surface = { name: "deck_card" };
          await queueEvent(swipeEvent);

          await queueSwipe({
            sessionId,
            itemId,
            direction,
            positionInDeck: position,
            createdAt: Timestamp.fromMillis(swipeMs),
          });
          await queueLegacyEvent({
            sessionId,
            eventType: direction === "right" ? "swipe_right" : "swipe_left",
            itemId,
            metadata: { positionInDeck: position },
            createdAt: Timestamp.fromMillis(swipeMs),
          });

          if (direction === "right") {
            const likeKey = sessionId + ":" + itemId;
            if (!liked.has(likeKey) && rng() < LIKE_FRACTION_OF_RIGHTS) {
              liked.add(likeKey);
              likeCount += 1;
              const likeMs = swipeMs + randomInt(rng, 20, 300);
              await queueLike(sessionId, itemId, likeMs);
              const likeEvent = buildBaseEvent(sessionId, "like_add", likeMs, meta.app, meta.anonUserId);
              likeEvent.item = itemPayload;
              likeEvent.rank = {
                rankerRunId,
                algorithmVersion: "preference_weights_v1",
                variant,
                variantBucket,
                scoreAtRender,
              };
              likeEvent.surface = { name: "deck_card" };
              await queueEvent(likeEvent);
              await queueLegacyEvent({
                sessionId,
                eventType: "add_like",
                itemId,
                createdAt: Timestamp.fromMillis(likeMs),
              });
            }
          }

          seenRolling.push(itemId);
          if (seenRolling.length > 20) seenRolling.shift();

          currentMs = swipeMs;
          remaining -= 1;
        }
      }

      sessionUpdates.push({
        sessionId,
        lastSeenAtMs: currentMs,
        seenItemIdsRolling: seenRolling,
      });
    }

    return { rightSwipeCount, likeCount, sessionUpdates };
  }

  async function updateSessions(sessionUpdates) {
    let batch = db.batch();
    let ops = 0;
    for (const update of sessionUpdates) {
      batch.set(
        db.collection("anonSessions").doc(update.sessionId),
        {
          lastSeenAt: Timestamp.fromMillis(update.lastSeenAtMs),
          seenItemIdsRolling: update.seenItemIdsRolling,
        },
        { merge: true }
      );
      ops += 1;
      if (ops >= BATCH_LIMIT) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  }

  async function flushBatches() {
    if (swipesOps > 0) await swipesBatch.commit();
    if (eventsOps > 0) await eventsBatch.commit();
    if (legacyOps > 0) await legacyBatch.commit();
    if (likesOps > 0) await likesBatch.commit();
  }

  (async () => {
    await loadOrGenerateItems();
    const { sessionIds, sessionWeights, sessionMeta } = await createSessionsAndWeights();
    const { rightSwipeCount, likeCount, sessionUpdates } = await generateInteractions(
      sessionIds,
      sessionWeights,
      sessionMeta
    );
    await flushBatches();
    await updateSessions(sessionUpdates);
    console.log(
      "Done. Synthetic dataset: %d users, %d interactions, %d right-swipes, %d likes.",
      args.users,
      totalInteractions,
      rightSwipeCount,
      likeCount
    );
    console.log(
      "Writes: swipes=%d, events_v1=%d, events_legacy=%d, likes=%d",
      swipesTotal,
      eventsTotal,
      legacyTotal,
      likesTotal
    );
  })().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

main();
