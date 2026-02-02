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

  it("with fixed seed and rate > 0 replaces a proportion of the top list", () => {
    const rankedIds = [
      "1",
      "2",
      "3",
      "4",
      "5",
      "6",
      "7",
      "8",
      "9",
      "10",
      "11",
      "12",
      "13",
      "14",
      "15",
      "16",
      "17",
      "18",
      "19",
      "20",
    ];
    const explored = applyExploration(rankedIds, candidates, { explorationRate: 0.3, limit: 10, seed: 123 });
    expect(explored).toHaveLength(10);
    const base = rankedIds.slice(0, 10);
    const replacedCount = explored.filter((id) => !base.includes(id)).length;
    expect(replacedCount).toBe(3);
    expect(new Set(explored).size).toBe(10);
  });

  it("with rate 1 replaces all positions from the exploration pool", () => {
    const rankedIds = ["a", "b", "c", "d", "e", "f"];
    const result = applyExploration(rankedIds, candidates, { explorationRate: 1, limit: 3, seed: 1 });
    const base = rankedIds.slice(0, 3);
    const pool = rankedIds.slice(0, 6);
    expect(result).toHaveLength(3);
    expect(result.every((id) => pool.includes(id))).toBe(true);
    expect(result.some((id) => !base.includes(id))).toBe(true);
    expect(new Set(result).size).toBe(3);
  });
});
