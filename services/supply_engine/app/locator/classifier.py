from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlparse


_PAGINATION_RE = re.compile(r"(\?|&)(page|p)=\d+", re.IGNORECASE)
_PAGINATION_PATH_RE = re.compile(r"/\d{1,4}-\d{1,4}/sida\.html?$", re.IGNORECASE)
_PRODUCT_ID_RE = re.compile(r"-p\d+(?:-v\d+)?\b", re.IGNORECASE)  # common ecommerce pattern (e.g. chilli.se)
_SHOPIFY_PRODUCT_RE = re.compile(r"/products/[^/?#]+/?$", re.IGNORECASE)
_SWEDISH_PRODUCTS_RE = re.compile(r"/produkter/[^/?#]+/?$", re.IGNORECASE)

# /products/{handle} is a Shopify PDP pattern, but some sites use
# /products/{category} for listings. Keep an explicit category handle denylist.
_NON_PRODUCT_PRODUCTS_HANDLES = {
    "sofas",
    "soffor",
    "armchairs",
    "chairs",
    "dining-chairs",
    "beds",
    "beds-and-bed-frames",
    "footstools",
    "accessories",
    "furniture",
    "tables",
}

_NON_PRODUCT_PRODUKTER_HANDLES = {
    "soffor",
    "fatoljer",
    "fåtöljer",
    "mobler",
    "möbler",
    "utemobler",
    "utemöbler",
    "sangar",
    "sängar",
    "bord",
    "stolar",
    "inredning",
}

# Strong product path patterns - these indicate a specific product page
# NOTE: /p/ must be followed by content (not just /p or /p/)
_PRODUCT_PATH_RE = re.compile(r"/p/[a-z0-9]", re.IGNORECASE)  # /p/product-slug
_PRODUCT_BUNDLE_RE = re.compile(r"/p-[a-z]\d{4,}", re.IGNORECASE)  # ILVA bundle pattern: /p-b0003274-5637177585/
_PRODUCT_SKU_RE = re.compile(r"[-/][a-z]{2,3}\d{4,}", re.IGNORECASE)  # SKU patterns like -AB12345

# Pattern: path ends with /article-number (7+ digit ID, common in Nordic retailers)
# e.g., /kelso-soffa-2-sits-manchester/1737345-02 (Jotex)
_ARTICLE_NUMBER_RE = re.compile(r"/\d{6,}(-\d+)?/?$", re.IGNORECASE)
_HTML_PRODUCT_LEAF_RE = re.compile(r"/[^/]+\.html?$", re.IGNORECASE)
_SEAT_COUNT_CATEGORY_RE = re.compile(r"^\d{1,2}-?sits-?soffa(?:r)?$", re.IGNORECASE)
_SINGULAR_PRODUCT_TERM_RE = re.compile(
    r"(?:^|[-_])(soffa|hornsoffa|divansoffa|modulsoffa|baddsoffa|bddsoffa|f(at|å)t(o|ö)lj|fotpall|dagbadd|daybed)(?:[-_]|$)",
    re.IGNORECASE,
)
_PLURAL_CATEGORY_TERM_RE = re.compile(
    r"(?:^|[-_])(soffor|fatoljer|f(a|å)t(o|ö)ljer|stolar|bord|sangar|s(a|ä)ngar|mobler|m(o|ö)bler|inredning|utemobler|utem(o|ö)bler|dagbaddar)(?:[-_]|$)",
    re.IGNORECASE,
)
_GENERIC_CATEGORY_SLUGS = {
    "soffor",
    "soffa",
    "hornsoffa",
    "hornsoffor",
    "divansoffa",
    "divansoffor",
    "modulsoffa",
    "modulsoffor",
    "baddsoffa",
    "baddsoffor",
    "bddsoffa",
    "dagbaddar",
    "fatoljer",
    "fåtöljer",
    "alla-fatoljer",
    "extra-kladsel",
    "tillbehor-till-soffor",
}


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
    "/brand/",
    "/assets/",
    "/blogs/",
    "/blog/",
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
    query = (p.query or "").lower()
    full_url_lower = url.lower()
    
    # Start with neutral score
    score = 0.3

    # ===== PRODUCT SIGNALS (evaluate first to detect strong signals) =====
    
    path_segments = [s for s in path.split('/') if s]
    last_segment = path_segments[-1] if path_segments else ""
    hyphen_count = last_segment.count("-") if last_segment else 0
    last_is_generic_category = (
        last_segment in _GENERIC_CATEGORY_SLUGS
        or bool(_SEAT_COUNT_CATEGORY_RE.search(last_segment))
        or bool(_PLURAL_CATEGORY_TERM_RE.search(last_segment))
    )
    product_signal_strength = 0.0
    
    # Product path patterns (/p/slug, /produkt/slug, etc.)
    if any(tok in path for tok in PRODUCT_HINT_TOKENS):
        product_signal_strength += 0.55
    
    # /p/ followed by product slug (very strong signal)
    if _PRODUCT_PATH_RE.search(path):
        product_signal_strength += 0.6

    # Shopify PDP canonical pattern: /products/{handle}
    shopify_match = _SHOPIFY_PRODUCT_RE.search(path)
    if shopify_match:
        handle = path.rstrip("/").split("/")[-1]
        if handle in _NON_PRODUCT_PRODUCTS_HANDLES:
            # Explicitly known listing handle under /products/.
            score -= 0.25
        else:
            product_signal_strength += 0.6

    swedish_products_match = _SWEDISH_PRODUCTS_RE.search(path)
    if swedish_products_match:
        handle = path.rstrip("/").split("/")[-1]
        if handle in _NON_PRODUCT_PRODUKTER_HANDLES:
            score -= 0.25
        else:
            product_signal_strength += 0.6

    # /p-b followed by product ID (ILVA bundle pattern: /p-bXXXXXX-XXXXXXXXXX/)
    if _PRODUCT_BUNDLE_RE.search(path):
        product_signal_strength += 0.6
    
    # Common product-ID patterns (used by many retailers, incl. chilli.se)
    # e.g., -p12345, -p12345-v1
    if _PRODUCT_ID_RE.search(path):
        product_signal_strength += 0.65
    
    # Article number at end of path (Nordic retailers like Jotex)
    # e.g., /kelso-soffa-2-sits-manchester/1737345-02
    # This is a very strong signal — a 7-digit article number is almost always a product.
    if _ARTICLE_NUMBER_RE.search(path):
        product_signal_strength += 0.55
    
    # SKU-like patterns in URL
    if _PRODUCT_SKU_RE.search(path):
        product_signal_strength += 0.25

    # Many Nordic retailers use category-prefix + slug for PDPs, e.g.
    # /soffor/rest-soffa-3-sits or /varumarken/muuto/rest-soffa-3-sits.
    if last_segment and not last_is_generic_category:
        if _SINGULAR_PRODUCT_TERM_RE.search(last_segment) and (hyphen_count >= 1 or len(last_segment) >= 10):
            product_signal_strength += 0.45
        if hyphen_count >= 2 and len(last_segment) >= 12:
            product_signal_strength += 0.35
    
    # Deep paths (4+ segments) are more likely products
    if len(path_segments) >= 4:
        product_signal_strength += 0.15
    elif len(path_segments) >= 3 and last_segment and not last_is_generic_category:
        product_signal_strength += 0.1

    # Many catalog/ecommerce sites use deep .html leaf pages for products,
    # while category hubs are usually */index.html.
    if _HTML_PRODUCT_LEAF_RE.search(path) and not path.endswith("/index.html") and len(path_segments) >= 4:
        product_signal_strength += 0.45
    
    has_strong_product_signal = product_signal_strength >= 0.4
    score += product_signal_strength
    
    # ===== CATEGORY SIGNALS =====
    # When a strong product signal is present (e.g., /p-bXXXX or /1737345-02),
    # category tokens in the path are likely breadcrumb segments, not indicators
    # of a category page. Reduce their penalty.
    
    # Category hint tokens - paths that indicate listing pages
    category_matches = sum(1 for tok in CATEGORY_HINT_TOKENS if tok in path)
    # /products/{handle} should not be penalised as "category" because of "/products".
    if (shopify_match and "/products" in path and category_matches > 0) or (
        swedish_products_match and "/produkter" in path and category_matches > 0
    ):
        category_matches -= 1
    if category_matches > 0:
        # If a strong product signal is present, category tokens in the path are
        # likely breadcrumbs (e.g., /soffor/product-name/p-bXXXX/) — reduce penalty.
        penalty_per_match = 0.15 if has_strong_product_signal else 0.35
        score -= penalty_per_match * min(category_matches, 2)

    # Category-like leaf slugs should be downranked even on deep paths.
    if last_segment:
        if _SEAT_COUNT_CATEGORY_RE.search(last_segment):
            score -= 0.45
        elif last_is_generic_category:
            score -= 0.25
    
    # Non-product pages (utility pages)
    if any(tok in path for tok in NON_PRODUCT_HINT_TOKENS):
        score -= 0.5

    # Common listing/filter query params.
    if any(k in query for k in ("page=", "sort=", "filter", "q=", "search=", "brand=", "campaign")):
        score -= 0.35
    # Product variant query params are common on PDPs (especially Shopify).
    if "variant=" in query and shopify_match:
        score += 0.15

    # Pagination is almost always a listing page
    if _PAGINATION_RE.search(full_url_lower):
        score -= 0.4
    if _PAGINATION_PATH_RE.search(path) or "/sida.html" in path:
        score -= 0.6
    
    # Path ends at a category level (no product slug after category)
    # e.g., /soffor or /soffor/ without further path segments
    if len(path_segments) <= 2 and not has_strong_product_signal:
        # Shallow paths without product markers are likely categories
        score -= 0.15
    if path.endswith("/index.html"):
        score -= 0.35
    
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
