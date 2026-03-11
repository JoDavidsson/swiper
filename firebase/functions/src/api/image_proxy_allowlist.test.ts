import { __imageProxyTestUtils } from "./image_proxy";

describe("image proxy allowlist", () => {
  const originalAllowedDomains = process.env.IMAGE_PROXY_ALLOWED_DOMAINS;

  afterEach(() => {
    if (originalAllowedDomains == null) {
      delete process.env.IMAGE_PROXY_ALLOWED_DOMAINS;
      return;
    }
    process.env.IMAGE_PROXY_ALLOWED_DOMAINS = originalAllowedDomains;
  });

  it("allows hosts used by Bloomingville and other affected retailers", () => {
    delete process.env.IMAGE_PROXY_ALLOWED_DOMAINS;

    const hosts = [
      "sleepo.cdn-norce.tech",
      "stalands.cdn-norce.tech",
      "cdn3.jysk.com",
      "img2.storyblok.com",
      "pictureserver.net",
      "media.crystallize.com",
      "www.granit.com",
      "media.bloomingville.com",
      "folkhemmet.com",
    ];

    for (const host of hosts) {
      expect(__imageProxyTestUtils.isHostAllowed(host)).toBe(true);
    }
  });

  it("blocks unrelated domains", () => {
    delete process.env.IMAGE_PROXY_ALLOWED_DOMAINS;
    expect(__imageProxyTestUtils.isHostAllowed("malicious.example.com")).toBe(false);
  });

  it("supports environment override for explicit allowlist", () => {
    process.env.IMAGE_PROXY_ALLOWED_DOMAINS = "*.custom-cdn.test";

    expect(__imageProxyTestUtils.isHostAllowed("img.custom-cdn.test")).toBe(true);
    expect(__imageProxyTestUtils.isHostAllowed("cdn3.jysk.com")).toBe(false);
  });
});
