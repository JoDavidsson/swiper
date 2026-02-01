import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";

export async function adminQaGet(req: Request, res: Response): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection("items").where("isActive", "==", true).limit(1000).get();

  let missingPrice = 0;
  let missingDimensions = 0;
  let missingImages = 0;
  let missingOutboundUrl = 0;
  let missingTags = 0;

  snap.docs.forEach((doc) => {
    const d = doc.data();
    if (d.priceAmount == null || d.priceAmount === 0) missingPrice++;
    if (!d.dimensionsCm || (d.dimensionsCm.w == null && d.dimensionsCm.h == null)) missingDimensions++;
    if (!d.images || (d.images as unknown[]).length === 0) missingImages++;
    if (!d.outboundUrl || !(d.outboundUrl as string).trim()) missingOutboundUrl++;
    if (!d.styleTags || (d.styleTags as unknown[]).length === 0) missingTags++;
  });

  const total = snap.size;
  res.status(200).json({
    total,
    missingPrice,
    missingDimensions,
    missingImages,
    missingOutboundUrl,
    missingTags,
  });
}
