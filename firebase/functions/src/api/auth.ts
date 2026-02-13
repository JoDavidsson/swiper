import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { requireUserAuth, ensureUserDocument } from "../middleware/require_user_auth";

/**
 * POST /api/auth/link-session
 * Links an anonymous session to the authenticated user account.
 * This migrates session data (likes, swipes, preferences) to be associated with the user.
 */
export async function authLinkSessionPost(req: Request, res: Response): Promise<void> {
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const { sessionId } = req.body;
  if (!sessionId || typeof sessionId !== "string") {
    res.status(400).json({ error: "sessionId is required" });
    return;
  }

  const db = admin.firestore();

  try {
    // Ensure user document exists
    await ensureUserDocument(user);

    // Get the user document to check existing linked sessions
    const userRef = db.collection("users").doc(user.uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data();
    const linkedSessionIds: string[] = userData?.linkedSessionIds || [];

    // Check if session is already linked
    if (linkedSessionIds.includes(sessionId)) {
      res.json({
        success: true,
        message: "Session already linked",
        userId: user.uid,
      });
      return;
    }

    // Verify the session exists
    const sessionRef = db.collection("anonSessions").doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      res.status(404).json({ error: "Session not found" });
      return;
    }

    // Link the session to the user
    await userRef.update({
      linkedSessionIds: FieldValue.arrayUnion(sessionId),
      lastActiveAt: FieldValue.serverTimestamp(),
    });

    // Update the session to reference the user
    await sessionRef.update({
      userId: user.uid,
      linkedAt: FieldValue.serverTimestamp(),
    });

    res.json({
      success: true,
      message: "Session linked successfully",
      userId: user.uid,
    });
  } catch (error) {
    console.error("Error linking session:", error);
    res.status(500).json({ error: "Failed to link session" });
  }
}

/**
 * GET /api/auth/me
 * Returns the current authenticated user's profile.
 */
export async function authMeGet(req: Request, res: Response): Promise<void> {
  const user = await requireUserAuth(req);
  if (!user) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }

  const db = admin.firestore();

  try {
    // Ensure user document exists and is up to date
    await ensureUserDocument(user);

    // Get the full user profile
    const userRef = db.collection("users").doc(user.uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data();

    if (!userData) {
      res.status(404).json({ error: "User profile not found" });
      return;
    }

    res.json({
      id: user.uid,
      email: userData.email,
      displayName: userData.displayName,
      photoUrl: userData.photoUrl,
      linkedSessionIds: userData.linkedSessionIds || [],
      createdAt: userData.createdAt?.toDate?.()?.toISOString() || null,
      lastActiveAt: userData.lastActiveAt?.toDate?.()?.toISOString() || null,
    });
  } catch (error) {
    console.error("Error getting user profile:", error);
    res.status(500).json({ error: "Failed to get user profile" });
  }
}
