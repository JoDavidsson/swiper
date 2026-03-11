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

  it("normalizes color variants into the same title family key", () => {
    const beige = __deckTestUtils.titleFamilyKey("Cloud Sofa Beige 3-seater");
    const blue = __deckTestUtils.titleFamilyKey("Cloud Sofa Blue 3-seater");
    expect(beige).toBe("cloud");
    expect(blue).toBe("cloud");
  });

  it("normalizes sofa-bed diacritics and token order into one family key", () => {
    const first = __deckTestUtils.titleFamilyKey("Lean Bäddsoffa 130 x 200");
    const second = __deckTestUtils.titleFamilyKey("Bäddsoffa Lean");
    const knob = __deckTestUtils.titleFamilyKey("BÄDDSOFFA KNOB");
    expect(first).toBe("lean");
    expect(second).toBe("lean");
    expect(knob).toBe("knob");
  });

  it("builds retailer-agnostic model keys for near-duplicate detection", () => {
    const model = __deckTestUtils.itemModelKey({
      retailer: "ikea",
      title: "Cloud Sofa Beige 3-seater",
    });
    expect(model).toBe("cloud");
  });

  it("derives stable model keys from canonical URL variants", () => {
    const blue = __deckTestUtils.itemModelKey({
      canonicalUrl: "https://shop.example.com/products/cloud-sofa-blue-3-seater/1737345-02",
    });
    const beige = __deckTestUtils.itemModelKey({
      canonicalUrl: "https://shop.example.com/products/cloud-sofa-beige-3-seater/1737345-03",
    });
    expect(blue).toBe("cloud");
    expect(beige).toBe("cloud");
  });

  it("builds retailer-aware family keys for near-duplicate detection", () => {
    const family = __deckTestUtils.itemFamilyKey({
      retailer: "ikea",
      title: "Cloud Sofa Beige 3-seater",
    });
    expect(family).toBe("ikea::cloud");
  });

  it("derives stable source keys from sourceId and URL host", () => {
    expect(
      __deckTestUtils.itemSourceKey({
        sourceId: "ret-1",
        sourceUrl: "https://example.com/a",
      })
    ).toBe("ret-1");

    expect(
      __deckTestUtils.itemSourceKey({
        canonicalUrl: "https://www.ellos.se/product/abc",
      })
    ).toBe("ellos.se");
  });

  it("enforces hard top-8 family dedupe and allows one qualified soft repeat", () => {
    const ranked = [
      {
        id: "cloud-1",
        retailer: "ikea",
        title: "Cloud Sofa Beige 3-seater",
        colorFamily: "beige",
        styleTags: ["minimal"],
        material: "linen",
        seatCountBucket: "3",
        images: ["img1", "img2"],
      },
      {
        id: "cloud-2",
        retailer: "ikea",
        title: "Cloud Sofa Blue 3-seater",
        colorFamily: "blue",
        styleTags: ["minimal"],
        material: "linen",
        seatCountBucket: "3",
        images: ["img1", "img2"],
      },
      { id: "u1", retailer: "a", title: "Aster Sofa", styleTags: ["scandinavian"], images: ["i1", "i2"] },
      { id: "u2", retailer: "b", title: "Harbor Sofa", styleTags: ["modern"], images: ["i1", "i2"] },
      { id: "u3", retailer: "c", title: "Canyon Sofa", styleTags: ["rustic"], images: ["i1", "i2"] },
      { id: "u4", retailer: "d", title: "Lotus Sofa", styleTags: ["bohemian"], images: ["i1", "i2"] },
      { id: "u5", retailer: "e", title: "Atlas Sofa", styleTags: ["industrial"], images: ["i1", "i2"] },
      { id: "u6", retailer: "f", title: "Marina Sofa", styleTags: ["coastal"], images: ["i1", "i2"] },
      { id: "u7", retailer: "g", title: "Ridge Sofa", styleTags: ["modern"], images: ["i1", "i2"] },
      {
        id: "cloud-3",
        retailer: "ikea",
        title: "Cloud Sofa Black XL",
        colorFamily: "black",
        styleTags: ["industrial"],
        material: "leather",
        seatCountBucket: "4_plus",
        sourceUrl: "https://example.com/cloud-black",
        images: ["img1", "img2", "img3"],
      },
      {
        id: "cloud-4",
        retailer: "ikea",
        title: "Cloud Sofa Green XL",
        colorFamily: "green",
        styleTags: ["minimal"],
        material: "linen",
        seatCountBucket: "3",
        sourceUrl: "https://example.com/cloud-green",
        images: ["img1", "img2"],
      },
      { id: "u8", retailer: "h", title: "Nova Sofa", styleTags: ["minimal"], images: ["i1", "i2"] },
      { id: "u9", retailer: "i", title: "Milo Sofa", styleTags: ["modern"], images: ["i1", "i2"] },
      { id: "u10", retailer: "j", title: "Pico Sofa", styleTags: ["minimal"], images: ["i1", "i2"] },
      { id: "u11", retailer: "k", title: "Echo Sofa", styleTags: ["coastal"], images: ["i1", "i2"] },
      { id: "u12", retailer: "l", title: "Willow Sofa", styleTags: ["rustic"], images: ["i1", "i2"] },
    ];

    const result = __deckTestUtils.applyNearDuplicateExplorationPolicy(ranked, 12);
    const top8Families = result.items
      .slice(0, 8)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((value): value is string => value != null);
    const cloudCountTop8 = top8Families.filter((family) => family === "ikea::cloud").length;
    const cloudCountTop12 = result.items
      .slice(0, 12)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family) => family === "ikea::cloud").length;

    expect(cloudCountTop8).toBe(1);
    expect(cloudCountTop12).toBe(2);
    expect(result.stats.droppedHardNearDuplicate).toBeGreaterThan(0);
    expect(result.stats.allowedSoftNearDuplicate).toBe(1);
    expect(result.stats.droppedSoftNearDuplicate).toBeGreaterThan(0);
  });

  it("spreads deferred near-duplicates to avoid family streaks", () => {
    const ranked = [
      { id: "lean-1", retailer: "ikea", title: "Lean Bäddsoffa 130 x 200", colorFamily: "beige", images: ["i1"] },
      { id: "lean-2", retailer: "ikea", title: "Bäddsoffa Lean", colorFamily: "blue", images: ["i1"] },
      { id: "lean-3", retailer: "ikea", title: "Lean Bäddsoffa 130 x 190", colorFamily: "gray", images: ["i1"] },
      { id: "knob-1", retailer: "ikea", title: "BÄDDSOFFA KNOB", colorFamily: "green", images: ["i1"] },
      { id: "knob-2", retailer: "ikea", title: "BÄDDSOFFA KNOB", colorFamily: "beige", images: ["i1"] },
      { id: "knob-3", retailer: "ikea", title: "BÄDDSOFFA KNOB", colorFamily: "brown", images: ["i1"] },
      { id: "flip-1", retailer: "ikea", title: "Flip bäddsoffa", colorFamily: "beige", images: ["i1"] },
      { id: "flip-2", retailer: "ikea", title: "Flip bäddsoffa", colorFamily: "blue", images: ["i1"] },
      { id: "flip-3", retailer: "ikea", title: "Flip bäddsoffa", colorFamily: "green", images: ["i1"] },
    ];

    const result = __deckTestUtils.applyNearDuplicateExplorationPolicy(ranked, 12);
    const topFamilies = result.items.slice(0, 9).map((item) => __deckTestUtils.itemFamilyKey(item));
    let maxRun = 0;
    let run = 0;
    let prev: string | null = null;
    for (const family of topFamilies) {
      const key = family ?? "unknown";
      if (key === prev) {
        run += 1;
      } else {
        run = 1;
        prev = key;
      }
      if (run > maxRun) maxRun = run;
    }

    expect(maxRun).toBeLessThanOrEqual(1);
  });

  it("caps single-source dominance in early deck positions", () => {
    const ranked = [
      { id: "a-1", sourceId: "ikea", title: "A1 Sofa" },
      { id: "a-2", sourceId: "ikea", title: "A2 Sofa" },
      { id: "a-3", sourceId: "ikea", title: "A3 Sofa" },
      { id: "a-4", sourceId: "ikea", title: "A4 Sofa" },
      { id: "a-5", sourceId: "ikea", title: "A5 Sofa" },
      { id: "a-6", sourceId: "ikea", title: "A6 Sofa" },
      { id: "a-7", sourceId: "ikea", title: "A7 Sofa" },
      { id: "a-8", sourceId: "ikea", title: "A8 Sofa" },
      { id: "a-9", sourceId: "ikea", title: "A9 Sofa" },
      { id: "a-10", sourceId: "ikea", title: "A10 Sofa" },
      { id: "b-1", sourceId: "homeroom", title: "B1 Sofa" },
      { id: "c-1", sourceId: "ellos", title: "C1 Sofa" },
      { id: "d-1", sourceId: "source-d", title: "D1 Sofa" },
      { id: "e-1", sourceId: "source-e", title: "E1 Sofa" },
      { id: "f-1", sourceId: "source-f", title: "F1 Sofa" },
      { id: "g-1", sourceId: "source-g", title: "G1 Sofa" },
    ];

    const result = __deckTestUtils.applySourceDiversityPolicy(ranked, 12);
    const ikeaTop12 = result.items
      .slice(0, 12)
      .map((item) => __deckTestUtils.itemSourceKey(item))
      .filter((key) => key === "ikea").length;

    expect(ikeaTop12).toBeLessThanOrEqual(6);
    expect(result.stats.deferredForSourceCap).toBeGreaterThan(0);
  });

  it("caps repeated model names in early deck positions", () => {
    const ranked = [
      { id: "m-1", retailer: "mio", title: "Madison" },
      { id: "m-2", retailer: "mio", title: "Madison" },
      { id: "m-3", retailer: "mio", title: "Madison" },
      { id: "e-1", retailer: "mio", title: "Eden" },
      { id: "e-2", retailer: "mio", title: "Eden" },
      { id: "w-1", retailer: "mio", title: "Willow" },
      { id: "a-1", retailer: "ellos", title: "Alpha" },
      { id: "b-1", retailer: "homeroom", title: "Beta" },
      { id: "c-1", retailer: "chilli", title: "Gamma" },
      { id: "d-1", retailer: "ikea", title: "Delta" },
      { id: "o-1", retailer: "soffadirekt", title: "Omega" },
    ];

    const result = __deckTestUtils.applyTopModelDedupePolicy(ranked, 12);
    const top8Models = result.items
      .slice(0, 8)
      .map((item) => __deckTestUtils.itemModelKey(item))
      .filter((value): value is string => value != null);

    expect(top8Models.filter((model) => model === "madison")).toHaveLength(1);
    expect(top8Models.filter((model) => model === "eden")).toHaveLength(1);
    expect(result.stats.deferredForModelCap).toBeGreaterThan(0);
  });

  it("computes top-8 source concentration and diversity", () => {
    const concentration = __deckTestUtils.computeSourceConcentrationTop8([
      { sourceId: "ikea" },
      { sourceId: "ikea" },
      { sourceId: "ikea" },
      { sourceId: "homeroom" },
      { sourceId: "homeroom" },
      { sourceId: "ellos" },
      { sourceId: "ellos" },
      { sourceId: "source-x" },
    ]);
    const diversity = __deckTestUtils.computeSourceDiversityTop8([
      { sourceId: "ikea" },
      { sourceId: "ikea" },
      { sourceId: "ikea" },
      { sourceId: "homeroom" },
      { sourceId: "homeroom" },
      { sourceId: "ellos" },
      { sourceId: "ellos" },
      { sourceId: "source-x" },
    ]);

    expect(concentration).toBe(0.375);
    expect(diversity).toBe(4);
  });

  it("rejects items with no displayable image URLs", () => {
    expect(__deckTestUtils.passesImageDisplayGate({ id: "no-image", images: [] })).toBe(false);
    expect(
      __deckTestUtils.passesImageDisplayGate({
        id: "empty-url",
        images: [{ url: "   " }],
      })
    ).toBe(false);
  });

  it("rejects items marked with critical image validation issues", () => {
    expect(
      __deckTestUtils.passesImageDisplayGate({
        id: "broken-item",
        images: [{ url: "https://cdn.example.com/a.jpg" }],
        imageValidation: {
          validated: true,
          validImageCount: 0,
          issues: ["validation-error"],
        },
      })
    ).toBe(false);
  });

  it("keeps studio cutout items if they are still valid images", () => {
    expect(
      __deckTestUtils.passesImageDisplayGate({
        id: "cutout-ok",
        images: [{ url: "https://cdn.example.com/cutout.png" }],
        imageValidation: {
          validated: true,
          validImageCount: 1,
          issues: ["studio-cutout"],
        },
      })
    ).toBe(true);
  });

  it("blocks soft-window repeats that fail quality gates", () => {
    const ranked = [
      {
        id: "cloud-1",
        retailer: "ikea",
        title: "Cloud Sofa Beige 3-seater",
        colorFamily: "beige",
        styleTags: ["minimal"],
        images: ["img1", "img2"],
      },
      { id: "u1", retailer: "a", title: "Aster Sofa", styleTags: ["scandinavian"], images: ["i1", "i2"] },
      { id: "u2", retailer: "b", title: "Harbor Sofa", styleTags: ["modern"], images: ["i1", "i2"] },
      { id: "u3", retailer: "c", title: "Canyon Sofa", styleTags: ["rustic"], images: ["i1", "i2"] },
      { id: "u4", retailer: "d", title: "Lotus Sofa", styleTags: ["bohemian"], images: ["i1", "i2"] },
      { id: "u5", retailer: "e", title: "Atlas Sofa", styleTags: ["industrial"], images: ["i1", "i2"] },
      { id: "u6", retailer: "f", title: "Marina Sofa", styleTags: ["coastal"], images: ["i1", "i2"] },
      { id: "u7", retailer: "g", title: "Ridge Sofa", styleTags: ["modern"], images: ["i1", "i2"] },
      {
        id: "cloud-2",
        retailer: "ikea",
        title: "Cloud Sofa Blue 3-seater",
        colorFamily: "blue",
        styleTags: ["industrial"],
        images: ["img1"],
      },
      { id: "u8", retailer: "h", title: "Nova Sofa", styleTags: ["minimal"], images: ["i1", "i2"] },
    ];

    const result = __deckTestUtils.applyNearDuplicateExplorationPolicy(ranked, 12);
    const cloudCountTop9 = result.items
      .slice(0, 9)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family) => family === "ikea::cloud").length;

    expect(cloudCountTop9).toBe(1);
    expect(result.stats.droppedSoftForQuality).toBeGreaterThan(0);
  });

  it("uses objective quality score map when evaluating soft repeat quality", () => {
    expect(
      __deckTestUtils.passesSoftRepeatQualityGate(
        { id: "item-high", images: ["img1"] },
        new Map([["item-high", 90]])
      )
    ).toBe(true);
    expect(
      __deckTestUtils.passesSoftRepeatQualityGate(
        { id: "item-low", images: ["img1", "img2"], sourceUrl: "https://x.test/item-low" },
        new Map([["item-low", 40]])
      )
    ).toBe(false);
  });

  it("allows qualified soft repeats via score-map even when proxy quality is low", () => {
    const ranked = [
      {
        id: "cloud-1",
        retailer: "ikea",
        title: "Cloud Sofa Beige 3-seater",
        colorFamily: "beige",
        styleTags: ["minimal"],
        images: ["img1", "img2"],
      },
      { id: "u1", retailer: "a", title: "Aster Sofa", styleTags: ["scandinavian"], images: ["i1", "i2"] },
      { id: "u2", retailer: "b", title: "Harbor Sofa", styleTags: ["modern"], images: ["i1", "i2"] },
      { id: "u3", retailer: "c", title: "Canyon Sofa", styleTags: ["rustic"], images: ["i1", "i2"] },
      { id: "u4", retailer: "d", title: "Lotus Sofa", styleTags: ["bohemian"], images: ["i1", "i2"] },
      { id: "u5", retailer: "e", title: "Atlas Sofa", styleTags: ["industrial"], images: ["i1", "i2"] },
      { id: "u6", retailer: "f", title: "Marina Sofa", styleTags: ["coastal"], images: ["i1", "i2"] },
      { id: "u7", retailer: "g", title: "Ridge Sofa", styleTags: ["modern"], images: ["i1", "i2"] },
      {
        id: "cloud-2",
        retailer: "ikea",
        title: "Cloud Sofa Blue 3-seater",
        colorFamily: "blue",
        styleTags: ["industrial"],
        images: ["img1"],
      },
      { id: "u8", retailer: "h", title: "Nova Sofa", styleTags: ["minimal"], images: ["i1", "i2"] },
    ];

    const withoutMap = __deckTestUtils.applyNearDuplicateExplorationPolicy(ranked, 12);
    const withMap = __deckTestUtils.applyNearDuplicateExplorationPolicy(
      ranked,
      12,
      new Map([["cloud-2", 92]])
    );

    const cloudCountTop9WithoutMap = withoutMap.items
      .slice(0, 9)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family) => family === "ikea::cloud").length;
    const cloudCountTop9WithMap = withMap.items
      .slice(0, 9)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family) => family === "ikea::cloud").length;

    expect(cloudCountTop9WithoutMap).toBe(1);
    expect(cloudCountTop9WithMap).toBe(2);
    expect(withMap.stats.allowedSoftNearDuplicate).toBe(1);
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

  it("enforces auto product sets using recommendedProductIds", () => {
    const contexts = new Map([
      [
        "camp-auto",
        {
          campaignId: "camp-auto",
          retailerId: "ret-1",
          segmentId: "seg-auto",
          threshold: 0.2,
          frequencyCap: 12,
          productMode: "auto",
          productIds: new Set<string>(),
          recommendedProductIds: new Set<string>(["item-auto-1"]),
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

    const allowed = __deckTestUtils.evaluatePromotedItemTargeting(
      "item-auto-1",
      { campaignId: "camp-auto" },
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
    expect(allowed.eligible).toBe(true);

    const blocked = __deckTestUtils.evaluatePromotedItemTargeting(
      "item-other",
      { campaignId: "camp-auto" },
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
    expect(blocked.eligible).toBe(false);
    expect(blocked.reason).toBe("product_set_mismatch");
  });

  it("keeps featured cards on strict frequency slots only", () => {
    const ranked = [
      { id: "o1", isFeatured: false },
      { id: "f1", isFeatured: true, featuredRetailerId: "ret-1" },
      { id: "o2", isFeatured: false },
      { id: "o3", isFeatured: false },
      { id: "o4", isFeatured: false },
      { id: "f2", isFeatured: true, featuredRetailerId: "ret-2" },
      { id: "o5", isFeatured: false },
      { id: "o6", isFeatured: false },
    ];

    const result = __deckTestUtils.applyFeaturedServingPolicy(ranked, 8, 4, 1);
    const featuredPositions = result.items
      .map((item, index) => ({ featured: item.isFeatured === true, index: index + 1 }))
      .filter((entry) => entry.featured)
      .map((entry) => entry.index);

    expect(featuredPositions).toEqual([4, 8]);
    expect(result.stats.featuredServed).toBe(2);
    expect(result.stats.maxFeaturedSlots).toBe(2);
    expect(result.stats.overflowFeaturedUsed).toBe(0);
  });

  it("falls back to organic when diversity cooldown blocks featured", () => {
    const ranked = [
      { id: "o1", isFeatured: false },
      { id: "o2", isFeatured: false },
      { id: "f1", isFeatured: true, featuredRetailerId: "ret-repeat" },
      { id: "o3", isFeatured: false },
      { id: "o4", isFeatured: false },
      { id: "o5", isFeatured: false },
      { id: "f2", isFeatured: true, featuredRetailerId: "ret-repeat" },
    ];

    const result = __deckTestUtils.applyFeaturedServingPolicy(ranked, 6, 3, 1);

    expect(result.items).toHaveLength(6);
    expect(result.items[2].isFeatured).toBe(true);
    expect(result.items[5].isFeatured).toBe(false);
    expect(result.stats.featuredServed).toBe(1);
    expect(result.stats.fallbackToOrganicCount).toBe(1);
    expect(result.stats.droppedForDiversity).toBeGreaterThan(0);
  });
});
