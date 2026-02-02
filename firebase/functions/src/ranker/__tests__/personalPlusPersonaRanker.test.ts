import { createPersonalPlusPersonaRanker } from "../personalPlusPersonaRanker";
import type { ItemCandidate, PersonaSignals, SessionContext } from "../types";

describe("PersonalPlusPersonaRanker", () => {
  const session: SessionContext = {
    preferenceWeights: { modern: 2, "material:fabric": 1 },
  };

  const candidates: ItemCandidate[] = [
    { id: "high_personal", styleTags: ["modern"], material: "fabric", colorFamily: "gray", sizeClass: "medium" },
    { id: "high_persona", styleTags: [], material: "wood", colorFamily: "brown", sizeClass: "small" },
    { id: "both_low", styleTags: [], material: "metal", colorFamily: "black", sizeClass: "large" },
  ];

  it("without personaSignals behaves like personal-only (highest personal first)", () => {
    const ranker = createPersonalPlusPersonaRanker(0.7);
    const result = ranker.rank(session, candidates, { limit: 3 });
    expect(result.itemIds[0]).toBe("high_personal");
    expect(result.algorithmVersion).toBe("personal_plus_persona_v1");
  });

  it("with personaSignals and high alpha favors personal score", () => {
    const personaSignals: PersonaSignals = {
      itemScoresFromSimilarSessions: { high_personal: 10, high_persona: 1, both_low: 0 },
    };
    const ranker = createPersonalPlusPersonaRanker(0.9);
    const result = ranker.rank(session, candidates, { limit: 3 }, personaSignals);
    expect(result.itemIds[0]).toBe("high_personal");
  });

  it("with personaSignals and low alpha favors persona score", () => {
    const personaSignals: PersonaSignals = {
      itemScoresFromSimilarSessions: { high_persona: 100, high_personal: 1, both_low: 0 },
    };
    const ranker = createPersonalPlusPersonaRanker(0.2);
    const result = ranker.rank(session, candidates, { limit: 3 }, personaSignals);
    expect(result.itemIds[0]).toBe("high_persona");
  });

  it("popularAmongSimilar influences order when itemScoresFromSimilarSessions missing", () => {
    const personaSignals: PersonaSignals = {
      popularAmongSimilar: ["both_low", "high_persona", "high_personal"],
    };
    const ranker = createPersonalPlusPersonaRanker(0.3);
    const result = ranker.rank(session, candidates, { limit: 3 }, personaSignals);
    expect(result.itemIds).toContain("both_low");
    expect(result.itemIds).toContain("high_persona");
    expect(result.itemIds).toContain("high_personal");
  });

  it("empty personaSignals falls back to personal-only", () => {
    const ranker = createPersonalPlusPersonaRanker(0.5);
    const result = ranker.rank(session, candidates, { limit: 3 }, {});
    expect(result.itemIds[0]).toBe("high_personal");
  });

  it("undefined personaSignals falls back to personal-only", () => {
    const ranker = createPersonalPlusPersonaRanker(0.5);
    const result = ranker.rank(session, candidates, { limit: 3 });
    expect(result.itemIds[0]).toBe("high_personal");
  });

  it("returns runId and itemScores for all returned itemIds", () => {
    const personaSignals: PersonaSignals = {
      itemScoresFromSimilarSessions: { high_persona: 10 },
    };
    const ranker = createPersonalPlusPersonaRanker(0.5);
    const result = ranker.rank(session, candidates, { limit: 2 }, personaSignals);
    expect(result.runId).toBeDefined();
    expect(result.itemIds).toHaveLength(2);
    for (const id of result.itemIds) {
      expect(result.itemScores[id]).toBeDefined();
    }
  });

  it("treats zeroed personal weights as no personal signal", () => {
    const personaSignals: PersonaSignals = {
      itemScoresFromSimilarSessions: { high_persona: 10, high_personal: 1 },
    };
    const ranker = createPersonalPlusPersonaRanker(0.7);
    const result = ranker.rank({ preferenceWeights: { modern: 0, "material:fabric": 0 } }, candidates, { limit: 3 }, personaSignals);
    expect(result.itemIds[0]).toBe("high_persona");
  });

  it("uses persona scores when session has no personal weights", () => {
    const personaSignals: PersonaSignals = {
      itemScoresFromSimilarSessions: { high_persona: 10, high_personal: 1 },
    };
    const ranker = createPersonalPlusPersonaRanker(0.7);
    const result = ranker.rank({ preferenceWeights: {} }, candidates, { limit: 3 }, personaSignals);
    expect(result.itemIds[0]).toBe("high_persona");
  });
});
