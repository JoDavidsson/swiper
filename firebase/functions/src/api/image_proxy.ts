import { Request, Response } from "express";
import sharp from "sharp";

const ALLOWED_WIDTHS = [400, 800, 1200];
const DEFAULT_TIMEOUT_MS = 8000;
const DEFAULT_PROXY_MAX_BYTES = 12 * 1024 * 1024; // 12MB
const DEFAULT_META_MAX_BYTES = 1024 * 1024; // 1MB prefix for metadata
const DEFAULT_ALLOWED_DOMAINS = [
  // --- CDN / media domains ---
  "images.unsplash.com",
  "*.shopify.com",               // cdn.shopify.com and other Shopify subdomains
  "cdn.bolia.com",
  "images.prismic.io",           // Prismic CMS (used by Rum21/RoyalDesign)
  "noga.cdn-norce.tech",         // Norce commerce CDN (Nordic retailers)
  "picsum.photos",               // Placeholder images (sample data)
  "*.cloudinary.com",            // Cloudinary CDN (used by many retailers)
  "*.imgix.net",                 // imgix CDN
  "*.scene7.com",                // Adobe Scene7 CDN
  "*.akamaized.net",             // Akamai CDN
  "*.cloudfront.net",            // AWS CloudFront CDN
  // --- Brand domains (products sold via multiple retailers) ---
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
  "*.mcdn.net",                  // mcdn.net, www.mcdn.net
];

class ProxyError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = "ProxyError";
  }
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

  const allowedDomains = parseAllowedDomains();
  if (allowedDomains.length > 0) {
    const ok = allowedDomains.some((pattern) => hostMatchesPattern(hostname, pattern));
    if (!ok) {
      console.warn(`[image-proxy] BLOCKED domain: ${hostname} (url: ${parsedUrl.href.slice(0, 200)})`);
      throw new ProxyError(403, `Target domain is not allowed: ${hostname}`);
    }
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

async function readResponsePrefix(response: globalThis.Response, maxBytes: number): Promise<Buffer> {
  if (!response.body) {
    throw new ProxyError(502, "Missing upstream response body");
  }

  const reader = response.body.getReader();
  const chunks: Buffer[] = [];
  let total = 0;

  while (total < maxBytes) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value || value.byteLength === 0) continue;

    const remaining = maxBytes - total;
    if (value.byteLength > remaining) {
      chunks.push(Buffer.from(value.subarray(0, remaining)));
      total = maxBytes;
      break;
    }

    chunks.push(Buffer.from(value));
    total += value.byteLength;
  }

  await reader.cancel().catch(() => undefined);
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
 * Get image metadata by downloading an image prefix.
 * Used for image validation (resolution check, aspect ratio).
 * 
 * GET /api/image-meta?url=<encoded-url>
 */
export async function imageMetaGet(req: Request, res: Response): Promise<void> {
  const url = req.query.url as string;
  
  if (!url) {
    res.status(400).json({ error: "Missing 'url' parameter" });
    return;
  }

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
    const maxBytes = envInt("IMAGE_META_MAX_BYTES", DEFAULT_META_MAX_BYTES);
    const buffer = await readResponsePrefix(response, maxBytes);
    
    // Get metadata with sharp
    const metadata = await sharp(buffer).metadata();
    
    const width = metadata.width || 0;
    const height = metadata.height || 0;
    const aspectRatio = height > 0 ? width / height : 0;
    
    // Validation rules
    const minResolution = 400;
    const isValid = width >= minResolution && height >= minResolution;
    const isBroken = width === 0 || height === 0;
    
    // Aspect ratio classification
    let aspectCategory: string;
    if (aspectRatio < 0.6) {
      aspectCategory = "tall-portrait";
    } else if (aspectRatio < 0.9) {
      aspectCategory = "portrait";
    } else if (aspectRatio < 1.1) {
      aspectCategory = "square";
    } else if (aspectRatio < 1.5) {
      aspectCategory = "landscape";
    } else {
      aspectCategory = "wide-landscape";
    }

    res.json({
      valid: isValid && !isBroken,
      url: url,
      domain: parsedUrl.hostname,
      width: width,
      height: height,
      aspectRatio: Math.round(aspectRatio * 100) / 100,
      aspectCategory: aspectCategory,
      format: metadata.format,
      size: buffer.length,
      issues: [
        ...(isBroken ? ["broken"] : []),
        ...(width < minResolution && !isBroken ? ["low-resolution"] : []),
        ...(aspectRatio > 2.5 ? ["extreme-aspect-ratio"] : []),
      ],
    });
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
