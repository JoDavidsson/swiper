import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { nanoid } from "nanoid";
import { FieldValue } from "../firestore";

/** Normalize User-Agent to a short label (e.g. "Chrome/120") for analytics. No PII. */
function normalizeUserAgent(ua: string | undefined): string | null {
  if (!ua || typeof ua !== "string") return null;
  const s = ua.slice(0, 200);
  const chrome = s.match(/Chrome\/(\d+)/);
  if (chrome) return `Chrome/${chrome[1]}`;
  const safari = s.match(/Version\/(\d+).*Safari/);
  if (safari) return `Safari/${safari[1]}`;
  const firefox = s.match(/Firefox\/(\d+)/);
  if (firefox) return `Firefox/${firefox[1]}`;
  return s ? "other" : null;
}

export async function sessionPost(req: Request, res: Response): Promise<void> {
  const sessionId = nanoid(24);
  const body = (req.body as Record<string, unknown>) || {};
  const locale = typeof body.locale === "string" ? body.locale.slice(0, 20) : null;
  const platform = typeof body.platform === "string" ? body.platform.slice(0, 20) : null;
  const screenBucket = typeof body.screenBucket === "string" ? body.screenBucket.slice(0, 20) : null;
  const tzOffset = typeof body.timezoneOffsetMinutes === "number" ? body.timezoneOffsetMinutes : null;
  const userAgentClient = typeof body.userAgent === "string" ? body.userAgent.slice(0, 300) : null;
  const userAgentHeader = req.headers["user-agent"];
  const userAgent = normalizeUserAgent(userAgentClient || (Array.isArray(userAgentHeader) ? userAgentHeader[0] : userAgentHeader));

  const db = admin.firestore();
  const sessionData: Record<string, unknown> = {
    createdAt: FieldValue.serverTimestamp(),
    lastSeenAt: FieldValue.serverTimestamp(),
  };
  if (locale) sessionData.locale = locale;
  if (platform) sessionData.platform = platform;
  if (screenBucket) sessionData.screenBucket = screenBucket;
  if (tzOffset != null) sessionData.timezoneOffsetMinutes = tzOffset;
  if (userAgent) sessionData.userAgent = userAgent;

  await db.collection("anonSessions").doc(sessionId).set(sessionData);

  res.status(200).json({ sessionId });
}
