import { applyMMRReRank } from "../mmrReranker";
import type { ItemCandidate } from "../types";

describe("applyMMRReRank", () => {
  const candidates: ItemCandidate[] = [
    {
      id: "a1",
      styleTags: ["modern"],
      material: "linen",
      colorFamily: "beige",
      primaryCategory: "sofa",
      subCategory: "3_seater",
    },
    {
      id: "a2",
      styleTags: ["modern"],
      material: "linen",
      colorFamily: "gray",
      primaryCategory: "sofa",
      subCategory: "3_seater",
    },
    {
      id: "b1",
      styleTags: ["vintage"],
      material: "leather",
      colorFamily: "brown",
      primaryCategory: "sofa",
      subCategory: "chesterfield",
    },
    {
      id: "c1",
      styleTags: ["scandinavian"],
      material: "wood",
      colorFamily: "white",
      primaryCategory: "sofa",
      subCategory: "2_seater",
    },
    {
      id: "tail_1",
      styleTags: ["minimal"],
      material: "fabric",
    },
  ];

  const rankedIds = ["a1", "a2", "b1", "c1", "tail_1"];
  const itemScores = {
    a1: 1.0,
    a2: 0.95,
    b1: 0.9,
    c1: 0.85,
    tail_1: 0.2,
  };

  it("keeps original order when lambda=1", () => {
    const result = applyMMRReRank(rankedIds, candidates, itemScores, { lambda: 1, topN: 4 });
    expect(result).toEqual(rankedIds);
  });

  it("promotes diversity when lambda is lower", () => {
    const result = applyMMRReRank(rankedIds, candidates, itemScores, { lambda: 0.55, topN: 4 });
    expect(result[0]).toBe("a1");
    expect(result.indexOf("b1")).toBeLessThan(result.indexOf("a2"));
  });

  it("reranks only topN and preserves tail order", () => {
    const result = applyMMRReRank(rankedIds, candidates, itemScores, { lambda: 0.5, topN: 3 });
    expect(result.slice(3)).toEqual(["c1", "tail_1"]);
  });

  it("returns unique IDs and original length", () => {
    const result = applyMMRReRank(rankedIds, candidates, itemScores, { lambda: 0.5, topN: 5 });
    expect(result).toHaveLength(rankedIds.length);
    expect(new Set(result).size).toBe(rankedIds.length);
  });
});
