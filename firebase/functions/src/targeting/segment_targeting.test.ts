import {
  buildSessionTargetingProfile,
  evaluateSegmentMatch,
  normalizeSegmentCriteriaInput,
  toSegmentCriteria,
} from "./segment_targeting";

describe("segment_targeting", () => {
  it("normalizes valid criteria and reports invalid fields", () => {
    const { normalized, issues } = normalizeSegmentCriteriaInput({
      styleTags: ["Modern", "modern", "  "],
      budgetMin: 9000,
      budgetMax: 5000,
      sizeClasses: ["small", "unknown"],
      geoRegion: "SE",
      geoCity: 123,
      geoPostcodes: ["114 52", "#bad"],
    });

    expect(normalized.styleTags).toEqual(["modern"]);
    expect(normalized.geoRegion).toBe("sweden");
    expect(normalized.geoPostcodes).toEqual(["11452"]);
    expect(issues.map((issue) => issue.field)).toContain("budgetMin/budgetMax");
    expect(issues.map((issue) => issue.field)).toContain("sizeClasses");
    expect(issues.map((issue) => issue.field)).toContain("geoCity");
    expect(issues.map((issue) => issue.field)).toContain("geoPostcodes");
  });

  it("builds session profile from preference keys and onboarding signals", () => {
    const profile = buildSessionTargetingProfile({
      locale: "sv-SE",
      preferenceWeights: {
        "style:scandinavian": 3,
        "size:compact": 1,
        "material:linen": 2,
      },
      onboardingStyleTokens: ["modern", "minimal"],
      preferredBudgetMin: 5000,
      preferredBudgetMax: 15000,
      explicitSizeClass: "small",
      inferredSizeClasses: ["medium", "invalid"],
    });

    expect(profile.geoRegion).toBe("sweden");
    expect(profile.styleTags).toEqual(
      expect.arrayContaining(["scandinavian", "modern", "minimal"])
    );
    expect(profile.sizeClasses).toEqual(
      expect.arrayContaining(["compact", "small", "medium"])
    );
    expect(profile.budgetMin).toBe(5000);
    expect(profile.budgetMax).toBe(15000);
  });

  it("matches when style, budget, size, and geo overlap", () => {
    const segment = toSegmentCriteria({
      styleTags: ["scandinavian", "minimal"],
      budgetMin: 4000,
      budgetMax: 12000,
      sizeClasses: ["small"],
      geoRegion: "sweden",
      geoCity: "stockholm",
      geoPostcodes: ["11452"],
    });

    const profile = buildSessionTargetingProfile({
      geoRegion: "sweden",
      geoCity: "stockholm",
      geoPostcode: "114 52",
      onboardingStyleTokens: ["minimal"],
      preferredBudgetMin: 6000,
      preferredBudgetMax: 10000,
      inferredSizeClasses: ["small"],
    });

    const match = evaluateSegmentMatch(segment, profile, 0.5);
    expect(match.isMatch).toBe(true);
    expect(match.overallScore).toBeGreaterThan(0.5);
  });

  it("fails when required style does not match", () => {
    const segment = toSegmentCriteria({
      styleTags: ["industrial"],
      geoRegion: "sweden",
    });
    const profile = buildSessionTargetingProfile({
      onboardingStyleTokens: ["minimal"],
      geoRegion: "sweden",
    });

    const match = evaluateSegmentMatch(segment, profile, 0.5);
    expect(match.isMatch).toBe(false);
    expect(match.components.style.matched).toBe(false);
  });
});
