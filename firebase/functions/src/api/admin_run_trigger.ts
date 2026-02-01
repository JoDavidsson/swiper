import { Request } from "firebase-functions/v2/https";
import { Response } from "express";

const SUPPLY_ENGINE_URL = process.env.SUPPLY_ENGINE_URL || "http://localhost:8081";

export async function adminRunTriggerPost(req: Request, res: Response): Promise<void> {
  const body = req.body as Record<string, unknown> | undefined;
  const sourceId = body?.sourceId as string;
  if (!sourceId) {
    res.status(400).json({ error: "sourceId required" });
    return;
  }
  try {
    const url = `${SUPPLY_ENGINE_URL.replace(/\/$/, "")}/run/${sourceId}`;
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" } });
    const text = await r.text();
    if (!r.ok) {
      res.status(r.status).json({ error: text || "Supply engine error" });
      return;
    }
    let data: unknown;
    try {
      data = JSON.parse(text);
    } catch {
      data = { message: text };
    }
    res.status(200).json(data);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e) });
  }
}
