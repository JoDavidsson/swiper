import { __deckTestUtils } from "./deck";

describe("deck v2 helper utilities", () => {
  it("parses onboarding v2 profile", () => {
    const parsed = __deckTestUtils.parseOnboardingV2Profile({
      sceneArchetypes: ["warm_organic", "calm_minimal"],
      sofaVibes: ["rounded_boucle"],
      constraints: {
        budgetBand: "5k_15k",
        seatCount: "3",
        modularOnly: true,
      },
      derivedProfile: {
        primaryStyle: "warm_organic",
        secondaryStyle: "calm_minimal",
        confidence: 0.8,
        explanation: ["Warm neutrals"],
      },
      pickHash: "a-b-c",
    });

    expect(parsed).not.toBeNull();
    expect(parsed?.sceneArchetypes).toEqual(["warm_organic", "calm_minimal"]);
    expect(parsed?.constraints.budgetBand).toBe("5k_15k");
    expect(parsed?.pickHash).toBe("a-b-c");
  });

  it("builds onboarding v2 preference priors", () => {
    const parsed = __deckTestUtils.parseOnboardingV2Profile({
      sceneArchetypes: ["warm_organic"],
      sofaVibes: ["modular_cloud"],
      constraints: { modularOnly: true, smallSpace: true },
    });
    expect(parsed).not.toBeNull();

    const weights = __deckTestUtils.buildOnboardingV2Weights(parsed!);
    expect(weights["feature:modular"]).toBeGreaterThan(2.5);
    expect(weights["feature:small_space"]).toBeGreaterThan(2.5);
    expect(weights["material:wood"]).toBeGreaterThan(0);
  });

  it("computes style distance using jaccard", () => {
    const a = __deckTestUtils.buildStyleTokenSet({
      styleTags: ["scandinavian", "minimal"],
      material: "linen",
      colorFamily: "beige",
      subCategory: "3_seater",
      roomTypes: ["living_room"],
    });
    const b = __deckTestUtils.buildStyleTokenSet({
      styleTags: ["industrial"],
      material: "leather",
      colorFamily: "black",
      subCategory: "corner_sofa",
      roomTypes: ["living_room"],
    });
    const c = __deckTestUtils.buildStyleTokenSet({
      styleTags: ["scandinavian", "minimal"],
      material: "linen",
      colorFamily: "beige",
      subCategory: "3_seater",
      roomTypes: ["living_room"],
    });

    const far = __deckTestUtils.jaccardDistance(a, b);
    const same = __deckTestUtils.jaccardDistance(a, c);

    expect(far).toBeGreaterThan(0.4);
    expect(same).toBe(0);
  });

  it("computes same family duplicate rate in top 8", () => {
    const rate = __deckTestUtils.computeSameFamilyTop8Rate([
      { title: "Cloud Sofa Module Left" },
      { title: "Cloud Sofa Module Right" },
      { title: "Breeze Lounge Chair" },
      { title: "Breeze Lounge Ottoman" },
    ]);
    expect(rate).toBe(0.5);
  });

  it("computes minimum style distance across top 4", () => {
    const min = __deckTestUtils.computeMinStyleDistanceTop4([
      { styleTags: ["scandinavian"], material: "linen", colorFamily: "beige" },
      { styleTags: ["industrial"], material: "leather", colorFamily: "black" },
      { styleTags: ["modern"], material: "velvet", colorFamily: "blue" },
      { styleTags: ["rustic"], material: "wood", colorFamily: "brown" },
    ]);

    expect(min).not.toBeNull();
    expect(min!).toBeGreaterThan(0.4);
  });

  it("extracts campaign id from promoted payload variants", () => {
    expect(__deckTestUtils.extractCampaignIdFromPromotedItem({ campaignId: "camp-1" })).toBe("camp-1");
    expect(__deckTestUtils.extractCampaignIdFromPromotedItem({ campaign: { id: "camp-2" } })).toBe("camp-2");
    expect(
      __deckTestUtils.extractCampaignIdFromPromotedItem({ featured: { campaignId: "camp-3" } })
    ).toBe("camp-3");
  });

  it("keeps legacy promoted items eligible without campaign id", () => {
    const decision = __deckTestUtils.evaluatePromotedItemTargeting(
      "item-1",
      { title: "Legacy promoted sofa" },
      new Map(),
      {
        styleTags: [],
        budgetMin: null,
        budgetMax: null,
        sizeClasses: [],
        geoRegion: "sweden",
        geoCity: null,
        geoPostcode: null,
      }
    );

    expect(decision.eligible).toBe(true);
    expect(decision.reason).toBe("legacy_promoted");
  });

  it("rejects campaign-backed promoted item when segment does not match", () => {
    const contexts = new Map([
      [
        "camp-1",
        {
          campaignId: "camp-1",
          segmentId: "seg-1",
          threshold: 0.5,
          productMode: "all",
          productIds: new Set<string>(),
          segmentCriteria: {
            styleTags: ["scandinavian"],
            budgetMin: null,
            budgetMax: null,
            sizeClasses: [],
            geoRegion: "sweden",
            geoCity: null,
            geoPostcodes: [],
          },
        },
      ],
    ]);

    const decision = __deckTestUtils.evaluatePromotedItemTargeting(
      "item-1",
      { campaignId: "camp-1" },
      contexts as any,
      {
        styleTags: ["industrial"],
        budgetMin: null,
        budgetMax: null,
        sizeClasses: [],
        geoRegion: "sweden",
        geoCity: null,
        geoPostcode: null,
      }
    );

    expect(decision.eligible).toBe(false);
    expect(decision.reason).toBe("segment_mismatch");
    expect(decision.campaignId).toBe("camp-1");
  });

  it("enforces selected product sets before segment matching", () => {
    const contexts = new Map([
      [
        "camp-2",
        {
          campaignId: "camp-2",
          segmentId: "seg-2",
          threshold: 0.5,
          productMode: "selected",
          productIds: new Set<string>(["item-selected"]),
          segmentCriteria: {
            styleTags: ["modern"],
            budgetMin: null,
            budgetMax: null,
            sizeClasses: [],
            geoRegion: "sweden",
            geoCity: null,
            geoPostcodes: [],
          },
        },
      ],
    ]);

    const decision = __deckTestUtils.evaluatePromotedItemTargeting(
      "item-other",
      { campaignId: "camp-2" },
      contexts as any,
      {
        styleTags: ["modern"],
        budgetMin: null,
        budgetMax: null,
        sizeClasses: [],
        geoRegion: "sweden",
        geoCity: null,
        geoPostcode: null,
      }
    );

    expect(decision.eligible).toBe(false);
    expect(decision.reason).toBe("product_set_mismatch");
  });
});
