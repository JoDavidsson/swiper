import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

const UTM_SOURCE = "Swiper";
const UTM_MEDIUM = "referral";
const UTM_CAMPAIGN = "beta";

/** Allowed URL schemes for redirect. */
function isAllowedUrl(url: string): boolean {
  try {
    const u = new URL(url);
    if (u.protocol !== "https:") return false;
    return true;
  } catch {
    return false;
  }
}

/** Append UTM params to URL. */
function appendUtm(url: string, utmContent?: string): string {
  const u = new URL(url);
  u.searchParams.set("utm_source", UTM_SOURCE);
  u.searchParams.set("utm_medium", UTM_MEDIUM);
  u.searchParams.set("utm_campaign", UTM_CAMPAIGN);
  if (utmContent) u.searchParams.set("utm_content", utmContent);
  return u.toString();
}

export async function goHandler(req: Request, res: Response): Promise<void> {
  const itemId = req.path.replace(/^\/go\/?/, "").replace(/\/$/, "");
  if (!itemId) {
    res.status(400).send("Missing itemId");
    return;
  }

  const db = admin.firestore();
  const itemSnap = await db.collection("items").doc(itemId).get();
  if (!itemSnap.exists) {
    res.status(404).send("Item not found");
    return;
  }

  const data = itemSnap.data()!;
  const outboundUrl = data.outboundUrl as string | undefined;
  if (!outboundUrl || !isAllowedUrl(outboundUrl)) {
    res.status(400).send("Invalid or missing outbound URL");
    return;
  }

  const sessionId = (req.query.sessionId as string) || (req.headers["x-session-id"] as string) || "";
  const ref = (req.query.ref as string) || "detail";

  await db.collection("events").add({
    sessionId: sessionId || null,
    eventType: "outbound_click",
    itemId,
    metadata: { destinationDomain: new URL(outboundUrl).hostname, ref },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const finalUrl = appendUtm(outboundUrl, ref);
  res.redirect(302, finalUrl);
}
