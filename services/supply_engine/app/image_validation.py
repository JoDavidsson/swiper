"""Image validation and metadata extraction for product images.

This module validates images during ingestion to ensure they meet quality standards
and calculates a Creative Health score for retailer feedback.
"""
import asyncio
import logging
from dataclasses import dataclass
from typing import Optional
from urllib.parse import urlparse

import httpx
from PIL import Image
from io import BytesIO

logger = logging.getLogger(__name__)

# Validation thresholds
MIN_WIDTH = 400
MIN_HEIGHT = 400
MAX_ASPECT_RATIO = 3.0  # Extreme aspect ratios are problematic
PREFERRED_ASPECT_MIN = 0.6  # Portrait OK
PREFERRED_ASPECT_MAX = 1.8  # Landscape OK

# Creative Health thresholds
EXCELLENT_RESOLUTION = 1200
GOOD_RESOLUTION = 800


@dataclass
class ImageMetadata:
    """Metadata extracted from an image."""
    url: str
    valid: bool
    width: int
    height: int
    aspect_ratio: float
    aspect_category: str
    file_size: int
    format: str
    issues: list[str]
    creative_health_score: int
    
    def to_dict(self) -> dict:
        """Convert to dictionary for Firestore storage."""
        return {
            "url": self.url,
            "valid": self.valid,
            "width": self.width,
            "height": self.height,
            "aspectRatio": round(self.aspect_ratio, 2),
            "aspectCategory": self.aspect_category,
            "fileSize": self.file_size,
            "format": self.format,
            "issues": self.issues,
            "creativeHealthScore": self.creative_health_score,
        }


def classify_aspect_ratio(ratio: float) -> str:
    """Classify aspect ratio into a human-readable category."""
    if ratio < 0.6:
        return "tall-portrait"
    elif ratio < 0.9:
        return "portrait"
    elif ratio < 1.1:
        return "square"
    elif ratio < 1.5:
        return "landscape"
    else:
        return "wide-landscape"


def calculate_creative_health_score(
    width: int,
    height: int,
    aspect_ratio: float,
    is_broken: bool,
    file_size: int,
) -> tuple[int, list[str]]:
    """
    Calculate a Creative Health score (0-100) for an image.
    
    Returns:
        Tuple of (score, issues_list)
    """
    if is_broken:
        return 0, ["broken"]
    
    issues = []
    score = 100
    
    # Resolution scoring
    min_dim = min(width, height)
    if min_dim < MIN_WIDTH:
        score -= 40
        issues.append("low-resolution")
    elif min_dim < GOOD_RESOLUTION:
        score -= 15
        issues.append("medium-resolution")
    elif min_dim >= EXCELLENT_RESOLUTION:
        # Bonus for high resolution (but cap at 100)
        pass
    
    # Aspect ratio scoring
    if aspect_ratio > MAX_ASPECT_RATIO or aspect_ratio < (1 / MAX_ASPECT_RATIO):
        score -= 25
        issues.append("extreme-aspect-ratio")
    elif aspect_ratio > PREFERRED_ASPECT_MAX or aspect_ratio < PREFERRED_ASPECT_MIN:
        score -= 10
        issues.append("unusual-aspect-ratio")
    
    # File size scoring (too small = low quality, too large = slow loading)
    if file_size < 10_000:  # Less than 10KB
        score -= 20
        issues.append("tiny-file-size")
    elif file_size > 5_000_000:  # More than 5MB
        score -= 10
        issues.append("large-file-size")
    
    return max(0, score), issues


async def validate_image_url(url: str, timeout: float = 10.0) -> ImageMetadata:
    """
    Fetch and validate a single image URL.
    
    Args:
        url: The image URL to validate
        timeout: Request timeout in seconds
        
    Returns:
        ImageMetadata object with validation results
    """
    default_failed = ImageMetadata(
        url=url,
        valid=False,
        width=0,
        height=0,
        aspect_ratio=0,
        aspect_category="unknown",
        file_size=0,
        format="unknown",
        issues=["fetch-failed"],
        creative_health_score=0,
    )
    
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 (compatible; Swiper/1.0)",
                    "Accept": "image/*",
                },
                follow_redirects=True,
            )
            
            if response.status_code != 200:
                return ImageMetadata(
                    url=url,
                    valid=False,
                    width=0,
                    height=0,
                    aspect_ratio=0,
                    aspect_category="unknown",
                    file_size=0,
                    format="unknown",
                    issues=[f"http-{response.status_code}"],
                    creative_health_score=0,
                )
            
            content = response.content
            file_size = len(content)
            
            # Parse image with PIL
            try:
                img = Image.open(BytesIO(content))
                width, height = img.size
                img_format = img.format or "unknown"
            except Exception as e:
                logger.warning(f"Failed to parse image {url}: {e}")
                return ImageMetadata(
                    url=url,
                    valid=False,
                    width=0,
                    height=0,
                    aspect_ratio=0,
                    aspect_category="unknown",
                    file_size=file_size,
                    format="unknown",
                    issues=["corrupt-image"],
                    creative_health_score=0,
                )
            
            # Calculate metrics
            is_broken = width == 0 or height == 0
            aspect_ratio = width / height if height > 0 else 0
            aspect_category = classify_aspect_ratio(aspect_ratio) if not is_broken else "unknown"
            
            # Validate dimensions
            valid = (
                not is_broken
                and width >= MIN_WIDTH
                and height >= MIN_HEIGHT
            )
            
            # Calculate creative health score
            health_score, issues = calculate_creative_health_score(
                width=width,
                height=height,
                aspect_ratio=aspect_ratio,
                is_broken=is_broken,
                file_size=file_size,
            )
            
            return ImageMetadata(
                url=url,
                valid=valid,
                width=width,
                height=height,
                aspect_ratio=aspect_ratio,
                aspect_category=aspect_category,
                file_size=file_size,
                format=img_format.lower() if img_format else "unknown",
                issues=issues,
                creative_health_score=health_score,
            )
            
    except httpx.TimeoutException:
        return ImageMetadata(
            url=url,
            valid=False,
            width=0,
            height=0,
            aspect_ratio=0,
            aspect_category="unknown",
            file_size=0,
            format="unknown",
            issues=["timeout"],
            creative_health_score=0,
        )
    except Exception as e:
        logger.warning(f"Image validation error for {url}: {e}")
        return default_failed


async def validate_images(urls: list[str], max_concurrent: int = 5) -> list[ImageMetadata]:
    """
    Validate multiple images concurrently.
    
    Args:
        urls: List of image URLs to validate
        max_concurrent: Maximum concurrent requests
        
    Returns:
        List of ImageMetadata objects in the same order as input URLs
    """
    semaphore = asyncio.Semaphore(max_concurrent)
    
    async def validate_with_semaphore(url: str) -> ImageMetadata:
        async with semaphore:
            return await validate_image_url(url)
    
    tasks = [validate_with_semaphore(url) for url in urls]
    return await asyncio.gather(*tasks)


def validate_images_sync(urls: list[str]) -> list[ImageMetadata]:
    """
    Synchronous wrapper for validate_images.
    
    Args:
        urls: List of image URLs to validate
        
    Returns:
        List of ImageMetadata objects
    """
    return asyncio.run(validate_images(urls))


def calculate_product_creative_health(image_metadatas: list[ImageMetadata]) -> dict:
    """
    Calculate overall Creative Health for a product based on all its images.
    
    Returns a dict with:
    - score: Overall 0-100 score
    - band: "green" | "yellow" | "red"
    - primaryImageValid: Whether the first image is valid
    - validImageCount: Number of valid images
    - issues: Combined issues from all images
    """
    if not image_metadatas:
        return {
            "score": 0,
            "band": "red",
            "primaryImageValid": False,
            "validImageCount": 0,
            "issues": ["no-images"],
        }
    
    # Primary image is most important
    primary = image_metadatas[0]
    valid_count = sum(1 for m in image_metadatas if m.valid)
    
    # Weighted score: primary image is 70%, average of rest is 30%
    if len(image_metadatas) == 1:
        overall_score = primary.creative_health_score
    else:
        other_scores = [m.creative_health_score for m in image_metadatas[1:]]
        avg_other = sum(other_scores) / len(other_scores) if other_scores else 0
        overall_score = int(0.7 * primary.creative_health_score + 0.3 * avg_other)
    
    # Penalty if primary image is invalid
    if not primary.valid:
        overall_score = min(overall_score, 25)
    
    # Determine band
    if overall_score >= 75:
        band = "green"
    elif overall_score >= 45:
        band = "yellow"
    else:
        band = "red"
    
    # Collect unique issues
    all_issues = set()
    for m in image_metadatas:
        all_issues.update(m.issues)
    
    return {
        "score": overall_score,
        "band": band,
        "primaryImageValid": primary.valid,
        "validImageCount": valid_count,
        "totalImageCount": len(image_metadatas),
        "issues": list(all_issues),
    }
