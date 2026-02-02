import { normalizeScore, scoreItem, scoreItemWithSignals } from "../scoreItem";
import type { ItemCandidate } from "../types";

describe("scoreItem", () => {
  it("returns 0 when weights are empty", () => {
    const item: ItemCandidate = {
      id: "i1",
      styleTags: ["modern", "scandinavian"],
      material: "fabric",
      colorFamily: "gray",
      sizeClass: "medium",
    };
    expect(scoreItem(item, {})).toBe(0);
  });

  it("scores styleTags from weights", () => {
    const item: ItemCandidate = { id: "i1", styleTags: ["modern", "scandinavian"] };
    const weights = { modern: 2, scandinavian: 3 };
    expect(scoreItem(item, weights)).toBe(5);
  });

  it("scores material as material:X", () => {
    const item: ItemCandidate = { id: "i1", material: "leather" };
    const weights = { "material:leather": 4 };
    expect(scoreItem(item, weights)).toBe(4);
  });

  it("scores colorFamily as color:X", () => {
    const item: ItemCandidate = { id: "i1", colorFamily: "gray" };
    const weights = { "color:gray": 1 };
    expect(scoreItem(item, weights)).toBe(1);
  });

  it("scores sizeClass as size:X", () => {
    const item: ItemCandidate = { id: "i1", sizeClass: "large" };
    const weights = { "size:large": 2 };
    expect(scoreItem(item, weights)).toBe(2);
  });

  it("sums all contributions", () => {
    const item: ItemCandidate = {
      id: "i1",
      styleTags: ["modern"],
      material: "fabric",
      colorFamily: "beige",
      sizeClass: "medium",
    };
    const weights = {
      modern: 1,
      "material:fabric": 2,
      "color:beige": 1,
      "size:medium": 1,
    };
    expect(scoreItem(item, weights)).toBe(5);
  });

  it("ignores missing or zero weights", () => {
    const item: ItemCandidate = { id: "i1", styleTags: ["unknown"], material: "wood" };
    const weights = { modern: 10 };
    expect(scoreItem(item, weights)).toBe(0);
  });

  it("handles empty styleTags", () => {
    const item: ItemCandidate = { id: "i1", styleTags: [] };
    expect(scoreItem(item, { modern: 1 })).toBe(0);
  });

  it("handles undefined styleTags", () => {
    const item: ItemCandidate = { id: "i1" };
    expect(scoreItem(item, {})).toBe(0);
  });

  it("returns signal count for matched weights", () => {
    const item: ItemCandidate = {
      id: "i1",
      styleTags: ["modern", "scandinavian"],
      material: "fabric",
      colorFamily: "gray",
      sizeClass: "medium",
    };
    const weights = {
      modern: 1,
      scandinavian: 0,
      "material:fabric": 2,
      "color:gray": 0.5,
      "size:medium": 0,
    };
    const result = scoreItemWithSignals(item, weights);
    expect(result.score).toBe(3.5);
    expect(result.signalCount).toBe(3);
  });

  it("normalizes score by sqrt of signal count", () => {
    const normalized = normalizeScore(9, 4);
    expect(normalized).toBe(4.5);
  });
});
