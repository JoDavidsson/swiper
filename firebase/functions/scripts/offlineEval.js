/**
 * Offline evaluation script: Computes "Liked-in-top-K" metric for recommendations engine.
 * 
 * Usage:
 *   node scripts/offlineEval.js [--days N] [--variant VARIANT_NAME] [--min-likes N]
 * 
 * Options:
 *   --days N: Only consider events from the last N days (default: 7)
 *   --variant VARIANT_NAME: Filter by specific variant (default: all variants)
 *   --min-likes N: Only include sessions with at least N likes (default: 1)
 *   --emulator: Use Firestore emulator (reads FIRESTORE_EMULATOR_HOST)
 * 
 * Metric: "Liked-in-top-K per session"
 * - For each session with at least one like, compute the fraction of that session's
 *   liked item IDs that appeared in the union of served item IDs across all deck_response
 *   events for that session.
 * - Aggregate: average over sessions (so each session counts once).
 * 
 * Output:
 * - Console: Summary stats (total sessions, sessions with likes, avg Liked-in-top-K)
 * - JSON file: Detailed results per session and per variant
 */

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

// Parse command-line arguments
const args = process.argv.slice(2);
function getArg(flag, defaultValue) {
  const idx = args.indexOf(flag);
  return idx >= 0 && idx + 1 < args.length ? args[idx + 1] : defaultValue;
}
const useEmulator = args.includes("--emulator");
const daysBack = parseInt(getArg("--days", "7"), 10);
const filterVariant = getArg("--variant", null);
const minLikes = parseInt(getArg("--min-likes", "1"), 10);

// Initialize Firebase Admin
if (useEmulator) {
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "localhost:8180";
  console.log(`Using Firestore emulator: ${process.env.FIRESTORE_EMULATOR_HOST}`);
}

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Fetch all deck_response events within the time window
 */
async function fetchDeckResponses(startDate) {
  console.log(`Fetching deck_response events since ${startDate.toISOString()}...`);
  const eventsRef = db.collection("events_v1");
  const snapshot = await eventsRef
    .where("eventName", "==", "deck_response")
    .where("createdAtServer", ">=", admin.firestore.Timestamp.fromDate(startDate))
    .orderBy("createdAtServer", "asc")
    .get();

  const events = [];
  snapshot.forEach((doc) => {
    const data = doc.data();
    events.push({
      eventId: doc.id,
      sessionId: data.sessionId,
      createdAtServer: data.createdAtServer?.toDate(),
      rank: data.rank || {},
    });
  });

  console.log(`Found ${events.length} deck_response events.`);
  return events;
}

/**
 * Fetch all likes (from likes collection or like_add events)
 */
async function fetchLikes(startDate) {
  console.log(`Fetching likes since ${startDate.toISOString()}...`);
  
  // Try likes collection first
  const likesRef = db.collection("likes");
  const likesSnapshot = await likesRef
    .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(startDate))
    .get();

  const likesFromCollection = [];
  likesSnapshot.forEach((doc) => {
    const data = doc.data();
    likesFromCollection.push({
      sessionId: data.sessionId,
      itemId: data.itemId,
      createdAt: data.createdAt?.toDate(),
    });
  });

  console.log(`Found ${likesFromCollection.length} likes from likes collection.`);

  // Also fetch like_add events from events_v1
  const eventsRef = db.collection("events_v1");
  const likeEventsSnapshot = await eventsRef
    .where("eventName", "==", "like_add")
    .where("createdAtServer", ">=", admin.firestore.Timestamp.fromDate(startDate))
    .get();

  const likesFromEvents = [];
  likeEventsSnapshot.forEach((doc) => {
    const data = doc.data();
    if (data.item?.itemId) {
      likesFromEvents.push({
        sessionId: data.sessionId,
        itemId: data.item.itemId,
        createdAt: data.createdAtServer?.toDate(),
      });
    }
  });

  console.log(`Found ${likesFromEvents.length} likes from like_add events.`);

  // Dedupe and merge (prefer likes collection)
  const allLikes = [...likesFromCollection];
  const existingKeys = new Set(likesFromCollection.map((l) => `${l.sessionId}:${l.itemId}`));
  
  for (const like of likesFromEvents) {
    const key = `${like.sessionId}:${like.itemId}`;
    if (!existingKeys.has(key)) {
      allLikes.push(like);
      existingKeys.add(key);
    }
  }

  console.log(`Total unique likes: ${allLikes.length}`);
  return allLikes;
}

/**
 * Group deck_response events by sessionId, extract served item IDs
 */
function groupDeckResponsesBySession(events, filterVariant) {
  const sessionToServedItems = new Map();
  const sessionToVariant = new Map();

  for (const event of events) {
    const { sessionId, rank } = event;
    if (!sessionId) continue;

    // Filter by variant if specified
    if (filterVariant && rank.variant !== filterVariant) continue;

    // Initialize session data
    if (!sessionToServedItems.has(sessionId)) {
      sessionToServedItems.set(sessionId, new Set());
    }

    // Track variant (use first variant seen for session)
    if (!sessionToVariant.has(sessionId) && rank.variant) {
      sessionToVariant.set(sessionId, rank.variant);
    }

    // Add served items to session's set
    const itemIds = rank.itemIds || [];
    for (const itemId of itemIds) {
      sessionToServedItems.get(sessionId).add(itemId);
    }
  }

  return { sessionToServedItems, sessionToVariant };
}

/**
 * Group likes by sessionId
 */
function groupLikesBySession(likes) {
  const sessionToLikes = new Map();

  for (const like of likes) {
    const { sessionId, itemId } = like;
    if (!sessionId || !itemId) continue;

    if (!sessionToLikes.has(sessionId)) {
      sessionToLikes.set(sessionId, new Set());
    }
    sessionToLikes.get(sessionId).add(itemId);
  }

  return sessionToLikes;
}

/**
 * Compute Liked-in-top-K metric per session
 */
function computeLikedInTopK(sessionToServedItems, sessionToLikes, sessionToVariant, minLikes) {
  const results = [];
  let totalSessions = 0;
  let sessionsWithLikes = 0;
  let sumLikedInTopK = 0;

  for (const [sessionId, likedItems] of sessionToLikes.entries()) {
    totalSessions++;
    
    // Skip sessions with too few likes
    if (likedItems.size < minLikes) continue;
    
    sessionsWithLikes++;

    const servedItems = sessionToServedItems.get(sessionId) || new Set();
    const variant = sessionToVariant.get(sessionId) || "unknown";

    // Compute fraction of liked items that were served
    let likedAndServed = 0;
    for (const itemId of likedItems) {
      if (servedItems.has(itemId)) {
        likedAndServed++;
      }
    }

    const fraction = likedItems.size > 0 ? likedAndServed / likedItems.size : 0;
    sumLikedInTopK += fraction;

    results.push({
      sessionId,
      variant,
      totalLikes: likedItems.size,
      totalServed: servedItems.size,
      likedAndServed,
      likedInTopKFraction: fraction,
    });
  }

  const avgLikedInTopK = sessionsWithLikes > 0 ? sumLikedInTopK / sessionsWithLikes : 0;

  return {
    totalSessions,
    sessionsWithLikes,
    avgLikedInTopK,
    results,
  };
}

/**
 * Compute metric segmented by variant
 */
function computeByVariant(results) {
  const variantStats = new Map();

  for (const result of results) {
    const { variant, likedInTopKFraction } = result;
    if (!variantStats.has(variant)) {
      variantStats.set(variant, { count: 0, sum: 0 });
    }
    const stats = variantStats.get(variant);
    stats.count++;
    stats.sum += likedInTopKFraction;
  }

  const byVariant = [];
  for (const [variant, stats] of variantStats.entries()) {
    byVariant.push({
      variant,
      sessionsWithLikes: stats.count,
      avgLikedInTopK: stats.count > 0 ? stats.sum / stats.count : 0,
    });
  }

  byVariant.sort((a, b) => b.avgLikedInTopK - a.avgLikedInTopK);
  return byVariant;
}

/**
 * Main evaluation function
 */
async function runEvaluation() {
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - daysBack);

  console.log(`\n=== Offline Evaluation: Liked-in-top-K ===`);
  console.log(`Time window: last ${daysBack} days (since ${startDate.toISOString()})`);
  console.log(`Min likes per session: ${minLikes}`);
  if (filterVariant) {
    console.log(`Filtering by variant: ${filterVariant}`);
  }
  console.log();

  // Fetch data
  const [deckResponses, likes] = await Promise.all([
    fetchDeckResponses(startDate),
    fetchLikes(startDate),
  ]);

  if (deckResponses.length === 0) {
    console.log("\nNo deck_response events found. Exiting.");
    return;
  }

  if (likes.length === 0) {
    console.log("\nNo likes found. Exiting.");
    return;
  }

  // Group data by session
  console.log("\nProcessing data...");
  const { sessionToServedItems, sessionToVariant } = groupDeckResponsesBySession(deckResponses, filterVariant);
  const sessionToLikes = groupLikesBySession(likes);

  console.log(`Sessions with deck_response: ${sessionToServedItems.size}`);
  console.log(`Sessions with likes: ${sessionToLikes.size}`);

  // Compute metric
  const { totalSessions, sessionsWithLikes, avgLikedInTopK, results } = computeLikedInTopK(
    sessionToServedItems,
    sessionToLikes,
    sessionToVariant,
    minLikes
  );

  // Compute by variant
  const byVariant = computeByVariant(results);

  // Print summary
  console.log(`\n=== Summary ===`);
  console.log(`Total sessions with likes: ${totalSessions}`);
  console.log(`Sessions meeting criteria (>= ${minLikes} likes): ${sessionsWithLikes}`);
  console.log(`Average Liked-in-top-K: ${(avgLikedInTopK * 100).toFixed(2)}%`);

  if (byVariant.length > 0) {
    console.log(`\n=== By Variant ===`);
    for (const variantStat of byVariant) {
      console.log(
        `  ${variantStat.variant}: ${variantStat.sessionsWithLikes} sessions, ` +
        `avg Liked-in-top-K: ${(variantStat.avgLikedInTopK * 100).toFixed(2)}%`
      );
    }
  }

  // Write detailed results to JSON
  const outputPath = path.join(__dirname, "../../../.cursor/offline_eval_results.json");
  const outputDir = path.dirname(outputPath);
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const output = {
    timestamp: new Date().toISOString(),
    config: {
      daysBack,
      filterVariant,
      minLikes,
    },
    summary: {
      totalSessions,
      sessionsWithLikes,
      avgLikedInTopK,
    },
    byVariant,
    perSession: results,
  };

  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
  console.log(`\nDetailed results written to: ${outputPath}`);
  console.log(`\n=== Evaluation complete ===\n`);
}

// Run evaluation and exit
runEvaluation()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Evaluation failed:", err);
    process.exit(1);
  });
