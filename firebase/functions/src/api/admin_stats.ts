import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function adminStatsGet(req: Request, res: Response): Promise<void> {
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
}
