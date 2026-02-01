import { Request } from "firebase-functions/v2/https";
import { Response } from "express";

export async function adminVerifyPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const password = body?.password as string;
  const adminPassword = process.env.ADMIN_PASSWORD || "";

  if (!adminPassword) {
    res.status(500).json({ ok: false, error: "Admin not configured" });
    return;
  }

  const ok = password === adminPassword;
  res.status(200).json({ ok });
}
