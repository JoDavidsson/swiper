import { Request } from "express";
import * as admin from "firebase-admin";

/**
 * Check if the request is from an admin user.
 * Uses either Firebase Auth token + allowlist OR X-Admin-Password header.
 * Returns true if admin, false otherwise.
 */
export async function requireAdmin(req: Request): Promise<boolean> {
  // Check X-Admin-Password header first
  const passwordHeader = req.headers["x-admin-password"] as string | undefined;
  const adminPassword = process.env.ADMIN_PASSWORD || "";
  if (adminPassword && passwordHeader === adminPassword) {
    return true;
  }

  // Check Firebase Auth token + allowlist
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) return false;

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    const email = decoded.email as string | undefined;
    if (!email) return false;

    const db = admin.firestore();
    const allowlistDoc = await db.collection("adminAllowlist").doc(email).get();
    return allowlistDoc.exists;
  } catch {
    return false;
  }
}
