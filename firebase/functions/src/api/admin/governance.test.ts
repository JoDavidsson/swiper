import {
  GovernanceConfig,
  adminGovernanceGet,
  adminGovernancePatch,
  adminGovernanceReset,
} from "./governance";

// Mock Firebase Admin
jest.mock("firebase-admin", () => {
  const mockTimestamp = {
    toDate: () => new Date("2026-03-27T12:00:00Z"),
    toMillis: () => new Date("2026-03-27T12:00:00Z").getTime(),
  };
  const mockDoc = {
    exists: true,
    id: "default",
    data: () => ({
      frequencyCap: 12,
      relevanceThreshold: 30,
      pacingStrategy: "even",
      brandSafetyEnabled: true,
      featuredLabelText: "Featured",
      updatedAt: mockTimestamp,
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

// Mock FieldValue
jest.mock("firebase-admin/firestore", () => ({
  FieldValue: {
    serverTimestamp: jest.fn(() => ({ toDate: () => new Date() })),
  },
}));

describe("GovernanceConfig interface", () => {
  it("should have correct shape for default config", () => {
    const config: GovernanceConfig = {
      id: "default",
      frequencyCap: 12,
      relevanceThreshold: 30,
      pacingStrategy: "even",
      brandSafetyEnabled: true,
      featuredLabelText: "Featured",
      updatedAt: null,
      updatedBy: "",
    };

    expect(config.id).toBe("default");
    expect(config.frequencyCap).toBe(12);
    expect(config.relevanceThreshold).toBe(30);
    expect(config.pacingStrategy).toBe("even");
    expect(config.brandSafetyEnabled).toBe(true);
    expect(config.featuredLabelText).toBe("Featured");
  });

  it("should accept all valid pacing strategies", () => {
    const strategies: GovernanceConfig["pacingStrategy"][] = ["even", "frontload", "backload"];

    for (const strategy of strategies) {
      const config: GovernanceConfig = {
        id: "default",
        frequencyCap: 12,
        relevanceThreshold: 30,
        pacingStrategy: strategy,
        brandSafetyEnabled: true,
        featuredLabelText: "Sponsored",
        updatedAt: null,
        updatedBy: "",
      };
      expect(config.pacingStrategy).toBe(strategy);
    }
  });
});

describe("adminGovernanceGet", () => {
  it("should be defined as a function", () => {
    expect(typeof adminGovernanceGet).toBe("function");
  });
});

describe("adminGovernancePatch", () => {
  it("should be defined as a function", () => {
    expect(typeof adminGovernancePatch).toBe("function");
  });
});

describe("adminGovernanceReset", () => {
  it("should be defined as a function", () => {
    expect(typeof adminGovernanceReset).toBe("function");
  });
});
