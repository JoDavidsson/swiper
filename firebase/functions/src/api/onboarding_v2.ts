import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { FieldValue } from "../firestore";

export type Constraints = {
  budgetBand?: string;
  seatCount?: string;
  modularOnly?: boolean;
  kidsPets?: boolean;
  smallSpace?: boolean;
};

export type DerivedProfile = {
  primaryStyle: string | null;
  secondaryStyle: string | null;
  confidence: number;
  explanation: string[];
};

const MAX_OPTION_COUNT = 8;

function asStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => {
      if (typeof entry !== "string") return null;
      const normalized = entry.trim().toLowerCase();
      return normalized.length > 0 ? normalized : null;
    })
    .filter((entry): entry is string => entry != null)
    .slice(0, MAX_OPTION_COUNT);
}

function asBool(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value;
  return undefined;
}

function asRawString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function asNormalizedToken(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase();
  return normalized.length > 0 ? normalized : undefined;
}

export function parseConstraints(value: unknown): Constraints {
  const c = (typeof value === "object" && value != null)
    ? (value as Record<string, unknown>)
    : {};

  return {
    budgetBand: asNormalizedToken(c.budgetBand),
    seatCount: asNormalizedToken(c.seatCount),
    modularOnly: asBool(c.modularOnly),
    kidsPets: asBool(c.kidsPets),
    smallSpace: asBool(c.smallSpace),
  };
}

export function buildExplanation(sceneArchetypes: string[], sofaVibes: string[], constraints: Constraints): string[] {
  const explanation = new Set<string>();

  const sceneCopy = new Set(sceneArchetypes);
  if (sceneCopy.has("warm_organic")) explanation.add("Warm neutrals");
  if (sceneCopy.has("calm_minimal")) explanation.add("Calm minimal lines");
  if (sceneCopy.has("bold_eclectic")) explanation.add("Expressive contrast");
  if (sceneCopy.has("urban_industrial")) explanation.add("Structured forms");

  const sofaCopy = new Set(sofaVibes);
  if (sofaCopy.has("rounded_boucle")) explanation.add("Rounded soft forms");
  if (sofaCopy.has("low_profile_linen")) explanation.add("Low relaxed profile");
  if (sofaCopy.has("structured_leather")) explanation.add("Tailored silhouettes");
  if (sofaCopy.has("modular_cloud")) explanation.add("Modular flexibility");

  if (constraints.smallSpace) explanation.add("Small-space prioritization");
  if (constraints.modularOnly) explanation.add("Modular-only preference");
  if (constraints.kidsPets) explanation.add("Family-friendly durability");

  return Array.from(explanation).slice(0, 4);
}

export function buildDerivedProfile(
  sceneArchetypes: string[],
  sofaVibes: string[],
  constraints: Constraints
): DerivedProfile {
  const mergedSignals = [...sceneArchetypes, ...sofaVibes];
  const primaryStyle = mergedSignals.length > 0 ? mergedSignals[0] : null;
  const secondaryStyle = mergedSignals.length > 1 ? mergedSignals[1] : null;

  const sceneConfidence = Math.min(0.45, sceneArchetypes.length * 0.225);
  const sofaConfidence = Math.min(0.35, sofaVibes.length * 0.175);
  const constraintsCount = [
    constraints.budgetBand,
    constraints.seatCount,
    constraints.modularOnly === true ? "modularOnly" : undefined,
    constraints.kidsPets === true ? "kidsPets" : undefined,
    constraints.smallSpace === true ? "smallSpace" : undefined,
  ].filter((v) => v != null).length;
  const constraintsConfidence = Math.min(0.2, constraintsCount * 0.04);
  const confidence = Math.min(0.95, Number((sceneConfidence + sofaConfidence + constraintsConfidence).toFixed(2)));

  return {
    primaryStyle,
    secondaryStyle,
    confidence,
    explanation: buildExplanation(sceneArchetypes, sofaVibes, constraints),
  };
}

export function buildPickHash(sceneArchetypes: string[], sofaVibes: string[]): string {
  const merged = [...sceneArchetypes, ...sofaVibes]
    .filter((v) => v.trim().length > 0)
    .sort();
  return merged.join("-");
}

/**
 * POST /api/onboarding/v2
 * Store Golden Card v2 selections and derived style profile.
 */
export async function onboardingV2Post(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  let sessionIdForLog: string | undefined;
  try {
    const body = (req.body || {}) as Record<string, unknown>;
    const sessionId = asRawString(body.sessionId);
    sessionIdForLog = sessionId;
    const sceneArchetypes = asStringList(body.sceneArchetypes);
    const sofaVibes = asStringList(body.sofaVibes);
    const constraints = parseConstraints(body.constraints);

    if (!sessionId) {
      res.status(400).json({ error: "sessionId required" });
      return;
    }

    if (sceneArchetypes.length === 0 && sofaVibes.length === 0) {
      res.status(400).json({ error: "At least one selection set is required" });
      return;
    }

    console.info("onboarding_v2_post_received", {
      sessionId,
      sceneCount: sceneArchetypes.length,
      sofaCount: sofaVibes.length,
      hasBudgetBand: constraints.budgetBand != null,
      hasSeatCount: constraints.seatCount != null,
      modularOnly: constraints.modularOnly === true,
      kidsPets: constraints.kidsPets === true,
      smallSpace: constraints.smallSpace === true,
    });

    const sessionRef = db.collection("anonSessions").doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      await sessionRef.set(
        {
          createdAt: FieldValue.serverTimestamp(),
          lastSeenAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    const derivedProfile = buildDerivedProfile(sceneArchetypes, sofaVibes, constraints);
    const pickHash = buildPickHash(sceneArchetypes, sofaVibes);

    await db.collection("onboardingProfiles").doc(sessionId).set(
      {
        version: 2,
        status: "completed",
        sceneArchetypes,
        sofaVibes,
        constraints,
        derivedProfile,
        pickHash,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    await sessionRef.set(
      {
        hasOnboardingProfileV2: true,
        onboardingV2PickHash: pickHash,
        updatedAt: FieldValue.serverTimestamp(),
        lastSeenAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.info("onboarding_v2_post_stored", {
      sessionId,
      pickHash,
      confidence: derivedProfile.confidence,
      explanationCount: derivedProfile.explanation.length,
    });

    res.status(200).json({
      ok: true,
      pickHash,
      profile: derivedProfile,
    });
  } catch (error) {
    console.error("onboarding_v2_post_failed", {
      sessionId: sessionIdForLog ?? null,
      error: error instanceof Error ? error.message : String(error),
    });
    res.status(500).json({ error: "Failed to store onboarding v2 profile" });
  }
}

/**
 * GET /api/onboarding/v2
 * Returns Golden Card v2 profile for a session.
 */
export async function onboardingV2Get(
  req: Request,
  res: Response
): Promise<void> {
  const db = admin.firestore();
  let sessionIdForLog: string | undefined;
  try {
    const sessionId = asRawString(req.query.sessionId);
    sessionIdForLog = sessionId;

    if (!sessionId) {
      res.status(400).json({ error: "sessionId required" });
      return;
    }

    const profileDoc = await db.collection("onboardingProfiles").doc(sessionId).get();
    if (!profileDoc.exists) {
      console.info("onboarding_v2_get_miss", { sessionId });
      res.status(200).json({ profile: null });
      return;
    }

    const data = profileDoc.data() as Record<string, unknown>;
    console.info("onboarding_v2_get_hit", {
      sessionId,
      version: data.version ?? 2,
      status: data.status ?? "completed",
    });
    res.status(200).json({
      profile: {
        version: data.version ?? 2,
        status: data.status ?? "completed",
        sceneArchetypes: data.sceneArchetypes ?? [],
        sofaVibes: data.sofaVibes ?? [],
        constraints: data.constraints ?? {},
        derivedProfile: data.derivedProfile ?? null,
        pickHash: data.pickHash ?? null,
      },
    });
  } catch (error) {
    console.error("onboarding_v2_get_failed", {
      sessionId: sessionIdForLog ?? null,
      error: error instanceof Error ? error.message : String(error),
    });
    res.status(500).json({ error: "Failed to fetch onboarding v2 profile" });
  }
}
