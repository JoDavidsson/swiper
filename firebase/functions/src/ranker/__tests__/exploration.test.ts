import { applyExploration } from "../exploration";
import type { ItemCandidate } from "../types";

describe("applyExploration", () => {
  const candidates: ItemCandidate[] = [
    { id: "1" },
    { id: "2" },
    { id: "3" },
    { id: "4" },
    { id: "5" },
  ];

  it("with explorationRate 0 returns first limit ids unchanged", () => {
    const rankedIds = ["1", "2", "3", "4", "5"];
    const result = applyExploration(rankedIds, candidates, { explorationRate: 0, limit: 3 });
    expect(result).toEqual(["1", "2", "3"]);
  });

  it("with limit 0 returns empty array", () => {
    const rankedIds = ["1", "2", "3"];
    const result = applyExploration(rankedIds, candidates, { explorationRate: 0.5, limit: 0 });
    expect(result).toEqual([]);
  });

  it("with explorationRate 0 and limit larger than rankedIds returns slice", () => {
    const rankedIds = ["1", "2"];
    const result = applyExploration(rankedIds, candidates, { explorationRate: 0, limit: 10 });
    expect(result).toEqual(["1", "2"]);
  });

  it("with fixed seed and rate > 0 returns reproducible order", () => {
    const rankedIds = ["1", "2", "3", "4", "5"];
    const opts = { explorationRate: 0.5, limit: 3, seed: 42 };
    const a = applyExploration(rankedIds, candidates, opts);
    const b = applyExploration(rankedIds, candidates, opts);
    expect(a).toEqual(b);
  });

  it("with rate = 1 samples within the exploration pool (unique ids)", () => {
    const rankedIds = ["1", "2", "3", "4", "5"];
    const explored = applyExploration(rankedIds, candidates, { explorationRate: 1, limit: 3, seed: 123 });
    expect(explored).toHaveLength(3);
    expect(new Set(explored).size).toBe(3);
    explored.forEach((id) => expect(rankedIds).toContain(id));
  });

  it("with rate > 0 returns exactly limit items when pool has at least 2*limit", () => {
    const rankedIds = ["a", "b", "c", "d", "e", "f"];
    const result = applyExploration(rankedIds, candidates, { explorationRate: 0.1, limit: 3, seed: 1 });
    expect(result).toHaveLength(3);
    expect(result.every((id) => rankedIds.includes(id))).toBe(true);
  });
});
