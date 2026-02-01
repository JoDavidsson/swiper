import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function adminStatsGet(req: Request, res: Response): Promise<void> {
  try {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const oneDayAgo = admin.firestore.Timestamp.fromMillis(now.toMillis() - 24 * 60 * 60 * 1000);

    const [sessionsSnap, swipesSnap, likesSnap, eventsSnap] = await Promise.all([
      db.collection("anonSessions").where("lastSeenAt", ">=", oneDayAgo).get(),
      db.collection("swipes").limit(5000).get(),
      db.collection("likes").limit(5000).get(),
      db.collection("events").where("eventType", "==", "outbound_click").limit(5000).get(),
    ]);

    const dailySessions = sessionsSnap.size;
    const totalSwipes = swipesSnap.size;
    const totalLikes = likesSnap.size;
    const outboundClicks = eventsSnap.size;
    const likeRate = totalSwipes > 0 ? (totalLikes / totalSwipes) * 100 : 0;

    res.status(200).json({
      dailySessions,
      totalSwipes,
      totalLikes,
      outboundClicks,
      likeRate: Math.round(likeRate * 10) / 10,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("admin/stats error:", message, err);
    // Return 200 with zero stats so dashboard still loads; real error is in logs.
    res.status(200).json({
      dailySessions: 0,
      totalSwipes: 0,
      totalLikes: 0,
      outboundClicks: 0,
      likeRate: 0,
    });
  }
}
