import { buildDerivedProfile, buildExplanation, buildPickHash, parseConstraints } from "./onboarding_v2";

describe("onboarding_v2 helpers", () => {
  it("builds derived profile with confidence and explanation", () => {
    const profile = buildDerivedProfile(
      ["warm_organic", "calm_minimal"],
      ["rounded_boucle"],
      {
        budgetBand: "5k_15k",
        seatCount: "3",
        kidsPets: true,
      }
    );

    expect(profile.primaryStyle).toBe("warm_organic");
    expect(profile.secondaryStyle).toBe("calm_minimal");
    expect(profile.confidence).toBeGreaterThan(0.5);
    expect(profile.explanation).toContain("Warm neutrals");
    expect(profile.explanation).toContain("Rounded soft forms");
    expect(profile.explanation).toContain("Family-friendly durability");
  });

  it("parses constraints safely", () => {
    const constraints = parseConstraints({
      budgetBand: "5k_15k",
      seatCount: "4_plus",
      modularOnly: true,
      kidsPets: false,
      smallSpace: true,
    });

    expect(constraints).toEqual({
      budgetBand: "5k_15k",
      seatCount: "4_plus",
      modularOnly: true,
      kidsPets: false,
      smallSpace: true,
    });
  });

  it("builds deterministic pick hash", () => {
    const a = buildPickHash(["b", "a"], ["d", "c"]);
    const b = buildPickHash(["a", "b"], ["c", "d"]);
    expect(a).toBe(b);
    expect(a).toBe("a-b-c-d");
  });

  it("build explanation limits output size", () => {
    const explanation = buildExplanation(
      ["warm_organic", "calm_minimal", "bold_eclectic", "urban_industrial"],
      ["rounded_boucle", "low_profile_linen", "structured_leather", "modular_cloud"],
      { modularOnly: true, kidsPets: true, smallSpace: true }
    );
    expect(explanation.length).toBeLessThanOrEqual(4);
  });
});
