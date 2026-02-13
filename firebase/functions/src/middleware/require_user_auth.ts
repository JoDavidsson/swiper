import { Request } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

export interface AuthenticatedUser {
  uid: string;
  email: string | null;
  displayName: string | null;
  photoUrl: string | null;
}

/**
 * Verify Authorization: Bearer <idToken> for regular users.
 * Unlike admin auth, this does not check an allowlist - any authenticated Firebase user is valid.
 * Returns user info or null if missing/invalid token.
 */
export async function requireUserAuth(req: Request): Promise<AuthenticatedUser | null> {
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) return null;

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    return {
      uid: decoded.uid,
      email: decoded.email || null,
      displayName: decoded.name || null,
      photoUrl: decoded.picture || null,
    };
  } catch {
    return null;
  }
}

/**
 * Ensure user document exists in Firestore.
 * Creates or updates the user document with latest auth info.
 */
export async function ensureUserDocument(user: AuthenticatedUser): Promise<void> {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(user.uid);
  const userDoc = await userRef.get();

  const now = FieldValue.serverTimestamp();

  if (!userDoc.exists) {
    // Create new user document
    await userRef.set({
      id: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      linkedSessionIds: [],
      createdAt: now,
      lastActiveAt: now,
    });
  } else {
    // Update last active and any changed fields
    await userRef.update({
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      lastActiveAt: now,
    });
  }
}
