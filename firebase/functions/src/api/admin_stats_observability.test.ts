import { __adminStatsTestUtils } from "./admin_stats";

describe("admin_stats golden v2 observability summary", () => {
  it("computes funnel rates from 24h counts", () => {
    const summary = __adminStatsTestUtils.buildGoldenV2ObservabilitySummary({
      nowMs: Date.now(),
      introShownCount: 100,
      stepViewedCount: 80,
      stepCompletedCount: 60,
      summaryConfirmedCount: 50,
      skippedCount: 20,
      attemptedSessionCount: 50,
      completedProfileCount: 49,
      deckObservations: [],
      sampledEventCount: 120,
      sampleCap: 30000,
    });

    const funnel = summary.funnel24h as Record<string, unknown>;
    expect(funnel.completionRatePct).toBe(50);
    expect(funnel.skipRatePct).toBe(20);
  });

  it("triggers submit failure alert above 2% with enough samples", () => {
    const summary = __adminStatsTestUtils.buildGoldenV2ObservabilitySummary({
      nowMs: Date.now(),
      introShownCount: 100,
      stepViewedCount: 90,
      stepCompletedCount: 80,
      summaryConfirmedCount: 70,
      skippedCount: 10,
      attemptedSessionCount: 100,
      completedProfileCount: 95,
      deckObservations: [],
      sampledEventCount: 200,
      sampleCap: 30000,
    });

    const submit = summary.submitReliability24h as Record<string, unknown>;
    const alert = submit.alert as Record<string, unknown>;
    expect(submit.failureRatePct).toBe(5);
    expect(alert.triggered).toBe(true);
  });

  it("triggers latency regression alert when p95 regresses more than 15%", () => {
    const nowMs = Date.now();
    const current = Array.from({ length: 40 }, (_, i) => ({
      timestampMs: nowMs - 60 * 60 * 1000,
      latencyMs: 1000 + i,
      sameFamilyTop8Rate: 0.2,
      styleDistanceTop4Min: 0.5,
    }));
    const baseline = Array.from({ length: 40 }, (_, i) => ({
      timestampMs: nowMs - 3 * 24 * 60 * 60 * 1000,
      latencyMs: 700 + i,
      sameFamilyTop8Rate: 0.25,
      styleDistanceTop4Min: 0.45,
    }));

    const summary = __adminStatsTestUtils.buildGoldenV2ObservabilitySummary({
      nowMs,
      introShownCount: 0,
      stepViewedCount: 0,
      stepCompletedCount: 0,
      summaryConfirmedCount: 0,
      skippedCount: 0,
      attemptedSessionCount: 0,
      completedProfileCount: 0,
      deckObservations: [...current, ...baseline],
      sampledEventCount: 80,
      sampleCap: 30000,
    });

    const latency = summary.deckLatency24h as Record<string, unknown>;
    const alert = latency.alert as Record<string, unknown>;
    expect((latency.regressionPct as number) > 15).toBe(true);
    expect(alert.triggered).toBe(true);
  });

  it("does not trigger alerts when sample sizes are below minimum", () => {
    const nowMs = Date.now();
    const observations = [
      {
        timestampMs: nowMs - 30 * 60 * 1000,
        latencyMs: 1200,
        sameFamilyTop8Rate: 0.3,
        styleDistanceTop4Min: 0.4,
      },
      {
        timestampMs: nowMs - 3 * 24 * 60 * 60 * 1000,
        latencyMs: 600,
        sameFamilyTop8Rate: 0.2,
        styleDistanceTop4Min: 0.5,
      },
    ];

    const summary = __adminStatsTestUtils.buildGoldenV2ObservabilitySummary({
      nowMs,
      introShownCount: 10,
      stepViewedCount: 10,
      stepCompletedCount: 9,
      summaryConfirmedCount: 8,
      skippedCount: 1,
      attemptedSessionCount: 10,
      completedProfileCount: 9,
      deckObservations: observations,
      sampledEventCount: 20,
      sampleCap: 30000,
    });

    const submit = summary.submitReliability24h as Record<string, unknown>;
    const submitAlert = submit.alert as Record<string, unknown>;
    const latency = summary.deckLatency24h as Record<string, unknown>;
    const latencyAlert = latency.alert as Record<string, unknown>;

    expect(submitAlert.triggered).toBe(false);
    expect(latencyAlert.triggered).toBe(false);
  });

  it("builds weekly cohort slices with completion, swipe-rate, and quality metrics", () => {
    const summary = __adminStatsTestUtils.buildWeeklyExperimentCohortSummary({
      nowMs: Date.now(),
      events: [
        {
          eventName: "deck_response",
          sessionId: "s1",
          rankVariant: "personal_only",
          sameFamilyTop8Rate: 0.2,
          styleDistanceTop4Min: 0.4,
        },
        { eventName: "gold_v2_intro_shown", sessionId: "s1" },
        { eventName: "gold_v2_summary_confirmed", sessionId: "s1" },
        { eventName: "swipe_right", sessionId: "s1" },
        { eventName: "swipe_left", sessionId: "s1" },
        {
          eventName: "deck_response",
          sessionId: "s2",
          rankVariant: "personal_only",
          sameFamilyTop8Rate: 0.4,
          styleDistanceTop4Min: 0.6,
        },
        { eventName: "gold_v2_intro_shown", sessionId: "s2" },
        { eventName: "gold_v2_skipped", sessionId: "s2" },
        { eventName: "swipe_right", sessionId: "s2" },
        { eventName: "gold_v2_intro_shown", sessionId: "s3" },
      ],
    });

    const cohorts = summary.cohorts as Array<Record<string, unknown>>;
    const byId = new Map<string, Record<string, unknown>>(
      cohorts.map((cohort) => [cohort.cohortId as string, cohort])
    );

    const personalOnly = byId.get("personal_only");
    expect(personalOnly).toBeDefined();
    expect(personalOnly?.sessionCount).toBe(2);
    expect(personalOnly?.completionRatePct).toBe(50);
    expect(personalOnly?.skipRatePct).toBe(50);
    expect(personalOnly?.swipeRightRatePct).toBe(66.67);
    expect(personalOnly?.sameFamilyTop8RateAvg).toBe(0.3);
    expect(personalOnly?.styleDistanceTop4MinAvg).toBe(0.5);

    const unknown = byId.get("unknown");
    expect(unknown).toBeDefined();
    expect(unknown?.sessionCount).toBe(1);
    expect(unknown?.introShownSessions).toBe(1);
  });

  it("falls back to session-level variant when event-level variant is missing", () => {
    const summary = __adminStatsTestUtils.buildWeeklyExperimentCohortSummary({
      nowMs: Date.now(),
      events: [
        {
          eventName: "deck_response",
          sessionId: "session-a",
          rankVariant: "personal_plus_persona",
        },
        { eventName: "swipe_right", sessionId: "session-a" },
      ],
    });

    const cohorts = summary.cohorts as Array<Record<string, unknown>>;
    const cohort = cohorts.find(
      (entry) => entry.cohortId === "personal_plus_persona"
    );
    expect(cohort).toBeDefined();
    expect(cohort?.swipeRightCount).toBe(1);
    expect(cohort?.sessionCount).toBe(1);
  });
});
