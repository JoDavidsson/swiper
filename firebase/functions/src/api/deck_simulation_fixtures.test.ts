import * as fs from "fs";
import * as path from "path";
import { __deckTestUtils } from "./deck";

function loadRankedItemsFixture(fileName: string): Array<Record<string, unknown>> {
  const filePath = path.resolve(process.cwd(), "scripts/fixtures/deck_simulation", fileName);
  const raw = fs.readFileSync(filePath, "utf8");
  const parsed = JSON.parse(raw) as unknown;
  if (!Array.isArray(parsed)) {
    throw new Error(`Fixture ${fileName} must be an array`);
  }
  return parsed as Array<Record<string, unknown>>;
}

describe("deck simulation fixtures", () => {
  it("duplicate-heavy catalog keeps family repeats bounded in top cards", () => {
    const rankedItems = loadRankedItemsFixture("duplicate_heavy_ranked_items.json");

    const result = __deckTestUtils.applyNearDuplicateExplorationPolicy(
      rankedItems,
      12,
      new Map([["cloud_black_statement", 92]])
    );

    const top8Cloud = result.items
      .slice(0, 8)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family) => family === "ikea::cloud").length;
    const top12Cloud = result.items
      .slice(0, 12)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family) => family === "ikea::cloud").length;

    expect(top8Cloud).toBe(1);
    expect(top12Cloud).toBe(2);
    expect(__deckTestUtils.computeSameFamilyTop8Rate(result.items)).toBeLessThanOrEqual(0.125);
    expect(result.stats.droppedHardNearDuplicate).toBeGreaterThan(0);
  });

  it("single-retailer-heavy catalog still keeps top-8 family diversity", () => {
    const rankedItems = loadRankedItemsFixture("single_retailer_heavy_ranked_items.json");

    const result = __deckTestUtils.applyNearDuplicateExplorationPolicy(rankedItems, 12);
    const top8Families = result.items
      .slice(0, 8)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family): family is string => family != null);

    expect(new Set(top8Families).size).toBe(top8Families.length);
    expect(__deckTestUtils.computeSameFamilyTop8Rate(result.items)).toBe(0);
    expect(result.stats.droppedHardNearDuplicate).toBeGreaterThan(0);
  });

  it("sparse-metadata catalog remains stable and avoids low-quality soft repeats", () => {
    const rankedItems = loadRankedItemsFixture("sparse_metadata_ranked_items.json");

    const result = __deckTestUtils.applyNearDuplicateExplorationPolicy(rankedItems, 12);
    const top12Mono = result.items
      .slice(0, 12)
      .map((item) => __deckTestUtils.itemFamilyKey(item))
      .filter((family) => family === "ikea::mono").length;

    expect(result.items).toHaveLength(rankedItems.length);
    expect(top12Mono).toBe(1);
    expect(result.stats.droppedSoftForQuality).toBeGreaterThan(0);
  });
});
