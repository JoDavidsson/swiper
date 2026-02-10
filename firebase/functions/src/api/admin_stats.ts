import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_WINDOW_DAYS = 7;
const WEEK_MS = WEEK_WINDOW_DAYS * DAY_MS;
const BASELINE_WINDOW_DAYS = 8;
const MAX_EVENTS_V1_SCAN = 30000;

const SUBMIT_FAILURE_ALERT_THRESHOLD = 0.02;
const SUBMIT_FAILURE_ALERT_MIN_SAMPLES = 20;
const LATENCY_REGRESSION_ALERT_THRESHOLD = 0.15;
const LATENCY_REGRESSION_ALERT_MIN_SAMPLES = 30;
const NEAR_DUPLICATE_RATE_ALERT_THRESHOLD = 0.2;
const NEAR_DUPLICATE_RATE_ALERT_MIN_SAMPLES = 20;
const FALLBACK_RECYCLED_RATE_ALERT_THRESHOLD = 0.08;
const FALLBACK_ALERT_MIN_SAMPLES = 20;

type DeckObservation = {
  timestampMs: number;
  latencyMs: number;
  sameFamilyTop8Rate?: number;
  styleDistanceTop4Min?: number;
  fallbackStage?: "none" | "recycled_seen_items" | "catalog_exhausted";
  droppedHardNearDuplicate?: number;
  droppedSoftNearDuplicate?: number;
  droppedSoftForQuality?: number;
  droppedSoftForStyleDistance?: number;
  allowedSoftNearDuplicate?: number;
};

type WeeklyExperimentEvent = {
  eventName: string;
  sessionId: string;
  rankVariant?: string;
  sameFamilyTop8Rate?: number;
  styleDistanceTop4Min?: number;
};

function asObject(value: unknown): Record<string, unknown> | null {
  if (value == null || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function asTimestampMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function round(value: number, decimals = 2): number {
  const scale = Math.pow(10, decimals);
  return Math.round(value * scale) / scale;
}

function average(values: Array<number | null | undefined>): number | null {
  const finite = values.filter((v): v is number => typeof v === "number" && Number.isFinite(v));
  if (finite.length === 0) return null;
  const total = finite.reduce((sum, v) => sum + v, 0);
  return total / finite.length;
}

function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  const bounded = Math.max(0, Math.min(sorted.length - 1, idx));
  return sorted[bounded];
}

export function buildGoldenV2ObservabilitySummary(params: {
  nowMs: number;
  introShownCount: number;
  stepViewedCount: number;
  stepCompletedCount: number;
  summaryConfirmedCount: number;
  skippedCount: number;
  attemptedSessionCount: number;
  completedProfileCount: number;
  deckObservations: DeckObservation[];
  sampledEventCount: number;
  sampleCap: number;
}): Record<string, unknown> {
  const currentWindowStart = params.nowMs - DAY_MS;
  const baselineWindowStart = params.nowMs - BASELINE_WINDOW_DAYS * DAY_MS;

  const completionRatePct =
    params.introShownCount > 0
      ? round((params.summaryConfirmedCount / params.introShownCount) * 100)
      : 0;
  const skipRatePct =
    params.introShownCount > 0
      ? round((params.skippedCount / params.introShownCount) * 100)
      : 0;

  const estimatedFailedSubmissions = Math.max(
    0,
    params.attemptedSessionCount - params.completedProfileCount
  );
  const submitFailureRate =
    params.attemptedSessionCount > 0
      ? estimatedFailedSubmissions / params.attemptedSessionCount
      : 0;
  const submitFailureRatePct = round(submitFailureRate * 100);
  const submitFailureAlertTriggered =
    params.attemptedSessionCount >= SUBMIT_FAILURE_ALERT_MIN_SAMPLES &&
    submitFailureRate > SUBMIT_FAILURE_ALERT_THRESHOLD;

  const currentDeckSamples = params.deckObservations.filter(
    (sample) => sample.timestampMs >= currentWindowStart
  );
  const baselineDeckSamples = params.deckObservations.filter(
    (sample) =>
      sample.timestampMs < currentWindowStart && sample.timestampMs >= baselineWindowStart
  );

  const currentLatencies = currentDeckSamples.map((sample) => sample.latencyMs);
  const baselineLatencies = baselineDeckSamples.map((sample) => sample.latencyMs);

  const currentP95 = percentile(currentLatencies, 95);
  const baselineP95 = percentile(baselineLatencies, 95);
  const latencyRegression =
    currentP95 != null && baselineP95 != null && baselineP95 > 0
      ? (currentP95 - baselineP95) / baselineP95
      : 0;
  const latencyRegressionPct = round(latencyRegression * 100);
  const latencyAlertTriggered =
    currentLatencies.length >= LATENCY_REGRESSION_ALERT_MIN_SAMPLES &&
    baselineLatencies.length >= LATENCY_REGRESSION_ALERT_MIN_SAMPLES &&
    latencyRegression > LATENCY_REGRESSION_ALERT_THRESHOLD;

  const sameFamilyTop8RateAvg = average(
    currentDeckSamples.map((sample) => sample.sameFamilyTop8Rate)
  );
  const styleDistanceTop4MinAvg = average(
    currentDeckSamples.map((sample) => sample.styleDistanceTop4Min)
  );
  const droppedHardNearDuplicateAvg = average(
    currentDeckSamples.map((sample) => sample.droppedHardNearDuplicate)
  );
  const droppedSoftNearDuplicateAvg = average(
    currentDeckSamples.map((sample) => sample.droppedSoftNearDuplicate)
  );
  const droppedSoftForQualityAvg = average(
    currentDeckSamples.map((sample) => sample.droppedSoftForQuality)
  );
  const droppedSoftForStyleDistanceAvg = average(
    currentDeckSamples.map((sample) => sample.droppedSoftForStyleDistance)
  );
  const allowedSoftNearDuplicateAvg = average(
    currentDeckSamples.map((sample) => sample.allowedSoftNearDuplicate)
  );
  const nearDuplicateRateAlertTriggered =
    currentDeckSamples.length >= NEAR_DUPLICATE_RATE_ALERT_MIN_SAMPLES &&
    (sameFamilyTop8RateAvg ?? 0) > NEAR_DUPLICATE_RATE_ALERT_THRESHOLD;

  const fallbackStageCounts = {
    none: 0,
    recycledSeenItems: 0,
    catalogExhausted: 0,
  };
  for (const sample of currentDeckSamples) {
    if (sample.fallbackStage === "recycled_seen_items") {
      fallbackStageCounts.recycledSeenItems += 1;
      continue;
    }
    if (sample.fallbackStage === "catalog_exhausted") {
      fallbackStageCounts.catalogExhausted += 1;
      continue;
    }
    fallbackStageCounts.none += 1;
  }
  const recycledRate =
    currentDeckSamples.length > 0
      ? fallbackStageCounts.recycledSeenItems / currentDeckSamples.length
      : 0;
  const catalogExhaustedRate =
    currentDeckSamples.length > 0
      ? fallbackStageCounts.catalogExhausted / currentDeckSamples.length
      : 0;
  const fallbackAlertTriggered =
    currentDeckSamples.length >= FALLBACK_ALERT_MIN_SAMPLES &&
    (fallbackStageCounts.catalogExhausted > 0 ||
      recycledRate > FALLBACK_RECYCLED_RATE_ALERT_THRESHOLD);

  return {
    funnel24h: {
      introShown: params.introShownCount,
      stepViewed: params.stepViewedCount,
      stepCompleted: params.stepCompletedCount,
      summaryConfirmed: params.summaryConfirmedCount,
      skipped: params.skippedCount,
      completionRatePct,
      skipRatePct,
    },
    submitReliability24h: {
      attemptedSessions: params.attemptedSessionCount,
      completedProfiles: params.completedProfileCount,
      estimatedFailedSubmissions,
      failureRatePct: submitFailureRatePct,
      alert: {
        triggered: submitFailureAlertTriggered,
        thresholdPct: SUBMIT_FAILURE_ALERT_THRESHOLD * 100,
        minSamples: SUBMIT_FAILURE_ALERT_MIN_SAMPLES,
      },
    },
    deckLatency24h: {
      sampleCount: currentLatencies.length,
      baselineSampleCount: baselineLatencies.length,
      currentP95Ms: currentP95 != null ? round(currentP95) : null,
      baselineP95Ms: baselineP95 != null ? round(baselineP95) : null,
      regressionPct: latencyRegressionPct,
      alert: {
        triggered: latencyAlertTriggered,
        thresholdPct: LATENCY_REGRESSION_ALERT_THRESHOLD * 100,
        minSamples: LATENCY_REGRESSION_ALERT_MIN_SAMPLES,
      },
    },
    deckQuality24h: {
      sampleCount: currentDeckSamples.length,
      sameFamilyTop8RateAvg:
        sameFamilyTop8RateAvg != null ? round(sameFamilyTop8RateAvg) : null,
      styleDistanceTop4MinAvg:
        styleDistanceTop4MinAvg != null ? round(styleDistanceTop4MinAvg) : null,
      nearDuplicateShapingAvg: {
        droppedHardNearDuplicate:
          droppedHardNearDuplicateAvg != null ? round(droppedHardNearDuplicateAvg) : null,
        droppedSoftNearDuplicate:
          droppedSoftNearDuplicateAvg != null ? round(droppedSoftNearDuplicateAvg) : null,
        droppedSoftForQuality:
          droppedSoftForQualityAvg != null ? round(droppedSoftForQualityAvg) : null,
        droppedSoftForStyleDistance:
          droppedSoftForStyleDistanceAvg != null ? round(droppedSoftForStyleDistanceAvg) : null,
        allowedSoftNearDuplicate:
          allowedSoftNearDuplicateAvg != null ? round(allowedSoftNearDuplicateAvg) : null,
      },
      nearDuplicateRateAlert: {
        triggered: nearDuplicateRateAlertTriggered,
        threshold: NEAR_DUPLICATE_RATE_ALERT_THRESHOLD,
        minSamples: NEAR_DUPLICATE_RATE_ALERT_MIN_SAMPLES,
      },
      fallbackStage: {
        counts: fallbackStageCounts,
        ratesPct: {
          recycledSeenItems: round(recycledRate * 100),
          catalogExhausted: round(catalogExhaustedRate * 100),
        },
        alert: {
          triggered: fallbackAlertTriggered,
          recycledRateThresholdPct: FALLBACK_RECYCLED_RATE_ALERT_THRESHOLD * 100,
          minSamples: FALLBACK_ALERT_MIN_SAMPLES,
        },
      },
    },
    sampling: {
      eventsV1SampledCount: params.sampledEventCount,
      sampleCap: params.sampleCap,
      isTruncated: params.sampledEventCount >= params.sampleCap,
    },
  };
}

export function buildWeeklyExperimentCohortSummary(params: {
  nowMs: number;
  events: WeeklyExperimentEvent[];
}): Record<string, unknown> {
  const variantBySession = new Map<string, string>();
  for (const event of params.events) {
    if (event.sessionId.length > 0 && event.rankVariant && event.rankVariant.length > 0) {
      if (!variantBySession.has(event.sessionId)) {
        variantBySession.set(event.sessionId, event.rankVariant);
      }
    }
  }

  type CohortAccumulator = {
    cohortId: string;
    sessions: Set<string>;
    introShownSessions: Set<string>;
    summaryConfirmedSessions: Set<string>;
    skippedSessions: Set<string>;
    deckResponses: number;
    swipeRightCount: number;
    swipeLeftCount: number;
    sameFamilyTop8RateValues: number[];
    styleDistanceTop4MinValues: number[];
  };

  const cohorts = new Map<string, CohortAccumulator>();

  const getCohort = (cohortId: string): CohortAccumulator => {
    const existing = cohorts.get(cohortId);
    if (existing) return existing;
    const created: CohortAccumulator = {
      cohortId,
      sessions: new Set<string>(),
      introShownSessions: new Set<string>(),
      summaryConfirmedSessions: new Set<string>(),
      skippedSessions: new Set<string>(),
      deckResponses: 0,
      swipeRightCount: 0,
      swipeLeftCount: 0,
      sameFamilyTop8RateValues: [],
      styleDistanceTop4MinValues: [],
    };
    cohorts.set(cohortId, created);
    return created;
  };

  for (const event of params.events) {
    const cohortId =
      (event.rankVariant && event.rankVariant.length > 0
        ? event.rankVariant
        : variantBySession.get(event.sessionId)) ?? "unknown";
    const cohort = getCohort(cohortId);
    if (event.sessionId.length > 0) cohort.sessions.add(event.sessionId);

    switch (event.eventName) {
      case "gold_v2_intro_shown":
        if (event.sessionId.length > 0) cohort.introShownSessions.add(event.sessionId);
        break;
      case "gold_v2_summary_confirmed":
        if (event.sessionId.length > 0) cohort.summaryConfirmedSessions.add(event.sessionId);
        break;
      case "gold_v2_skipped":
        if (event.sessionId.length > 0) cohort.skippedSessions.add(event.sessionId);
        break;
      case "deck_response":
        cohort.deckResponses += 1;
        if (typeof event.sameFamilyTop8Rate === "number") {
          cohort.sameFamilyTop8RateValues.push(event.sameFamilyTop8Rate);
        }
        if (typeof event.styleDistanceTop4Min === "number") {
          cohort.styleDistanceTop4MinValues.push(event.styleDistanceTop4Min);
        }
        break;
      case "swipe_right":
        cohort.swipeRightCount += 1;
        break;
      case "swipe_left":
        cohort.swipeLeftCount += 1;
        break;
      default:
        break;
    }
  }

  const cohortRows = Array.from(cohorts.values())
    .map((cohort) => {
      const introCount = cohort.introShownSessions.size;
      const summaryCount = cohort.summaryConfirmedSessions.size;
      const skippedCount = cohort.skippedSessions.size;
      const totalSwipes = cohort.swipeRightCount + cohort.swipeLeftCount;
      const swipeRightRatePct =
        totalSwipes > 0 ? round((cohort.swipeRightCount / totalSwipes) * 100) : null;
      const completionRatePct =
        introCount > 0 ? round((summaryCount / introCount) * 100) : 0;
      const skipRatePct = introCount > 0 ? round((skippedCount / introCount) * 100) : 0;

      return {
        cohortId: cohort.cohortId,
        sessionCount: cohort.sessions.size,
        introShownSessions: introCount,
        summaryConfirmedSessions: summaryCount,
        skippedSessions: skippedCount,
        completionRatePct,
        skipRatePct,
        swipeRightCount: cohort.swipeRightCount,
        swipeLeftCount: cohort.swipeLeftCount,
        swipeRightRatePct,
        deckResponses: cohort.deckResponses,
        sameFamilyTop8RateAvg:
          cohort.sameFamilyTop8RateValues.length > 0
            ? round(cohort.sameFamilyTop8RateValues.reduce((sum, v) => sum + v, 0) /
                cohort.sameFamilyTop8RateValues.length)
            : null,
        styleDistanceTop4MinAvg:
          cohort.styleDistanceTop4MinValues.length > 0
            ? round(cohort.styleDistanceTop4MinValues.reduce((sum, v) => sum + v, 0) /
                cohort.styleDistanceTop4MinValues.length)
            : null,
      };
    })
    .sort((a, b) => b.sessionCount - a.sessionCount);

  return {
    windowDays: WEEK_WINDOW_DAYS,
    generatedAtMs: params.nowMs,
    cohortCount: cohortRows.length,
    cohorts: cohortRows,
  };
}

function emptyGoldenV2Summary(nowMs: number): Record<string, unknown> {
  const summary = buildGoldenV2ObservabilitySummary({
    nowMs,
    introShownCount: 0,
    stepViewedCount: 0,
    stepCompletedCount: 0,
    summaryConfirmedCount: 0,
    skippedCount: 0,
    attemptedSessionCount: 0,
    completedProfileCount: 0,
    deckObservations: [],
    sampledEventCount: 0,
    sampleCap: MAX_EVENTS_V1_SCAN,
  });
  return {
    ...summary,
    experimentWeeklyByCohort: buildWeeklyExperimentCohortSummary({
      nowMs,
      events: [],
    }),
  };
}

export async function adminStatsGet(req: Request, res: Response): Promise<void> {
  try {
    const db = admin.firestore();
    const now = Timestamp.now();
    const nowMs = now.toMillis();
    const oneDayAgo = Timestamp.fromMillis(nowMs - DAY_MS);
    const oneWeekAgo = Timestamp.fromMillis(nowMs - WEEK_MS);
    const baselineStart = Timestamp.fromMillis(nowMs - BASELINE_WINDOW_DAYS * DAY_MS);

    const [sessionsSnap, swipesSnap, likesSnap, outboundClicksSnap, eventsV1Snap, completedProfilesSnap] =
      await Promise.all([
        db.collection("anonSessions").where("lastSeenAt", ">=", oneDayAgo).get(),
        db.collection("swipes").limit(5000).get(),
        db.collection("likes").limit(5000).get(),
        db.collection("events").where("eventType", "==", "outbound_click").limit(5000).get(),
        db
          .collection("events_v1")
          .where("createdAtServer", ">=", baselineStart)
          .orderBy("createdAtServer", "desc")
          .limit(MAX_EVENTS_V1_SCAN)
          .get(),
        db
          .collection("onboardingProfiles")
          .where("status", "==", "completed")
          .where("updatedAt", ">=", oneDayAgo)
          .get(),
      ]);

    const dailySessions = sessionsSnap.size;
    const totalSwipes = swipesSnap.size;
    const totalLikes = likesSnap.size;
    const outboundClicks = outboundClicksSnap.size;
    const likeRate = totalSwipes > 0 ? (totalLikes / totalSwipes) * 100 : 0;

    let introShown24h = 0;
    let stepViewed24h = 0;
    let stepCompleted24h = 0;
    let summaryConfirmed24h = 0;
    let skipped24h = 0;
    const attemptedSessionIds = new Set<string>();
    const deckObservations: DeckObservation[] = [];
    const weeklyExperimentEvents: WeeklyExperimentEvent[] = [];

    for (const doc of eventsV1Snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const createdAtMs = asTimestampMillis(data.createdAtServer);
      if (createdAtMs == null) continue;

      const eventName = typeof data.eventName === "string" ? data.eventName : "";
      const sessionId = typeof data.sessionId === "string" ? data.sessionId : "";
      const rank = asObject(data.rank);
      const rankVariant =
        typeof rank?.variant === "string" && rank.variant.length > 0
          ? rank.variant
          : undefined;
      const inCurrentWindow = createdAtMs >= oneDayAgo.toMillis();
      const inWeeklyWindow = createdAtMs >= oneWeekAgo.toMillis();

      if (inWeeklyWindow) {
        weeklyExperimentEvents.push({
          eventName,
          sessionId,
          rankVariant,
          sameFamilyTop8Rate: asNumber(rank?.sameFamilyTop8Rate) ?? undefined,
          styleDistanceTop4Min: asNumber(rank?.styleDistanceTop4Min) ?? undefined,
        });
      }

      if (inCurrentWindow) {
        if (eventName === "gold_v2_intro_shown") introShown24h += 1;
        if (eventName === "gold_v2_step_viewed") stepViewed24h += 1;
        if (eventName === "gold_v2_step_completed") stepCompleted24h += 1;
        if (eventName === "gold_v2_summary_confirmed") {
          summaryConfirmed24h += 1;
          if (sessionId.length > 0) attemptedSessionIds.add(sessionId);
        }
        if (eventName === "gold_v2_skipped") skipped24h += 1;
      }

      if (eventName !== "deck_response") continue;

      const perf = asObject(data.perf);
      const latencyMs = asNumber(perf?.latencyMs);
      if (latencyMs == null) continue;
      const nearDuplicateShaping = asObject(rank?.nearDuplicateShaping);
      const fallbackStageRaw =
        typeof rank?.fallbackStage === "string" ? rank.fallbackStage : null;
      const fallbackStage =
        fallbackStageRaw === "none" ||
        fallbackStageRaw === "recycled_seen_items" ||
        fallbackStageRaw === "catalog_exhausted"
          ? fallbackStageRaw
          : undefined;

      deckObservations.push({
        timestampMs: createdAtMs,
        latencyMs,
        sameFamilyTop8Rate: asNumber(rank?.sameFamilyTop8Rate) ?? undefined,
        styleDistanceTop4Min: asNumber(rank?.styleDistanceTop4Min) ?? undefined,
        fallbackStage,
        droppedHardNearDuplicate:
          asNumber(nearDuplicateShaping?.droppedHardNearDuplicate) ?? undefined,
        droppedSoftNearDuplicate:
          asNumber(nearDuplicateShaping?.droppedSoftNearDuplicate) ?? undefined,
        droppedSoftForQuality:
          asNumber(nearDuplicateShaping?.droppedSoftForQuality) ?? undefined,
        droppedSoftForStyleDistance:
          asNumber(nearDuplicateShaping?.droppedSoftForStyleDistance) ?? undefined,
        allowedSoftNearDuplicate:
          asNumber(nearDuplicateShaping?.allowedSoftNearDuplicate) ?? undefined,
      });
    }

    const goldenV2 = {
      ...buildGoldenV2ObservabilitySummary({
        nowMs,
        introShownCount: introShown24h,
        stepViewedCount: stepViewed24h,
        stepCompletedCount: stepCompleted24h,
        summaryConfirmedCount: summaryConfirmed24h,
        skippedCount: skipped24h,
        attemptedSessionCount: attemptedSessionIds.size,
        completedProfileCount: completedProfilesSnap.size,
        deckObservations,
        sampledEventCount: eventsV1Snap.size,
        sampleCap: MAX_EVENTS_V1_SCAN,
      }),
      experimentWeeklyByCohort: buildWeeklyExperimentCohortSummary({
        nowMs,
        events: weeklyExperimentEvents,
      }),
    };

    res.status(200).json({
      dailySessions,
      totalSwipes,
      totalLikes,
      outboundClicks,
      likeRate: round(likeRate, 1),
      goldenV2,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("admin/stats error:", message, err);
    const nowMs = Date.now();
    // Return 200 with zero stats so dashboard still loads; real error is in logs.
    res.status(200).json({
      dailySessions: 0,
      totalSwipes: 0,
      totalLikes: 0,
      outboundClicks: 0,
      likeRate: 0,
      goldenV2: emptyGoldenV2Summary(nowMs),
    });
  }
}

export const __adminStatsTestUtils = {
  average,
  percentile,
  buildGoldenV2ObservabilitySummary,
  buildWeeklyExperimentCohortSummary,
};
