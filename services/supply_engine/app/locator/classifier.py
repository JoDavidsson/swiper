from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlparse


_PAGINATION_RE = re.compile(r"(\?|&)(page|p)=\d+", re.IGNORECASE)
_PRODUCT_ID_RE = re.compile(r"-p\d+(?:-v\d+)?\b", re.IGNORECASE)  # common ecommerce pattern (e.g. chilli.se)

# Strong product path patterns - these indicate a specific product page
# NOTE: /p/ must be followed by content (not just /p or /p/)
_PRODUCT_PATH_RE = re.compile(r"/p/[a-z0-9]", re.IGNORECASE)  # /p/product-slug
_PRODUCT_SKU_RE = re.compile(r"[-/][a-z]{2,3}\d{4,}", re.IGNORECASE)  # SKU patterns like -AB12345


# Strong product hints - paths that almost always indicate product pages
PRODUCT_HINT_TOKENS = (
    "/produkt/",   # Must have trailing slash to require product slug
    "/product/",   # Must have trailing slash to require product slug
    "/item/",      # Must have trailing slash
    "/vara/",      # Swedish for "product"
    "/artikel/",   # Swedish for "article/product"
)

# Category hints - paths that indicate listing/category pages
CATEGORY_HINT_TOKENS = (
    "/category",
    "/kategori",
    "/collections",
    "/sortiment",
    "/products",   # /products (plural) is usually a listing
    "/produkter",  # Swedish plural = listing
    "/shop",
    "/mobler",     # Furniture category
    "/soffor",     # Sofas category (PLURAL = listing)
    "/soffa-",     # Sofas category prefix
    "/fatoljer",   # Armchairs category
    "/stolar",     # Chairs category
    "/bord",       # Tables category
    "/sangar",     # Beds category
    "/horn-",      # Corner (as in corner sofas category)
    "/divan",      # Divan category
    "/modul",      # Module category
    "-sits-soffor", # "X-seat sofas" is a category
    "-sitssoffor",  # "X-seat sofas" variant
    "/efter-farg", # "by color" filter page
)

# Non-product pages - utility/support pages
NON_PRODUCT_HINT_TOKENS = (
    "/kampanj",    # Campaign/sale pages
    "/support",
    "/villkor",
    "/konto",
    "/varukorg",   # Shopping cart
    "/kundservice",
    "/login",
    "/register",
    "/mina-sidor", # My pages
    "/favoriter",  # Favorites
    "/butiker",    # Stores
    "/om-",        # About pages
    "/handla-",    # Shopping info
    "/medlem",     # Membership
    "/nyhets",     # Newsletter
    "/hjalp",      # Help
    "/reklamation",
    "/inspiration",
    "/guide",
    "/press",
    "/outlet",
    "/tillbehor", # Accessories (category)
    "/service",
)


@dataclass(frozen=True)
class UrlClassification:
    confidence: float
    url_type_hint: str  # product|category|unknown


def classify_url(url: str) -> UrlClassification:
    """
    Heuristic classifier for likely product URLs.

    This is intentionally conservative; extraction will do the final decision.
    Returns higher confidence for URLs likely to be individual product pages,
    lower confidence for category/listing pages.
    """
    try:
        p = urlparse(url)
    except Exception:
        return UrlClassification(confidence=0.0, url_type_hint="unknown")

    path = (p.path or "").lower()
    full_url_lower = url.lower()
    
    # Start with neutral score
    score = 0.3

    # ===== STRONG CATEGORY SIGNALS (check first, these are definitive) =====
    
    # Category hint tokens - paths that indicate listing pages
    category_matches = sum(1 for tok in CATEGORY_HINT_TOKENS if tok in path)
    if category_matches > 0:
        score -= 0.35 * min(category_matches, 2)  # Cap at 2 matches
    
    # Non-product pages (utility pages)
    if any(tok in path for tok in NON_PRODUCT_HINT_TOKENS):
        score -= 0.5
    
    # Pagination is almost always a listing page
    if _PAGINATION_RE.search(full_url_lower):
        score -= 0.4
    
    # Path ends at a category level (no product slug after category)
    # e.g., /soffor or /soffor/ without further path segments
    path_segments = [s for s in path.split('/') if s]
    if len(path_segments) <= 2 and not _PRODUCT_PATH_RE.search(path):
        # Shallow paths without product markers are likely categories
        score -= 0.15
    
    # ===== STRONG PRODUCT SIGNALS =====
    
    # Product path patterns (/p/slug, /produkt/slug, etc.)
    if any(tok in path for tok in PRODUCT_HINT_TOKENS):
        score += 0.55
    
    # /p/ followed by product slug (very strong signal)
    if _PRODUCT_PATH_RE.search(path):
        score += 0.6
    
    # Common product-ID patterns (used by many retailers, incl. chilli.se)
    # e.g., -p12345, -p12345-v1
    if _PRODUCT_ID_RE.search(path):
        score += 0.65
    
    # SKU-like patterns in URL
    if _PRODUCT_SKU_RE.search(path):
        score += 0.25
    
    # Deep paths (4+ segments) with no category markers are more likely products
    if len(path_segments) >= 4 and category_matches == 0:
        score += 0.15
    
    # ===== DEFINITIVE EXCLUSIONS =====
    
    # Static files are never product pages
    if any(path.endswith(ext) for ext in (".pdf", ".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg", ".css", ".js")):
        return UrlClassification(confidence=0.0, url_type_hint="non_product")
    
    # Empty path or just "/" is never a product
    if not path or path == "/":
        return UrlClassification(confidence=0.0, url_type_hint="homepage")

    # Clamp and classify
    score = max(0.0, min(1.0, score))
    
    if score >= 0.65:
        hint = "product"
    elif score <= 0.25:
        hint = "category"
    else:
        hint = "unknown"
    
    return UrlClassification(confidence=score, url_type_hint=hint)

