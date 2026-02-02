import { PreferenceWeightsRanker } from "../preferenceWeightsRanker";
import type { ItemCandidate, SessionContext } from "../types";

describe("PreferenceWeightsRanker", () => {
  const session: SessionContext = {
    preferenceWeights: { modern: 2, scandinavian: 1, "material:fabric": 1, "color:gray": 1, "size:medium": 1, "size:large": 1 },
  };

  const candidates: ItemCandidate[] = [
    { id: "a", styleTags: ["modern"], material: "fabric", colorFamily: "gray", sizeClass: "medium" },
    { id: "b", styleTags: ["scandinavian"], material: "leather", colorFamily: "beige", sizeClass: "small" },
    { id: "c", styleTags: ["modern", "scandinavian"], material: "fabric", colorFamily: "gray", sizeClass: "large" },
    { id: "d", styleTags: [], material: "wood", colorFamily: "brown", sizeClass: "medium" },
  ];

  it("returns runId and algorithmVersion", () => {
    const result = PreferenceWeightsRanker.rank(session, candidates, { limit: 2 });
    expect(result.runId).toBeDefined();
    expect(result.runId.length).toBeGreaterThanOrEqual(8);
    expect(result.algorithmVersion).toBe("preference_weights_v1");
  });

  it("respects limit", () => {
    const result = PreferenceWeightsRanker.rank(session, candidates, { limit: 2 });
    expect(result.itemIds).toHaveLength(2);
    expect(Object.keys(result.itemScores)).toHaveLength(2);
  });

  it("orders by score descending (c highest: modern+scandinavian+fabric+gray)", () => {
    const result = PreferenceWeightsRanker.rank(session, candidates, { limit: 4 });
    expect(result.itemIds[0]).toBe("c");
    expect(result.itemIds[1]).toBe("a");
    expect(result.itemScores["c"]).toBeGreaterThan(result.itemScores["a"]);
  });

  it("itemScores match returned itemIds", () => {
    const result = PreferenceWeightsRanker.rank(session, candidates, { limit: 3 });
    for (const id of result.itemIds) {
      expect(result.itemScores[id]).toBeDefined();
      expect(typeof result.itemScores[id]).toBe("number");
    }
  });

  it("empty candidates returns empty itemIds and itemScores", () => {
    const result = PreferenceWeightsRanker.rank(session, [], { limit: 10 });
    expect(result.itemIds).toEqual([]);
    expect(result.itemScores).toEqual({});
  });

  it("single candidate returns one item", () => {
    const result = PreferenceWeightsRanker.rank(session, [candidates[0]], { limit: 5 });
    expect(result.itemIds).toEqual(["a"]);
    expect(result.itemScores["a"]).toBeCloseTo(2.5, 5);
  });

  it("ties broken deterministically by id", () => {
    const tied: ItemCandidate[] = [
      { id: "x", styleTags: [], material: "wood", colorFamily: "brown", sizeClass: "small" },
      { id: "y", styleTags: [], material: "wood", colorFamily: "brown", sizeClass: "small" },
    ];
    const result = PreferenceWeightsRanker.rank(session, tied, { limit: 2 });
    expect(result.itemIds).toHaveLength(2);
    expect(result.itemIds.sort()).toEqual(["x", "y"]);
  });

  it("uses custom algorithmVersion when provided", () => {
    const result = PreferenceWeightsRanker.rank(session, candidates, {
      limit: 1,
      algorithmVersion: "custom_v1",
    });
    expect(result.algorithmVersion).toBe("custom_v1");
  });
});
