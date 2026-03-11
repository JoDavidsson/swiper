import { Request, Response } from "express";
import sharp from "sharp";

const ALLOWED_WIDTHS = [400, 800, 1200];
const DEFAULT_TIMEOUT_MS = 8000;
const DEFAULT_PROXY_MAX_BYTES = 12 * 1024 * 1024; // 12MB
const DEFAULT_META_MAX_BYTES = 5 * 1024 * 1024; // 5MB full image for quality analysis
const MIN_RESOLUTION = 400;
const MAX_IMAGE_PIXELS = 40_000_000;
const SCENE_SAMPLE_SIZE = 192;
const BORDER_RATIO = 0.12;
const DEFAULT_ALLOWED_DOMAINS = [
  // --- CDN / media domains ---
  "images.unsplash.com",
  "*.shopify.com",               // cdn.shopify.com and other Shopify subdomains
  "cdn.bolia.com",
  "images.prismic.io",           // Prismic CMS (used by Rum21/RoyalDesign)
  "noga.cdn-norce.tech",         // Norce commerce CDN (Nordic retailers)
  "*.cdn-norce.tech",            // sleepo.cdn-norce.tech, stalands.cdn-norce.tech, etc.
  "picsum.photos",               // Placeholder images (sample data)
  "*.cloudinary.com",            // Cloudinary CDN (used by many retailers)
  "*.imgix.net",                 // imgix CDN
  "*.storyblok.com",             // Storyblok CDN (e.g. img2.storyblok.com)
  "*.crystallize.com",           // Sweef media host
  "*.scene7.com",                // Adobe Scene7 CDN
  "*.akamaized.net",             // Akamai CDN
  "*.cloudfront.net",            // AWS CloudFront CDN
  "*.jysk.com",                  // cdn1-4.jysk.com
  "*.pictureserver.net",         // Beliani/Folkhemmet image host
  // --- Brand domains (products sold via multiple retailers) ---
  "*.bloomingville.com",         // Bloomingville official media
  "*.gubi.com",                  // Gubi (sold via Rum21, Nordiskagalleriet, etc.)
  "*.haydesign.com",             // HAY Design
  "*.muuto.com",                 // Muuto
  "*.fritzhansen.com",           // Fritz Hansen
  // --- Retailer domains (wildcard *.domain covers subdomains) ---
  "*.ikea.com",                  // www.ikea.com, assets.ikea.com
  "*.mio.se",                    // www.mio.se, images.mio.se
  "*.chilli.se",
  "*.rum21.se",                  // media.rum21.se
  "*.royaldesign.se",            // api-prod.royaldesign.se
  "*.ellosgroup.com",            // assets.ellosgroup.com (Ellos, Jotex)
  "*.ellos.se",                  // ellos.se (may serve images directly)
  "*.jotex.se",
  "*.lannamobler.se",            // cdn.lannamobler.se
  "*.emhome.se",
  "*.furniturebox.se",
  "*.svenskahem.se",
  "*.trademax.se",
  "*.soffadirekt.se",
  "*.sweef.se",
  "*.sleepo.se",
  "*.homeroom.se",
  "*.newport.se",
  "*.nordiskagalleriet.se",
  "*.svenssons.se",
  "*.ilva.se",
  "*.granit.com",
  "*.folkhemmet.com",
  "*.soffkoncept.se",
  "*.tibergsmobler.se",
  "*.affariofsweden.com",
  "*.mcdn.net",                  // mcdn.net, www.mcdn.net
];

class ProxyError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = "ProxyError";
  }
}

export type ImageSceneType = "contextual" | "studio_cutout" | "unknown";

export type ImageMetaResult = {
  valid: boolean;
  url: string;
  domain: string;
  width: number;
  height: number;
  aspectRatio: number;
  aspectCategory: string;
  format: string | undefined;
  size: number;
  sceneType: ImageSceneType;
  displaySuitabilityScore: number;
  sceneMetrics: {
    backgroundRatio: number;
    borderBackgroundRatio: number;
    nearWhiteRatio: number;
    transparentRatio: number;
    subjectCoverage: number;
    textureScore: number;
  };
  issues: string[];
};

type SceneMetrics = ImageMetaResult["sceneMetrics"];

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function round(value: number, decimals: number = 3): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function classifyAspectRatio(ratio: number): string {
  if (ratio < 0.6) return "tall-portrait";
  if (ratio < 0.9) return "portrait";
  if (ratio < 1.1) return "square";
  if (ratio < 1.5) return "landscape";
  return "wide-landscape";
}

function classifySceneFromMetrics(metrics: SceneMetrics): {
  sceneType: ImageSceneType;
  sceneIssues: string[];
} {
  const isTransparentCutout =
    metrics.transparentRatio >= 0.08 &&
    metrics.backgroundRatio >= 0.66 &&
    metrics.borderBackgroundRatio >= 0.72;
  const isWhiteStudioBg =
    metrics.nearWhiteRatio >= 0.62 &&
    metrics.borderBackgroundRatio >= 0.78 &&
    metrics.backgroundRatio >= 0.68;
  const lowTexture = metrics.textureScore < 0.07;

  let sceneType: ImageSceneType = "unknown";
  if (isTransparentCutout || (isWhiteStudioBg && lowTexture)) {
    sceneType = "studio_cutout";
  } else if (
    metrics.backgroundRatio <= 0.58 &&
    metrics.borderBackgroundRatio <= 0.62 &&
    metrics.textureScore >= 0.09 &&
    metrics.subjectCoverage >= 0.35
  ) {
    sceneType = "contextual";
  }

  const sceneIssues: string[] = [];
  if (metrics.transparentRatio >= 0.12) sceneIssues.push("transparent-background");
  if (isWhiteStudioBg) sceneIssues.push("white-background");
  if (sceneType === "studio_cutout") sceneIssues.push("studio-cutout");
  if (sceneType !== "contextual" && metrics.backgroundRatio >= 0.72) {
    sceneIssues.push("low-context-scene");
  }
  return { sceneType, sceneIssues };
}

function scoreDisplaySuitability(input: {
  width: number;
  height: number;
  valid: boolean;
  sceneType: ImageSceneType;
  metrics: SceneMetrics;
}): number {
  const { width, height, valid, sceneType, metrics } = input;
  if (!valid) return 0;

  let score = 70;
  const minDim = Math.min(width, height);
  if (minDim < MIN_RESOLUTION) score -= 45;
  else if (minDim < 800) score -= 15;
  else if (minDim >= 1200) score += 8;

  if (sceneType === "contextual") score += 18;
  if (sceneType === "studio_cutout") score -= 25;

  if (metrics.transparentRatio >= 0.12) score -= 12;
  if (metrics.nearWhiteRatio >= 0.7 && metrics.borderBackgroundRatio >= 0.78) score -= 8;

  // Texture reward: scene-rich images usually have moderate-to-high gradients.
  score += Math.round((metrics.textureScore - 0.08) * 120);

  // Coverage sweet spot around 0.55 avoids tiny product in frame or over-cropped shots.
  score -= Math.round(Math.abs(metrics.subjectCoverage - 0.55) * 20);

  return clamp(Math.round(score), 0, 100);
}

async function analyzeSceneMetrics(buffer: Buffer): Promise<SceneMetrics> {
  const sample = await sharp(buffer, { limitInputPixels: MAX_IMAGE_PIXELS })
    .ensureAlpha()
    .resize(SCENE_SAMPLE_SIZE, SCENE_SAMPLE_SIZE, {
      fit: "inside",
      withoutEnlargement: true,
    })
    .raw()
    .toBuffer({ resolveWithObject: true });

  const width = sample.info.width;
  const height = sample.info.height;
  const channels = sample.info.channels;
  const data = sample.data;
  if (width <= 1 || height <= 1 || channels < 4) {
    return {
      backgroundRatio: 0,
      borderBackgroundRatio: 0,
      nearWhiteRatio: 0,
      transparentRatio: 0,
      subjectCoverage: 0,
      textureScore: 0,
    };
  }

  const total = width * height;
  const borderWidth = Math.max(1, Math.round(Math.min(width, height) * BORDER_RATIO));

  let transparentPixels = 0;
  let nearWhitePixels = 0;
  let backgroundPixels = 0;
  let borderPixels = 0;
  let borderBackgroundPixels = 0;
  let gradientSum = 0;
  let gradientCount = 0;
  let foregroundCount = 0;
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;

  const pxIndex = (x: number, y: number) => (y * width + x) * channels;
  const luminanceAt = (x: number, y: number): number => {
    const idx = pxIndex(x, y);
    const r = data[idx];
    const g = data[idx + 1];
    const b = data[idx + 2];
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const idx = pxIndex(x, y);
      const r = data[idx];
      const g = data[idx + 1];
      const b = data[idx + 2];
      const alpha = data[idx + 3];
      const alphaNorm = alpha / 255;
      const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      const max = Math.max(r, g, b);
      const min = Math.min(r, g, b);
      const saturation = max === 0 ? 0 : (max - min) / max;
      const transparent = alphaNorm < 0.08;
      const nearWhite = alphaNorm >= 0.9 && lum >= 245 && saturation <= 0.12;
      const backgroundLike = transparent || nearWhite;

      if (transparent) transparentPixels += 1;
      if (nearWhite) nearWhitePixels += 1;
      if (backgroundLike) backgroundPixels += 1;

      const isBorder =
        x < borderWidth || x >= width - borderWidth || y < borderWidth || y >= height - borderWidth;
      if (isBorder) {
        borderPixels += 1;
        if (backgroundLike) borderBackgroundPixels += 1;
      }

      if (!backgroundLike) {
        foregroundCount += 1;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }

      if (x + 1 < width && y + 1 < height) {
        const lumX = luminanceAt(x + 1, y);
        const lumY = luminanceAt(x, y + 1);
        gradientSum += Math.abs(lumX - lum) + Math.abs(lumY - lum);
        gradientCount += 2;
      }
    }
  }

  let subjectCoverage = 0;
  if (foregroundCount > 0 && maxX >= minX && maxY >= minY) {
    const bboxArea = (maxX - minX + 1) * (maxY - minY + 1);
    subjectCoverage = bboxArea / total;
  }

  return {
    backgroundRatio: round(backgroundPixels / total),
    borderBackgroundRatio: round(borderPixels > 0 ? borderBackgroundPixels / borderPixels : 0),
    nearWhiteRatio: round(nearWhitePixels / total),
    transparentRatio: round(transparentPixels / total),
    subjectCoverage: round(subjectCoverage),
    textureScore: round(gradientCount > 0 ? gradientSum / (gradientCount * 255) : 0),
  };
}

function envInt(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function isPrivateIpv4(hostname: string): boolean {
  const parts = hostname.split(".").map((p) => parseInt(p, 10));
  if (parts.length !== 4 || parts.some((p) => !Number.isFinite(p) || p < 0 || p > 255)) return false;
  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 0) return true;
  return false;
}

function isPrivateIpv6(hostname: string): boolean {
  const h = hostname.toLowerCase();
  if (h === "::1") return true;
  if (h.startsWith("fc") || h.startsWith("fd")) return true; // unique local
  if (h.startsWith("fe80")) return true; // link-local
  return false;
}

function isPrivateHost(hostname: string): boolean {
  const h = hostname.toLowerCase();
  if (!h) return true;
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".local")) return true;
  if (isPrivateIpv4(h)) return true;
  if (isPrivateIpv6(h)) return true;
  return false;
}

function parseAllowedDomains(): string[] {
  const raw = process.env.IMAGE_PROXY_ALLOWED_DOMAINS || "";
  const fromEnv = raw
    .split(",")
    .map((v) => v.trim().toLowerCase())
    .filter((v) => v.length > 0);
  return fromEnv.length > 0 ? fromEnv : DEFAULT_ALLOWED_DOMAINS;
}

function hostMatchesPattern(hostname: string, pattern: string): boolean {
  const host = hostname.toLowerCase();
  const p = pattern.toLowerCase();
  if (p.startsWith("*.")) {
    const suffix = p.slice(2);
    return host === suffix || host.endsWith(`.${suffix}`);
  }
  return host === p || host.endsWith(`.${p}`);
}

function isHostAllowed(hostname: string): boolean {
  const allowedDomains = parseAllowedDomains();
  if (allowedDomains.length === 0) return true;
  return allowedDomains.some((pattern) => hostMatchesPattern(hostname, pattern));
}

function assertAllowedTarget(parsedUrl: URL): void {
  if (!["http:", "https:"].includes(parsedUrl.protocol)) {
    throw new ProxyError(400, "Only HTTP/HTTPS URLs are allowed");
  }

  if (parsedUrl.username || parsedUrl.password) {
    throw new ProxyError(400, "Credentials in URL are not allowed");
  }

  const hostname = parsedUrl.hostname.toLowerCase();
  const allowPrivate = process.env.IMAGE_PROXY_ALLOW_PRIVATE === "true";
  if (!allowPrivate && isPrivateHost(hostname)) {
    throw new ProxyError(400, "Target host is not allowed");
  }

  // Only allow plain HTTP for explicit local/dev scenarios.
  if (parsedUrl.protocol === "http:" && !allowPrivate) {
    throw new ProxyError(400, "Only HTTPS is allowed");
  }

  if (!isHostAllowed(hostname)) {
    console.warn(`[image-proxy] BLOCKED domain: ${hostname} (url: ${parsedUrl.href.slice(0, 200)})`);
    throw new ProxyError(403, `Target domain is not allowed: ${hostname}`);
  }
}

async function fetchWithTimeout(url: string, acceptHeader: string): Promise<globalThis.Response> {
  const timeoutMs = envInt("IMAGE_PROXY_FETCH_TIMEOUT_MS", DEFAULT_TIMEOUT_MS);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; Swiper/1.0)",
        "Accept": acceptHeader,
      },
      signal: controller.signal,
      redirect: "follow",
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new ProxyError(504, "Upstream request timed out");
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function assertImageResponse(response: globalThis.Response): void {
  if (!response.ok) {
    throw new ProxyError(response.status, `Upstream error: ${response.status}`);
  }
  const contentType = (response.headers.get("content-type") || "").toLowerCase();
  if (!contentType.startsWith("image/")) {
    throw new ProxyError(415, "Upstream content is not an image");
  }
}

async function readResponseBufferStrict(response: globalThis.Response, maxBytes: number): Promise<Buffer> {
  const contentLengthHeader = response.headers.get("content-length");
  if (contentLengthHeader) {
    const contentLength = parseInt(contentLengthHeader, 10);
    if (Number.isFinite(contentLength) && contentLength > maxBytes) {
      throw new ProxyError(413, "Upstream image too large");
    }
  }

  if (!response.body) {
    throw new ProxyError(502, "Missing upstream response body");
  }

  const reader = response.body.getReader();
  const chunks: Buffer[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value || value.byteLength === 0) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => undefined);
      throw new ProxyError(413, "Upstream image too large");
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

/**
 * Image proxy endpoint to serve external images through our API.
 * This avoids CORS issues and provides CDN-like image optimization.
 * 
 * GET /api/image-proxy?url=<encoded-url>&w=<width>&format=<webp|jpeg|png>
 * 
 * Parameters:
 * - url: Required. The source image URL (must be from allowed domains)
 * - w: Optional. Target width in pixels (400, 800, 1200). Height auto-calculated.
 * - format: Optional. Output format (webp, jpeg, png). Default: webp if supported, else jpeg.
 * - q: Optional. Quality (1-100). Default: 80.
 */
export async function imageProxyGet(req: Request, res: Response): Promise<void> {
  const url = req.query.url as string;
  const widthParam = req.query.w as string | undefined;
  const formatParam = req.query.format as string | undefined;
  const qualityParam = req.query.q as string | undefined;
  
  if (!url) {
    res.status(400).json({ error: "Missing 'url' parameter" });
    return;
  }

  // Parse parameters
  const parsedWidth = widthParam != null ? parseInt(widthParam, 10) : undefined;
  if (widthParam != null && !Number.isFinite(parsedWidth)) {
    res.status(400).json({ error: "Invalid width value" });
    return;
  }
  const width = parsedWidth;

  const parsedQuality = qualityParam != null ? parseInt(qualityParam, 10) : undefined;
  if (qualityParam != null && !Number.isFinite(parsedQuality)) {
    res.status(400).json({ error: "Invalid quality value" });
    return;
  }
  const quality = parsedQuality != null ? Math.min(100, Math.max(1, parsedQuality)) : 80;
  
  // Validate width if provided
  if (width != null && !ALLOWED_WIDTHS.includes(width)) {
    res.status(400).json({ 
      error: `Invalid width. Allowed values: ${ALLOWED_WIDTHS.join(", ")}` 
    });
    return;
  }

  // Determine output format
  const acceptHeader = req.headers.accept || "";
  const supportsWebP = acceptHeader.includes("image/webp");
  let outputFormat: "webp" | "jpeg" | "png" = supportsWebP ? "webp" : "jpeg";
  
  if (formatParam) {
    if (["webp", "jpeg", "png"].includes(formatParam)) {
      outputFormat = formatParam as "webp" | "jpeg" | "png";
    } else {
      res.status(400).json({ error: "Invalid format. Allowed: webp, jpeg, png" });
      return;
    }
  }

  // Validate URL is well-formed and uses HTTPS (or HTTP for local dev)
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(url);
  } catch {
    res.status(400).json({ error: "Invalid URL" });
    return;
  }

  try {
    assertAllowedTarget(parsedUrl);
  } catch (error) {
    const e = error as Error;
    if (e instanceof ProxyError) {
      res.status(e.status).json({ error: e.message });
      return;
    }
    res.status(400).json({ error: "Invalid URL" });
    return;
  }

  try {
    const response = await fetchWithTimeout(url, "image/*");
    assertImageResponse(response);
    const maxBytes = envInt("IMAGE_PROXY_MAX_UPSTREAM_BYTES", DEFAULT_PROXY_MAX_BYTES);
    const buffer = await readResponseBufferStrict(response, maxBytes);
    
    // Process image with sharp
    let pipeline = sharp(buffer, { limitInputPixels: 40_000_000 });
    
    // Resize if width specified (maintains aspect ratio)
    if (width) {
      pipeline = pipeline.resize(width, undefined, {
        fit: "inside",
        withoutEnlargement: true, // Don't upscale small images
      });
    }
    
    // Convert to target format
    let outputBuffer: Buffer;
    let contentType: string;
    
    switch (outputFormat) {
      case "webp":
        outputBuffer = await pipeline.webp({ quality }).toBuffer();
        contentType = "image/webp";
        break;
      case "png":
        outputBuffer = await pipeline.png({ quality: Math.round(quality / 10) }).toBuffer();
        contentType = "image/png";
        break;
      case "jpeg":
      default:
        outputBuffer = await pipeline.jpeg({ quality, mozjpeg: true }).toBuffer();
        contentType = "image/jpeg";
        break;
    }

    // Build cache key components for Vary header
    const varyHeaders = ["Accept"];
    
    // Set cache headers (cache for 7 days)
    res.set({
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=604800, immutable",
      "Access-Control-Allow-Origin": "*",
      "Vary": varyHeaders.join(", "),
      "X-Image-Width": width?.toString() || "original",
      "X-Image-Format": outputFormat,
    });

    res.send(outputBuffer);
  } catch (error) {
    console.error("Image proxy error:", error);
    if (error instanceof ProxyError) {
      res.status(error.status).json({ error: error.message });
      return;
    }
    res.status(502).json({ error: "Failed to process image" });
  }
}

/**
 * Analyze image metadata and visual suitability from a URL.
 * Used for image validation (resolution + scene quality checks).
 */
export async function analyzeImageUrl(url: string): Promise<ImageMetaResult> {
  const parsedUrl = new URL(url);
  assertAllowedTarget(parsedUrl);

  const response = await fetchWithTimeout(url, "image/*");
  assertImageResponse(response);
  const maxBytes = envInt("IMAGE_META_MAX_BYTES", DEFAULT_META_MAX_BYTES);
  const buffer = await readResponseBufferStrict(response, maxBytes);

  const metadata = await sharp(buffer, { limitInputPixels: MAX_IMAGE_PIXELS }).metadata();
  const width = metadata.width || 0;
  const height = metadata.height || 0;
  const aspectRatio = height > 0 ? width / height : 0;
  const aspectCategory = classifyAspectRatio(aspectRatio);
  const isBroken = width === 0 || height === 0;
  const valid = width >= MIN_RESOLUTION && height >= MIN_RESOLUTION && !isBroken;

  const sceneMetrics = await analyzeSceneMetrics(buffer);
  const { sceneType, sceneIssues } = classifySceneFromMetrics(sceneMetrics);
  const issues = [
    ...(isBroken ? ["broken"] : []),
    ...(width < MIN_RESOLUTION && !isBroken ? ["low-resolution"] : []),
    ...(aspectRatio > 2.5 ? ["extreme-aspect-ratio"] : []),
    ...sceneIssues,
  ];
  const displaySuitabilityScore = scoreDisplaySuitability({
    width,
    height,
    valid,
    sceneType,
    metrics: sceneMetrics,
  });

  return {
    valid,
    url,
    domain: parsedUrl.hostname,
    width,
    height,
    aspectRatio: round(aspectRatio, 2),
    aspectCategory,
    format: metadata.format,
    size: buffer.length,
    sceneType,
    displaySuitabilityScore,
    sceneMetrics,
    issues: Array.from(new Set(issues)),
  };
}

/**
 * Get image metadata by downloading an image.
 * 
 * GET /api/image-meta?url=<encoded-url>
 */
export async function imageMetaGet(req: Request, res: Response): Promise<void> {
  const url = req.query.url as string;
  
  if (!url) {
    res.status(400).json({ error: "Missing 'url' parameter" });
    return;
  }

  try {
    const result = await analyzeImageUrl(url);
    res.json(result);
    return;
  } catch (error) {
    console.error("Image meta error:", error);
    if (error instanceof ProxyError) {
      res.status(error.status).json({
        valid: false,
        error: error.message,
        url: url,
      });
      return;
    }
    res.json({
      valid: false,
      error: "Failed to analyze image",
      url: url,
    });
  }
}

export const __imageProxyTestUtils = {
  classifySceneFromMetrics,
  scoreDisplaySuitability,
  hostMatchesPattern,
  isHostAllowed,
};
