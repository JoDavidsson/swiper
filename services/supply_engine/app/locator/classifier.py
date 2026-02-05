from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlparse


_PAGINATION_RE = re.compile(r"(\\?|&)(page|p)=\\d+", re.IGNORECASE)
_PRODUCT_ID_RE = re.compile(r"-p\\d+(?:-v\\d+)?\\b", re.IGNORECASE)  # common ecommerce pattern (e.g. chilli.se)


PRODUCT_HINT_TOKENS = (
    "/produkt",
    "/product",
    "/p/",
    "/item",
    "/soffa",
    "/soffor",
)

CATEGORY_HINT_TOKENS = (
    "/category",
    "/kategori",
    "/collections",
    "/sortiment",
    "/products",
    "/shop",
)

NON_PRODUCT_HINT_TOKENS = (
    "/kampanjer",
    "/support",
    "/villkor",
    "/konto",
    "/varukorg",
    "/kundservice",
    "/login",
    "/register",
)


@dataclass(frozen=True)
class UrlClassification:
    confidence: float
    url_type_hint: str  # product|category|unknown


def classify_url(url: str) -> UrlClassification:
    """
    Heuristic classifier for likely product URLs.

    This is intentionally conservative; extraction will do the final decision.
    """
    try:
        p = urlparse(url)
    except Exception:
        return UrlClassification(confidence=0.0, url_type_hint="unknown")

    path = (p.path or "").lower()
    score = 0.1

    # Strong product hints
    if any(tok in path for tok in PRODUCT_HINT_TOKENS):
        score += 0.65

    # Common product-ID patterns (used by many retailers, incl. chilli.se)
    if _PRODUCT_ID_RE.search(path):
        score += 0.75

    # Strong category hints
    if any(tok in path for tok in CATEGORY_HINT_TOKENS):
        score -= 0.25

    if any(tok in path for tok in NON_PRODUCT_HINT_TOKENS):
        score -= 0.4

    # Pagination pages are rarely product pages.
    if _PAGINATION_RE.search(url):
        score -= 0.15

    # Files are rarely product detail pages.
    if any(path.endswith(ext) for ext in (".pdf", ".jpg", ".jpeg", ".png", ".webp", ".gif")):
        score = 0.0

    score = max(0.0, min(1.0, score))
    if score >= 0.7:
        hint = "product"
    elif score <= 0.2:
        hint = "category"
    else:
        hint = "unknown"
    return UrlClassification(confidence=score, url_type_hint=hint)

