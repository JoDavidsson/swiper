import { __adminImageValidationTestUtils } from "./admin_image_validation";

describe("admin image validation candidate selection", () => {
  it("requires validation when imageValidation is missing", () => {
    expect(__adminImageValidationTestUtils.needsImageValidation({})).toBe(true);
  });

  it("requires validation when validated flag is false", () => {
    expect(
      __adminImageValidationTestUtils.needsImageValidation({
        imageValidation: { validated: false },
      })
    ).toBe(true);
  });

  it("requires validation when analyzed images metadata is missing", () => {
    expect(
      __adminImageValidationTestUtils.needsImageValidation({
        imageValidation: {
          validated: true,
          selectedImageUrl: "https://cdn.example.com/a.jpg",
          selectedSceneType: "contextual",
        },
        creativeHealth: { score: 82 },
      })
    ).toBe(true);
  });

  it("does not require validation when scene metadata is complete", () => {
    expect(
      __adminImageValidationTestUtils.needsImageValidation({
        imageValidation: {
          validated: true,
          analyzedImages: [{ url: "https://cdn.example.com/a.jpg", sceneType: "contextual" }],
          selectedImageUrl: "https://cdn.example.com/a.jpg",
          selectedSceneType: "contextual",
        },
        creativeHealth: { score: 87 },
      })
    ).toBe(false);
  });

  const makeEvaluatedImage = (input: {
    url: string;
    sourceIndex: number;
    sceneType: "contextual" | "studio_cutout" | "unknown";
    valid?: boolean;
    displaySuitabilityScore: number;
    creativeScore?: number;
  }) => ({
    url: input.url,
    sourceIndex: input.sourceIndex,
    creativeScore: input.creativeScore ?? input.displaySuitabilityScore,
    meta: {
      valid: input.valid ?? true,
      url: input.url,
      domain: "cdn.example.com",
      width: 1200,
      height: 900,
      aspectRatio: 1.33,
      aspectCategory: "landscape",
      format: "jpeg",
      size: 120000,
      sceneType: input.sceneType,
      displaySuitabilityScore: input.displaySuitabilityScore,
      sceneMetrics: {
        backgroundRatio: input.sceneType === "studio_cutout" ? 0.84 : 0.44,
        borderBackgroundRatio: input.sceneType === "studio_cutout" ? 0.9 : 0.38,
        nearWhiteRatio: input.sceneType === "studio_cutout" ? 0.74 : 0.1,
        transparentRatio: 0,
        subjectCoverage: 0.52,
        textureScore: input.sceneType === "studio_cutout" ? 0.05 : 0.14,
      },
      issues: input.sceneType === "studio_cutout" ? ["studio-cutout"] : [],
    },
  });

  it("prefers contextual image over studio cutout when both are valid", () => {
    const studio = makeEvaluatedImage({
      url: "https://cdn.example.com/studio.jpg",
      sourceIndex: 0,
      sceneType: "studio_cutout",
      displaySuitabilityScore: 96,
      creativeScore: 96,
    });
    const contextual = makeEvaluatedImage({
      url: "https://cdn.example.com/contextual.jpg",
      sourceIndex: 1,
      sceneType: "contextual",
      displaySuitabilityScore: 74,
      creativeScore: 72,
    });

    const selected = __adminImageValidationTestUtils.selectBestDisplayImage([studio, contextual]);
    expect(selected.url).toBe("https://cdn.example.com/contextual.jpg");
  });

  it("falls back to studio cutout when no valid non-studio image exists", () => {
    const studio = makeEvaluatedImage({
      url: "https://cdn.example.com/studio.jpg",
      sourceIndex: 0,
      sceneType: "studio_cutout",
      displaySuitabilityScore: 64,
    });
    const brokenContextual = makeEvaluatedImage({
      url: "https://cdn.example.com/contextual-broken.jpg",
      sourceIndex: 1,
      sceneType: "contextual",
      valid: false,
      displaySuitabilityScore: 0,
      creativeScore: 0,
    });

    const selected = __adminImageValidationTestUtils.selectBestDisplayImage([studio, brokenContextual]);
    expect(selected.url).toBe("https://cdn.example.com/studio.jpg");
  });
});
