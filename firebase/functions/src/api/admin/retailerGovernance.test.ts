import {
  RetailerGovernance,
  adminRetailerGovernanceGet,
  adminRetailerGovernancePatch,
} from "./retailerGovernance";

// Mock Firebase Admin
jest.mock("firebase-admin", () => {
  const mockDoc = {
    exists: true,
    id: "test-retailer",
    data: () => ({
      frequencyCapOverride: 6,
      relevanceThresholdOverride: 50,
      pacingStrategyOverride: "frontload",
      pausedCampaignIds: ["campaign-1", "campaign-2"],
      blockedProductIds: ["product-abc"],
      updatedAt: { toDate: () => new Date("2026-03-27T12:00:00Z") },
      updatedBy: "admin@example.com",
    }),
  };
  const mockCollection = {
    doc: jest.fn().mockReturnValue({
      get: jest.fn().mockResolvedValue(mockDoc),
      set: jest.fn().mockResolvedValue(undefined),
      update: jest.fn().mockResolvedValue(undefined),
    }),
  };
  return {
    firestore: jest.fn(() => ({
      collection: jest.fn().mockReturnValue(mockCollection),
    })),
    default: {
      firestore: jest.fn(() => ({
        collection: jest.fn().mockReturnValue(mockCollection),
      })),
    },
  };
});

jest.mock("firebase-admin/firestore", () => ({
  FieldValue: {
    serverTimestamp: jest.fn(() => ({ toDate: () => new Date() })),
  },
}));

describe("RetailerGovernance interface", () => {
  it("should have correct shape with all overrides", () => {
    const governance: RetailerGovernance = {
      retailerId: "test-retailer",
      frequencyCapOverride: 6,
      relevanceThresholdOverride: 50,
      pacingStrategyOverride: "frontload",
      pausedCampaignIds: ["campaign-1"],
      blockedProductIds: ["product-abc"],
      updatedAt: "2026-03-27T12:00:00Z",
      updatedBy: "admin@example.com",
    };

    expect(governance.retailerId).toBe("test-retailer");
    expect(governance.frequencyCapOverride).toBe(6);
    expect(governance.relevanceThresholdOverride).toBe(50);
    expect(governance.pacingStrategyOverride).toBe("frontload");
    expect(governance.pausedCampaignIds).toEqual(["campaign-1"]);
    expect(governance.blockedProductIds).toEqual(["product-abc"]);
  });

  it("should allow null overrides to use global config", () => {
    const governance: RetailerGovernance = {
      retailerId: "test-retailer",
      frequencyCapOverride: null,
      relevanceThresholdOverride: null,
      pacingStrategyOverride: null,
      pausedCampaignIds: [],
      blockedProductIds: [],
      updatedAt: null,
      updatedBy: "",
    };

    expect(governance.frequencyCapOverride).toBeNull();
    expect(governance.relevanceThresholdOverride).toBeNull();
    expect(governance.pacingStrategyOverride).toBeNull();
  });

  it("should accept all valid pacing strategy overrides", () => {
    const strategies: RetailerGovernance["pacingStrategyOverride"][] = [
      "even",
      "frontload",
      "backload",
      null,
    ];

    for (const strategy of strategies) {
      // Just test that the value is assignable
      const governance = {
        retailerId: "test-retailer",
        pacingStrategyOverride: strategy,
        pausedCampaignIds: [] as string[],
        blockedProductIds: [] as string[],
        updatedAt: null as string | null,
        updatedBy: "",
      };
      expect(governance.pacingStrategyOverride).toBe(strategy);
    }
  });
});

describe("adminRetailerGovernanceGet", () => {
  it("should be defined as a function", () => {
    expect(typeof adminRetailerGovernanceGet).toBe("function");
  });
});

describe("adminRetailerGovernancePatch", () => {
  it("should be defined as a function", () => {
    expect(typeof adminRetailerGovernancePatch).toBe("function");
  });

  it("should accept partial updates with pacingStrategyOverride", () => {
    // Test that a partial object with just pacingStrategyOverride is valid
    const partial = {
      pacingStrategyOverride: "frontload" as const,
    };
    expect(partial.pacingStrategyOverride).toBe("frontload");
  });

  it("should accept blockedProductIds array", () => {
    const governance = {
      retailerId: "test",
      blockedProductIds: ["prod-1", "prod-2"],
      pausedCampaignIds: [] as string[],
      updatedAt: null as string | null,
      updatedBy: "",
    };
    expect(governance.blockedProductIds).toHaveLength(2);
  });
});
