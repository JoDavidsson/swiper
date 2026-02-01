"""Normalize raw values to TAG_TAXONOMY (material, colorFamily, sizeClass, styleTags, ecoTags)."""
from typing import Any

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
    from urllib.parse import urlparse, urlunparse, parse_qs, urlencode

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
