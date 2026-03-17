import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import {
  allowLegacyAdminPassword,
  isLegacyAdminPasswordValid,
  requireAdminAuth,
} from "./admin_auth";

export async function adminVerifyPost(req: Request, res: Response): Promise<void> {
  // 1) Firebase Auth: Bearer token + allowlist
  const adminUser = await requireAdminAuth(req);
  if (adminUser) {
    res.status(200).json({ ok: true });
    return;
  }

  // 2) Legacy: password (no token for subsequent admin calls; use Sign in with Google for full access)
  const body = req.body as Record<string, unknown> | undefined;
  const password = body?.password as string;
  if (!allowLegacyAdminPassword()) {
    res.status(401).json({
      ok: false,
      error: "Password login is disabled for this environment. Use Sign in with Google and add your email to adminAllowlist.",
    });
    return;
  }

  const ok = isLegacyAdminPasswordValid(password);
  res.status(200).json({ ok });
}
