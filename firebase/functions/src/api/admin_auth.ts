import { Request } from "express";
import * as admin from "firebase-admin";

export interface AdminUser {
  uid: string;
  email: string | null;
}

function isTruthy(value: string | undefined): boolean {
  if (!value) return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes" || normalized === "on";
}

function isEmulatorEnvironment(): boolean {
  return isTruthy(process.env.FUNCTIONS_EMULATOR) ||
    Boolean(process.env.FIRESTORE_EMULATOR_HOST) ||
    Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST);
}

export function allowLegacyAdminPassword(): boolean {
  if (process.env.ALLOW_LEGACY_ADMIN_PASSWORD != null) {
    return isTruthy(process.env.ALLOW_LEGACY_ADMIN_PASSWORD);
  }
  return isEmulatorEnvironment();
}

export function isLegacyAdminPasswordValid(password: string | null | undefined): boolean {
  const adminPassword = process.env.ADMIN_PASSWORD || "";
  return allowLegacyAdminPassword() &&
    adminPassword.length > 0 &&
    typeof password === "string" &&
    password === adminPassword;
}

/**
 * Verify Authorization: Bearer <idToken> and check Firestore adminAllowlist.
 * Collection adminAllowlist: document ID = allowed email (e.g. admin@example.com).
 * Returns admin user info or null if missing/invalid/not allowlisted.
 */
export async function requireAdminAuth(req: Request): Promise<AdminUser | null> {
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
