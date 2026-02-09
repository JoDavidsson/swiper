"""Normalize raw values to TAG_TAXONOMY (material, colorFamily, sizeClass, styleTags, ecoTags).

Also includes URL normalization for source configuration.
"""
import html
import math
import re
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


def canonical_domain(domain: str) -> str:
    """
    Normalize a domain by stripping the www. prefix for comparison.
    
    This allows treating www.example.com and example.com as equivalent
    for same-site checks, sitemap filtering, and robots.txt caching.
    
    Examples:
    - "www.example.com" -> "example.com"
    - "example.com" -> "example.com"
    - "WWW.EXAMPLE.COM" -> "example.com"
    - "sub.example.com" -> "sub.example.com" (non-www subdomains preserved)
    """
    if not domain:
        return ""
    d = domain.lower().strip()
    if d.startswith("www."):
        return d[4:]
    return d


def domains_equivalent(d1: str, d2: str) -> bool:
    """
    Check if two domains are equivalent (handles www vs apex).
    
    Returns True if both domains resolve to the same canonical domain.
    
    Examples:
    - domains_equivalent("www.example.com", "example.com") -> True
    - domains_equivalent("example.com", "www.example.com") -> True
    - domains_equivalent("example.com", "other.com") -> False
    - domains_equivalent("sub.example.com", "example.com") -> False
    """
    return canonical_domain(d1) == canonical_domain(d2)

MATERIAL_MAP = {
    "fabric": ["fabric", "cloth", "textile", "cotton", "bomull", "linen", "linne", "polyester", "tyg", "klädsel", "remix", "hallingdal", "steelcut", "canvas", "tweed", "chenille"],
    "leather": ["leather", "läder", "skinn", "nubuck", "nappa"],
    "velvet": ["velvet", "sammet", "velour"],
    "boucle": ["boucle", "bouclé"],
    "wool": ["wool", "ull", "ylle", "merino", "felt", "filt"],
    "wood": ["wood", "timber", "oak", "ek", "birch", "björk", "pine", "furu", "teak", "walnut", "valnöt", "ash", "ask", "beech", "bok", "bamboo", "bambu"],
    "metal": ["metal", "metall", "steel", "stål", "iron", "järn", "chrome", "krom", "aluminium", "aluminum", "brass", "mässing", "copper", "koppar"],
    "rattan": ["rattan", "rotting", "wicker", "korg"],
    "plastic": ["plastic", "plast", "polypropylene", "polypropen", "acrylic", "akryl", "abs"],
    "mixed": ["mixed", "combination", "kombination"],
}

COLOR_MAP = {
    "white": ["white", "vit", "bianco", "ivory", "elfenben", "snow", "chalk", "krita"],
    "beige": ["beige", "sand", "cream", "off-white", "natural", "linen", "linne", "taupe", "ecru", "oat", "wheat", "havremjölk"],
    "brown": ["brown", "brun", "marron", "walnut", "oak", "cognac", "camel", "tan", "chocolate", "espresso", "mocha", "terracotta", "terrakotta", "rust", "rost", "copper", "koppar"],
    "gray": ["gray", "grey", "grå", "anthracite", "antracit", "charcoal", "kol", "graphite", "grafit", "silver", "ash", "aska", "slate", "stone", "cement"],
    "black": ["black", "svart", "noir", "jet", "onyx", "ebony"],
    "green": ["green", "grön", "vert", "olive", "oliv", "sage", "salvia", "moss", "mossa", "forest", "emerald", "khaki", "mint"],
    "blue": ["blue", "blå", "bleu", "navy", "marinblå", "marin", "indigo", "cobalt", "teal", "petrol", "ocean", "sky", "denim"],
    "red": ["red", "röd", "rouge", "burgundy", "vinröd", "bordeaux", "crimson", "wine", "vin", "cherry", "maroon"],
    "yellow": ["yellow", "gul", "jaune", "mustard", "senap", "gold", "guld", "honey", "honung", "amber", "bärnsten", "curry"],
    "orange": ["orange", "terracotta", "terrakotta", "peach", "persika", "apricot", "coral", "korall"],
    "pink": ["pink", "rosa", "blush", "dusty rose", "salmon", "lax", "fuchsia", "magenta"],
    "multi": ["multi", "multicolor", "mixed", "flerfärgad", "mönstrad", "patterned"],
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


def _word_boundary_match(needle: str, haystack: str) -> bool:
    """Check if *needle* appears as a whole word (or word-prefix) in *haystack*.

    Uses regex word boundaries to avoid false positives like "kol" inside
    "kollektionen" or "red" inside "inredningsstilar".
    """
    # Multi-word needles (e.g. "dusty rose", "off-white") — match literally
    # Single-word needles — require word boundaries on both sides
    import re
    pattern = r"\b" + re.escape(needle) + r"\b"
    return bool(re.search(pattern, haystack))


def infer_color_from_title(title: str) -> str | None:
    """
    Scan title for COLOR_MAP tokens. Returns first matching canonical color or None.
    E.g. "Bolero 3-sits soffa svart" -> "black"
    """
    if not title or not isinstance(title, str):
        return None
    s = title.lower()
    for canonical, variants in COLOR_MAP.items():
        if any(_word_boundary_match(v, s) for v in variants):
            return canonical
    return None


def infer_material_from_text(title: str | None, description: str | None) -> str | None:
    """
    Try to infer a canonical material from title first, then description.

    Checks title first (e.g. "Soffa 3-sits läder"), then falls back to
    description for more detailed material mentions.
    """
    for text in (title, description):
        if not text or not isinstance(text, str):
            continue
        s = text.lower()
        for canonical, variants in MATERIAL_MAP.items():
            if any(_word_boundary_match(v, s) for v in variants):
                return canonical
    return None


def infer_color_from_text(title: str | None, description: str | None) -> str | None:
    """
    Try to infer a canonical color from title first, then description.

    Title is checked first because it's more specific (e.g. "Soffa 3-sits svart").
    Description is a fallback for when the title only has a fabric code
    (e.g. "Remix 163") but the description mentions the actual color.
    """
    if title:
        result = infer_color_from_title(title)
        if result:
            return result
    if description and isinstance(description, str):
        s = description.lower()
        for canonical, variants in COLOR_MAP.items():
            if any(_word_boundary_match(v, s) for v in variants):
                return canonical
    return None


def infer_size_from_title(title: str) -> str | None:
    """
    Infer sofa size class from Swedish/English product title patterns.

    Patterns:
      small  – 1-sits, 2-sits, fåtölj, schäslong (single/compact seating)
      medium – 3-sits (standard sofa)
      large  – 4-sits, 5-sits, 6-sits+, U-soffa, U-formad, modulsoffa, hörnbäddsoffa
    """
    import re
    if not title or not isinstance(title, str):
        return None
    s = title.lower()

    # Check N-sits patterns first (most reliable)
    m = re.search(r"(\d+)\s*-?\s*sits", s)
    if m:
        seats = int(m.group(1))
        if seats <= 2:
            return "small"
        if seats == 3:
            return "medium"
        return "large"  # 4+ sits

    # Large indicators
    large_keywords = ["u-soffa", "u-formad", "modulsoffa", "hörnbäddsoffa",
                      "hörnsoffa", "u-bäddsoffa", "sectional", "corner sofa",
                      "modular"]
    if any(kw in s for kw in large_keywords):
        return "large"

    # Small indicators
    small_keywords = ["fåtölj", "armchair", "schäslong", "chaise", "fotpall",
                      "ottoman", "puff", "loveseat"]
    if any(kw in s for kw in small_keywords):
        return "small"

    return None


def normalize_size_class(raw: Any, width_cm: float | None = None, title: str | None = None) -> str:
    if width_cm is not None:
        return size_class_from_width_cm(width_cm)
    if raw is not None and isinstance(raw, str) and raw.strip():
        s = raw.lower().strip()
        if s in ("small", "medium", "large"):
            return s
        if "small" in s or "compact" in s:
            return "small"
        if "large" in s or "wide" in s:
            return "large"
    # Infer from title when no explicit size data
    if title:
        inferred = infer_size_from_title(title)
        if inferred:
            return inferred
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


def normalize_price_amount(raw: Any) -> float | None:
    """Parse price into a positive finite float.

    Returns None for missing/invalid/zero/negative values to avoid showing 0 SEK.
    """
    if raw is None:
        return None
    if isinstance(raw, str):
        text = raw.replace("\u00a0", " ").strip()
        if not text:
            return None
        # Take first numeric span to handle ranges like "12 999 - 15 999 kr".
        m = re.search(r"-?\d[\d\s.,]*", text)
        if not m:
            return None
        token = m.group(0).strip().replace(" ", "")
        if not token:
            return None

        sign = -1 if token.startswith("-") else 1
        token = token.lstrip("-").strip(".,")
        if not token:
            return None

        if "," in token and "." in token:
            # Last separator is decimal separator; the other is thousands separator.
            if token.rfind(",") > token.rfind("."):
                token = token.replace(".", "").replace(",", ".")
            else:
                token = token.replace(",", "")
        elif token.count(",") == 1 and token.count(".") == 0:
            left, right = token.split(",", 1)
            if len(right) == 3 and left.isdigit() and right.isdigit():
                token = left + right  # thousands group
            else:
                token = left + "." + right  # decimal comma
        elif token.count(".") == 1 and token.count(",") == 0:
            left, right = token.split(".", 1)
            if len(right) == 3 and left.isdigit() and right.isdigit():
                token = left + right  # thousands group
        elif token.count(",") > 1 and token.count(".") == 0:
            token = token.replace(",", "")
        elif token.count(".") > 1 and token.count(",") == 0:
            token = token.replace(".", "")

        raw = f"-{token}" if sign < 0 else token
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(value) or value <= 0:
        return None
    return value


def clean_description_text(raw: Any) -> str | None:
    """Decode HTML entities/tags and normalize whitespace for product descriptions.

    Handles double/triple-encoded HTML entities by running unescape in a loop
    until the output stabilises (up to 3 passes).
    """
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None

    # Multi-pass unescape to handle double/triple-encoded entities
    # e.g. "&amp;lt;p&amp;gt;" -> "&lt;p&gt;" -> "<p>"
    for _ in range(3):
        unescaped = html.unescape(text)
        if unescaped == text:
            break
        text = unescaped

    # Convert line-break tags to actual line breaks.
    text = re.sub(r"(?i)<\s*br\s*/?\s*>", "\n", text)
    # Remove remaining tags (run twice to catch nested/malformed tags).
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)

    # Final unescape pass to catch entities that were inside tags.
    text = html.unescape(text)

    # Normalize per-line whitespace while keeping paragraphs.
    lines = [re.sub(r"\s+", " ", ln).strip() for ln in text.splitlines()]
    lines = [ln for ln in lines if ln]
    if not lines:
        return None
    return "\n\n".join(lines)


# ============================================================================
# CURRENCY VALIDATION
# ============================================================================

# Accepted currencies for the Swedish market.
_ACCEPTED_CURRENCIES = {"SEK", "KR"}


def validate_currency(raw: str | None) -> str | None:
    """Return 'SEK' if the currency is acceptable for our market, else None.

    Accepts 'SEK', 'kr' (case-insensitive).  Returns None for EUR, USD, etc.
    so the caller can decide whether to skip or flag the item.
    """
    if not raw:
        return None
    normalised = raw.strip().upper()
    if normalised in _ACCEPTED_CURRENCIES:
        return "SEK"
    return None
