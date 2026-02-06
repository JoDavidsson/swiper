import { Request, Response } from "express";
import sharp from "sharp";

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
  const width = widthParam ? parseInt(widthParam, 10) : undefined;
  const quality = qualityParam ? Math.min(100, Math.max(1, parseInt(qualityParam, 10))) : 80;
  
  // Validate width if provided
  const allowedWidths = [400, 800, 1200];
  if (width && !allowedWidths.includes(width)) {
    res.status(400).json({ 
      error: `Invalid width. Allowed values: ${allowedWidths.join(", ")}` 
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

  // Validate URL is from allowed domains
  const allowedDomains = [
    "media.rum21.se",
    "images.unsplash.com",
    "www.chilli.se",
    "cdn.shopify.com",
    "cdn.bolia.com",
    "www.ikea.com",
    "assets.ikea.com",
    "www.mio.se",
    "images.mio.se",
    "www.mcdn.net",   // mio.se CDN
    "mcdn.net",
    // Add more trusted domains as needed
  ];

  let parsedUrl: URL;
  try {
    parsedUrl = new URL(url);
  } catch {
    res.status(400).json({ error: "Invalid URL" });
    return;
  }

  const isAllowed = allowedDomains.some(domain => 
    parsedUrl.hostname === domain || parsedUrl.hostname.endsWith("." + domain)
  );

  if (!isAllowed) {
    res.status(403).json({ error: "Domain not allowed" });
    return;
  }

  try {
    // Fetch the original image
    const response = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; Swiper/1.0)",
        "Accept": "image/*",
      },
    });

    if (!response.ok) {
      res.status(response.status).json({ error: `Upstream error: ${response.status}` });
      return;
    }

    const buffer = Buffer.from(await response.arrayBuffer());
    
    // Process image with sharp
    let pipeline = sharp(buffer);
    
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
    res.status(502).json({ error: "Failed to process image" });
  }
}

/**
 * Get image metadata without downloading the full image.
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
    // Fetch the image
    const response = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; Swiper/1.0)",
        "Accept": "image/*",
      },
    });

    if (!response.ok) {
      res.json({
        valid: false,
        error: `HTTP ${response.status}`,
        url: url,
      });
      return;
    }

    const buffer = Buffer.from(await response.arrayBuffer());
    
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
    res.json({
      valid: false,
      error: "Failed to analyze image",
      url: url,
    });
  }
}
