import {
  calculatePacing,
  getHourlyBreakdown,
  PacingStrategy,
  PacingMap,
} from "./pacing";

describe("calculatePacing", () => {
  describe("even distribution", () => {
    it("should distribute budget evenly across all days", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-03"); // 3 days
      const budgetCents = 3000; // 30.00 total

      const result = calculatePacing(budgetCents, startDate, endDate, "even");

      // 3000 / 3 = 1000 per day
      expect(result.get("2026-03-01")).toBe(1000);
      expect(result.get("2026-03-02")).toBe(1000);
      expect(result.get("2026-03-03")).toBe(1000);
    });

    it("should handle remainder by adding to first day", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-02"); // 2 days
      const budgetCents = 3001; // 30.01, should be 1501 + 1500

      const result = calculatePacing(budgetCents, startDate, endDate, "even");

      // Floor(3001 / 2) = 1500, remainder = 1
      // Day 1: 1500 + 1 = 1501 (first day gets the remainder)
      // Day 2: 1500
      expect(result.get("2026-03-01")).toBe(1501);
      expect(result.get("2026-03-02")).toBe(1500);
      expect(Array.from(result.values()).reduce((a, b) => a + b, 0)).toBe(3001);
    });

    it("should return empty map for zero budget", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-03");

      const result = calculatePacing(0, startDate, endDate, "even");

      expect(result.size).toBe(0);
    });

    it("should return empty map when start > end", () => {
      const startDate = new Date("2026-03-05");
      const endDate = new Date("2026-03-01");

      const result = calculatePacing(1000, startDate, endDate, "even");

      expect(result.size).toBe(0);
    });
  });

  describe("frontload distribution", () => {
    it("should allocate more budget to earlier days", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-03"); // 3 days
      const budgetCents = 3000;

      const result = calculatePacing(budgetCents, startDate, endDate, "frontload");

      // Frontload should give more to day 1
      expect(result.get("2026-03-01")).toBeGreaterThan(result.get("2026-03-03")!);
    });

    it("should distribute all budget with frontload", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-05");
      const budgetCents = 10000;

      const result = calculatePacing(budgetCents, startDate, endDate, "frontload");

      const total = Array.from(result.values()).reduce((a, b) => a + b, 0);
      expect(total).toBe(budgetCents);
    });
  });

  describe("backload distribution", () => {
    it("should allocate more budget to later days", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-03"); // 3 days
      const budgetCents = 3000;

      const result = calculatePacing(budgetCents, startDate, endDate, "backload");

      // Backload should give more to day 3
      expect(result.get("2026-03-03")).toBeGreaterThan(result.get("2026-03-01")!);
    });

    it("should distribute all budget with backload", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-05");
      const budgetCents = 10000;

      const result = calculatePacing(budgetCents, startDate, endDate, "backload");

      const total = Array.from(result.values()).reduce((a, b) => a + b, 0);
      expect(total).toBe(budgetCents);
    });
  });

  describe("single day campaign", () => {
    it("should put all budget on single day", () => {
      const startDate = new Date("2026-03-01");
      const endDate = new Date("2026-03-01");
      const budgetCents = 5000;

      const result = calculatePacing(budgetCents, startDate, endDate, "even");

      expect(result.get("2026-03-01")).toBe(5000);
      expect(result.size).toBe(1);
    });
  });
});

describe("getHourlyBreakdown", () => {
  describe("even hourly distribution", () => {
    it("should distribute evenly across 24 hours", () => {
      const result = getHourlyBreakdown(2400, "even"); // 24.00 split across 24 hours = 100/hour

      for (let h = 0; h < 24; h++) {
        expect(result.get(h)).toBe(100);
      }
    });
  });

  describe("frontload hourly distribution (morning peak)", () => {
    it("should allocate more to morning hours (8am-12pm)", () => {
      const result = getHourlyBreakdown(2400, "frontload");

      const morningTotal = (result.get(9) || 0) + (result.get(10) || 0) + (result.get(11) || 0);
      const nightTotal = (result.get(2) || 0) + (result.get(3) || 0);

      expect(morningTotal).toBeGreaterThan(nightTotal);
    });
  });

  describe("backload hourly distribution (evening peak)", () => {
    it("should allocate more to evening hours (6pm-10pm)", () => {
      const result = getHourlyBreakdown(2400, "backload");

      const eveningTotal = (result.get(19) || 0) + (result.get(20) || 0) + (result.get(21) || 0);
      const morningTotal = (result.get(9) || 0) + (result.get(10) || 0);

      expect(eveningTotal).toBeGreaterThan(morningTotal);
    });
  });

  it("should return empty map for zero budget", () => {
    const result = getHourlyBreakdown(0, "even");
    expect(result.size).toBe(0);
  });
});

describe("PacingMap type", () => {
  it("should work as a Map with date strings", () => {
    const pacingMap: PacingMap = new Map();
    pacingMap.set("2026-03-01", 1000);
    pacingMap.set("2026-03-02", 2000);

    expect(pacingMap.get("2026-03-01")).toBe(1000);
    expect(pacingMap.get("2026-03-02")).toBe(2000);
  });
});

describe("PacingStrategy type", () => {
  it("should accept all valid strategy values", () => {
    const strategies: PacingStrategy[] = ["even", "frontload", "backload"];

    for (const strategy of strategies) {
      const result = calculatePacing(
        1000,
        new Date("2026-03-01"),
        new Date("2026-03-01"),
        strategy
      );
      expect(result.size).toBe(1);
    }
  });
});
