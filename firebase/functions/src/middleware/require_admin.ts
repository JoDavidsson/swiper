import { Request } from "express";
import { isLegacyAdminPasswordValid, requireAdminAuth } from "../api/admin_auth";

/**
 * Check if the request is from an admin user.
 * Uses either Firebase Auth token + allowlist OR X-Admin-Password header.
 * Returns true if admin, false otherwise.
 */
export async function requireAdmin(req: Request): Promise<boolean> {
  const passwordHeader = req.headers["x-admin-password"] as string | undefined;
  if (isLegacyAdminPasswordValid(passwordHeader)) return true;

  const adminUser = await requireAdminAuth(req);
  return adminUser != null;
}
