import { normalizeScore, scoreItem, scoreItemWithSignals, toPriceBucket } from "../scoreItem";
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

  it("scores brand, delivery, and condition signals", () => {
    const item: ItemCandidate = {
      id: "i1",
      brand: "Ikea",
      deliveryComplexity: "low",
      newUsed: "new",
    };
    const weights = {
      "brand:ikea": 1.5,
      "delivery:low": 0.5,
      "condition:new": 0.75,
    };
    expect(scoreItem(item, weights)).toBe(2.75);
  });

  it("scores eco tags and boolean feature signals", () => {
    const item: ItemCandidate = {
      id: "i1",
      ecoTags: ["fsc", "recycled"],
      smallSpaceFriendly: true,
      modular: true,
    };
    const weights = {
      "eco:fsc": 0.6,
      "eco:recycled": 0.4,
      "feature:small_space": 1.2,
      "feature:modular": 0.8,
    };
    expect(scoreItem(item, weights)).toBe(3.0);
  });

  it("scores price bucket signal", () => {
    const item: ItemCandidate = { id: "i1", priceAmount: 13499 };
    const weights = { "price_bucket:mid": 2 };
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

  it("maps price amount to expected price bucket", () => {
    expect(toPriceBucket(2500)).toBe("budget");
    expect(toPriceBucket(6000)).toBe("affordable");
    expect(toPriceBucket(12000)).toBe("mid");
    expect(toPriceBucket(24000)).toBe("premium");
    expect(toPriceBucket(52000)).toBe("luxury");
    expect(toPriceBucket(-1)).toBeNull();
  });
});
