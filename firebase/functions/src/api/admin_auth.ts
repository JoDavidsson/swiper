import { Request, Response } from "express";
import * as admin from "firebase-admin";

export interface AdminUser {
  uid: string;
  email: string | null;
}

/**
 * Verify Authorization: Bearer <idToken> and check Firestore adminAllowlist.
 * Collection adminAllowlist: document ID = allowed email (e.g. admin@example.com).
 * Returns admin user info or null if missing/invalid/not allowlisted.
 */
export async function requireAdminAuth(req: Request, res: Response): Promise<AdminUser | null> {
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) return null;

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    const uid = decoded.uid;
    const email = (decoded.email as string) || null;
    if (!email) return null;

    const db = admin.firestore();
    const allowlistDoc = await db.collection("adminAllowlist").doc(email).get();
    if (!allowlistDoc.exists) return null;

    return { uid, email };
  } catch {
    return null;
  }
}
