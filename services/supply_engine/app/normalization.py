"""Normalize raw values to TAG_TAXONOMY (material, colorFamily, sizeClass, styleTags, ecoTags).

Also includes URL normalization for source configuration.
"""
from typing import Any
from urllib.parse import urlparse, urlunparse, parse_qs, urlencode


# ============================================================================
# URL NORMALIZATION FOR SOURCE CONFIGURATION
# ============================================================================

def normalize_source_url(user_input: str) -> dict:
    """
    Normalize user input URL and extract components for crawler configuration.
    
    Handles various input formats:
    - "mio.se" -> adds https://
    - "www.mio.se/soffor" -> adds https://
    - "https://www.mio.se/soffor-och-fatoljer/soffor" -> pass-through
    
    Returns:
        {
            "normalized": "https://www.mio.se/soffor-och-fatoljer/soffor",
            "domain": "www.mio.se",
            "baseUrl": "https://www.mio.se",
            "seedUrl": "https://www.mio.se/soffor-och-fatoljer/soffor",
            "seedPath": "/soffor-och-fatoljer/soffor",
            "seedPathPattern": "/soffor",  # First path segment for filtering
        }
    """
    if not user_input or not isinstance(user_input, str):
        raise ValueError("URL input is required")
    
    url = user_input.strip()
    
    # Add protocol if missing
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
    
    # Parse the URL
    parsed = urlparse(url)
    
    # Validate we have a domain
    if not parsed.netloc:
        raise ValueError(f"Invalid URL: could not extract domain from '{user_input}'")
    
    # Normalize domain (lowercase)
    domain = parsed.netloc.lower()
    
    # Base URL is always the domain root (for robots.txt, relative URL resolution)
    base_url = f"{parsed.scheme}://{domain}"
    
    # Seed URL is the full normalized URL (where to start crawling)
    path = parsed.path or "/"
    seed_url = f"{base_url}{path}".rstrip("/") or base_url
    
    # Extract seed path pattern (first meaningful path segment for filtering sitemaps)
    seed_path_pattern = _extract_seed_path_pattern(path)
    
    return {
        "normalized": seed_url,
        "domain": domain,
        "baseUrl": base_url,
        "seedUrl": seed_url,
        "seedPath": path if path != "/" else "",
        "seedPathPattern": seed_path_pattern,
    }


def _extract_seed_path_pattern(path: str) -> str:
    """
    Extract a path pattern from the URL path for filtering sitemap URLs.
    
    Examples:
    - "/soffor-och-fatoljer/soffor" -> "/soffor" (last segment, likely category)
    - "/products/sofas" -> "/sofas"
    - "/p/product-123" -> "/p/" (product URL pattern)
    - "/" -> "" (no pattern)
    
    The pattern is used to filter sitemap URLs to only those relevant to
    the user's intended category.
    """
    if not path or path == "/":
        return ""
    
    # Split path into segments
    segments = [s for s in path.strip("/").split("/") if s]
    
    if not segments:
        return ""
    
    # If path looks like a product URL (contains /p/ or /product/), extract the pattern
    for i, seg in enumerate(segments):
        if seg.lower() in ("p", "product", "produkt", "products", "produkter"):
            return f"/{seg}/"
    
    # Otherwise use the last segment as the category pattern
    # This helps filter sitemaps to relevant categories
    last_segment = segments[-1]
    return f"/{last_segment}"


def extract_domain_root(url: str) -> str:
    """
    Extract the domain root (scheme + netloc) from any URL.
    
    This is used to construct robots.txt URLs and for domain-level operations.
    
    Examples:
    - "https://www.mio.se/soffor/products" -> "https://www.mio.se"
    - "http://example.com:8080/path" -> "http://example.com:8080"
    """
    if not url:
        return ""
    
    # Add protocol if missing for parsing
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
    
    parsed = urlparse(url)
    if not parsed.netloc:
        return ""
    
    return f"{parsed.scheme}://{parsed.netloc.lower()}"


def extract_domain(url: str) -> str:
    """
    Extract just the domain (netloc) from a URL.
    
    Examples:
    - "https://www.mio.se/soffor" -> "www.mio.se"
    - "mio.se" -> "mio.se"
    """
    if not url:
        return ""
    
    # Add protocol if missing for parsing
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
    
    parsed = urlparse(url)
    return parsed.netloc.lower() if parsed.netloc else ""

MATERIAL_MAP = {
    "fabric": ["fabric", "cloth", "textile", "cotton", "linen", "polyester"],
    "leather": ["leather"],
    "velvet": ["velvet"],
    "boucle": ["boucle", "bouclé"],
    "wood": ["wood", "timber", "oak", "birch", "pine"],
    "metal": ["metal", "steel", "iron", "chrome"],
    "mixed": ["mixed", "combination"],
}

COLOR_MAP = {
    "white": ["white", "vit", "bianco"],
    "beige": ["beige", "sand", "cream", "off-white", "natural"],
    "brown": ["brown", "brun", "marron", "walnut", "oak"],
    "gray": ["gray", "grey", "grå"],
    "black": ["black", "svart", "noir"],
    "green": ["green", "grön", "vert"],
    "blue": ["blue", "blå", "bleu"],
    "red": ["red", "röd", "rouge"],
    "yellow": ["yellow", "gul", "jaune"],
    "orange": ["orange"],
    "pink": ["pink", "rosa"],
    "multi": ["multi", "multicolor", "mixed", "flerfärgad"],
}


def size_class_from_width_cm(w: float | None) -> str:
    if w is None:
        return "medium"
    if w < 180:
        return "small"
    if w > 220:
        return "large"
    return "medium"


def normalize_material(raw: Any) -> str | None:
    if raw is None or (isinstance(raw, str) and not raw.strip()):
        return None
    s = str(raw).lower().strip()
    for canonical, variants in MATERIAL_MAP.items():
        if any(v in s for v in variants):
            return canonical
    return "mixed" if s else None


def normalize_color_family(raw: Any) -> str | None:
    if raw is None or (isinstance(raw, str) and not raw.strip()):
        return None
    s = str(raw).lower().strip()
    for canonical, variants in COLOR_MAP.items():
        if any(v in s for v in variants):
            return canonical
    return "multi" if s else None


def infer_color_from_title(title: str) -> str | None:
    """
    Scan title for COLOR_MAP tokens. Returns first matching canonical color or None.
    E.g. "Bolero 3-sits soffa svart" -> "black"
    """
    if not title or not isinstance(title, str):
        return None
    s = title.lower()
    for canonical, variants in COLOR_MAP.items():
        if any(v in s for v in variants):
            return canonical
    return None


def normalize_size_class(raw: Any, width_cm: float | None = None) -> str:
    if width_cm is not None:
        return size_class_from_width_cm(width_cm)
    if raw is None or (isinstance(raw, str) and not raw.strip()):
        return "medium"
    s = str(raw).lower().strip()
    if s in ("small", "medium", "large"):
        return s
    if "small" in s or "compact" in s:
        return "small"
    if "large" in s or "wide" in s:
        return "large"
    return "medium"


def normalize_new_used(raw: Any) -> str:
    if raw is None:
        return "new"
    s = str(raw).lower().strip()
    if "used" in s or "second" in s or "begagnad" in s:
        return "used"
    return "new"


def canonical_url(url: str) -> str:
    """Canonicalize a URL by removing tracking parameters and normalizing."""
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return url
        netloc = parsed.netloc.lower()
        path = parsed.path or "/"
        q = parse_qs(parsed.query, keep_blank_values=False)
        for key in list(q.keys()):
            if key.lower() in ("utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "fbclid", "gclid"):
                del q[key]
        new_query = urlencode(q, doseq=True) if q else ""
        return urlunparse((parsed.scheme, netloc, path, parsed.params, new_query, ""))
    except Exception:
        return url
