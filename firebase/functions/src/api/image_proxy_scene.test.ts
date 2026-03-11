import { __imageProxyTestUtils } from "./image_proxy";

describe("image proxy scene heuristics", () => {
  it("classifies contextual scenes from balanced metrics", () => {
    const result = __imageProxyTestUtils.classifySceneFromMetrics({
      backgroundRatio: 0.44,
      borderBackgroundRatio: 0.38,
      nearWhiteRatio: 0.1,
      transparentRatio: 0,
      subjectCoverage: 0.52,
      textureScore: 0.14,
    });

    expect(result.sceneType).toBe("contextual");
    expect(result.sceneIssues).toEqual([]);
  });

  it("classifies transparent/white cutouts as studio_cutout", () => {
    const result = __imageProxyTestUtils.classifySceneFromMetrics({
      backgroundRatio: 0.84,
      borderBackgroundRatio: 0.92,
      nearWhiteRatio: 0.77,
      transparentRatio: 0.14,
      subjectCoverage: 0.41,
      textureScore: 0.05,
    });

    expect(result.sceneType).toBe("studio_cutout");
    expect(result.sceneIssues).toContain("studio-cutout");
    expect(result.sceneIssues).toContain("transparent-background");
    expect(result.sceneIssues).toContain("white-background");
  });

  it("scores contextual scenes higher than studio cutouts", () => {
    const contextualScore = __imageProxyTestUtils.scoreDisplaySuitability({
      width: 1400,
      height: 1000,
      valid: true,
      sceneType: "contextual",
      metrics: {
        backgroundRatio: 0.45,
        borderBackgroundRatio: 0.4,
        nearWhiteRatio: 0.08,
        transparentRatio: 0,
        subjectCoverage: 0.58,
        textureScore: 0.13,
      },
    });
    const cutoutScore = __imageProxyTestUtils.scoreDisplaySuitability({
      width: 1400,
      height: 1000,
      valid: true,
      sceneType: "studio_cutout",
      metrics: {
        backgroundRatio: 0.82,
        borderBackgroundRatio: 0.9,
        nearWhiteRatio: 0.72,
        transparentRatio: 0.16,
        subjectCoverage: 0.44,
        textureScore: 0.05,
      },
    });

    expect(contextualScore).toBeGreaterThan(cutoutScore);
    expect(cutoutScore).toBeLessThan(60);
  });

  it("returns 0 suitability for invalid images", () => {
    const score = __imageProxyTestUtils.scoreDisplaySuitability({
      width: 0,
      height: 0,
      valid: false,
      sceneType: "unknown",
      metrics: {
        backgroundRatio: 0,
        borderBackgroundRatio: 0,
        nearWhiteRatio: 0,
        transparentRatio: 0,
        subjectCoverage: 0,
        textureScore: 0,
      },
    });

    expect(score).toBe(0);
  });
});
