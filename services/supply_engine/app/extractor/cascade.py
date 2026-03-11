from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse, urljoin, unquote

from app.extractor.money import parse_money_sv
from app.extractor.signals import extract_page_signals, PageSignals
from app.extractor.enrichment import enrich_product, EnrichedMetadata
from app.extractor.embedded_state import extract_products_from_state
from app.normalization import clean_title_text


# ============================================================================
# IMAGE URL VALIDATION
# ============================================================================

# File extensions that indicate an image URL
_IMAGE_EXTENSIONS = frozenset({
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif", ".svg",
    ".bmp", ".tiff", ".tif", ".ico",
})

# Path segments that suggest the URL serves images (even without an extension)
_IMAGE_PATH_HINTS = (
    "/images/", "/image/", "/img/", "/media/",
    "/bilder/", "/foto/", "/photos/", "/pics/",
    "/product-images/", "/product_images/",
    "/thumbnails/", "/thumb/",
    "/cdn-cgi/image/",  # Cloudflare image resizing
    "/pimg/",  # IKEA image pattern
)

# Domain prefixes/patterns that indicate a dedicated image/media CDN
_IMAGE_CDN_DOMAINS = (
    "cdn.", "media.", "img.", "images.", "assets.", "static.",
    "mcdn.", "imgix.", "cloudinary.",
)

# Patterns found anywhere in the domain (e.g., "shop.cdn-norce.tech")
_IMAGE_CDN_DOMAIN_CONTAINS = (
    ".cdn-", ".cdn.",  # e.g., sleepo.cdn-norce.tech
    "cloudinary.com",
    "imgix.net",
    "shopify.com/cdn",
)

# URL path patterns that strongly indicate a product PAGE, not an image
_PAGE_URL_PATTERNS = (
    "/produkt/", "/produkter/", "/product/", "/products/",
    "/varumarken/", "/varumärken/",
    "/kategori/", "/category/",
    "/shop/", "/butik/",
    # URL-encoded Swedish characters in category paths (e.g., möbler = m%c3%b6bler)
    "m%c3%b6bler",  # möbler
    "b%c3%a4ddsoffor",  # bäddsoffor
    "l%c3%a4ngsb%c3%a4ddad",  # längsbäddad
)


def _is_likely_image_url(url: str) -> bool:
    """
    Heuristic check: is this URL likely an actual image, not a product page?

    Strategy:
    1. URLs with image file extensions -> YES
    2. URLs on known image CDN domains -> YES
    3. URLs with image-related path segments -> YES
    4. URLs matching product page patterns -> NO
    5. URLs without any image signals -> NO
    """
    if not url or len(url) < 10:
        return False

    try:
        parsed = urlparse(url)
    except Exception:
        return False

    path_lower = parsed.path.lower()
    netloc_lower = parsed.netloc.lower()
    url_lower = url.lower()

    # 1. Check for image file extension (most reliable signal)
    # Strip query params and fragments from the path for extension check
    path_clean = path_lower.split("?")[0].split("#")[0]
    for ext in _IMAGE_EXTENSIONS:
        if path_clean.endswith(ext):
            return True

    # 2. Check for image CDN domain
    for cdn in _IMAGE_CDN_DOMAINS:
        if netloc_lower.startswith(cdn) or f".{cdn}" in netloc_lower:
            return True
    for pattern in _IMAGE_CDN_DOMAIN_CONTAINS:
        if pattern in netloc_lower or pattern in url_lower:
            return True

    # 3. Check for image-related path segments
    # Treat /assets/ conservatively: extensionless asset URLs are often logos/files.
    for hint in _IMAGE_PATH_HINTS:
        if hint in path_lower:
            return True

    # 3b. Check for image CDN query parameters (e.g., ?w=800&h=600, ?format=jpg)
    query_lower = parsed.query.lower() if parsed.query else ""
    if query_lower:
        image_query_hints = ("w=", "h=", "width=", "height=", "format=", "quality=", "scale=", "fit=", "crop=")
        if any(hint in query_lower for hint in image_query_hints):
            return True

    # 4. Reject URLs that look like product/category pages
    decoded_url = unquote(url_lower)
    for pattern in _PAGE_URL_PATTERNS:
        decoded_pattern = unquote(pattern)
        if pattern in url_lower or decoded_pattern in decoded_url:
            return False

    # 5. No strong signal either way - reject by default
    # (better to find images via fallback than to store page URLs)
    return False


def _looks_truncated(url: str) -> bool:
    """
    Detect URLs that appear truncated / incomplete.

    Truncated URLs often:
    - End mid-path without a file extension
    - Have very short final path segments (like a hash cut off)
    - End with a hyphen or partial word
    """
    if not url:
        return True

    try:
        parsed = urlparse(url)
    except Exception:
        return True

    path = parsed.path.rstrip("/")
    if not path:
        return False

    # Get the last path segment
    last_segment = path.split("/")[-1] if "/" in path else path

    # If the URL has a query string or fragment, it's probably complete
    if parsed.query or parsed.fragment:
        return False

    # If it has a file extension, it's probably complete
    for ext in _IMAGE_EXTENSIONS:
        if last_segment.lower().endswith(ext):
            return False

    # Suspiciously short final segment (likely truncated hash or ID)
    if len(last_segment) < 5 and not last_segment.isdigit():
        return True

    # Ends with a hyphen (mid-word truncation)
    if last_segment.endswith("-") or last_segment.endswith("_"):
        return True

    return False


@dataclass(frozen=True)
class NormalizedProduct:
    retailer_id: str
    retailer_domain: str
    product_url: str
    canonical_url: str
    title: str
    price_amount: float | None
    price_currency: str | None
    price_raw: str | None
    images: list[str]
    description: str | None
    brand: str | None
    extracted_at: str
    method: str  # jsonld|embedded_json|dom|recipe
    recipe_id: str | None
    recipe_version: int | None
    completeness_score: float
    warnings: list[str]
    debug: dict
    # P1: Recommendation backbone (material, color, dimensions for ranker)
    dimensions_raw: dict | None = None  # {"w": float, "h": float, "d": float} in cm
    material_raw: str | None = None
    color_raw: str | None = None
    # EPIC B: Enriched metadata
    breadcrumbs: list[str] | None = None
    product_type: str | None = None
    retailer_category_label: str | None = None
    facets: dict | None = None
    variants: list[dict] | None = None
    sku: str | None = None
    mpn: str | None = None
    gtin: str | None = None
    model_name: str | None = None
    price_original: float | None = None
    discount_pct: float | None = None
    availability: str | None = None
    delivery_eta: str | None = None
    shipping_cost: float | None = None
    enrichment_evidence: list[str] | None = None
    # Rich furniture specs (extracted from spec tables / facets)
    seat_height_cm: float | None = None
    seat_depth_cm: float | None = None
    seat_width_cm: float | None = None
    seat_count: int | None = None
    weight_kg: float | None = None
    frame_material: str | None = None
    cover_material: str | None = None
    leg_material: str | None = None
    cushion_filling: str | None = None


def _domain(url: str) -> str:
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return ""


def _parse_quantitative_value(val: Any) -> float | None:
    """Parse Schema.org QuantitativeValue or plain number to cm."""
    if val is None:
        return None
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, dict):
        v = val.get("value")
        if v is None:
            return None
        try:
            num = float(v)
        except (TypeError, ValueError):
            return None
        unit = (val.get("unitCode") or val.get("unitText") or "").upper()
        # CMT = centimetre, MCM = square centimetre (use as cm), MTR = metre
        if unit in ("MTR", "M"):
            return num * 100
        return num
    if isinstance(val, str):
        s = re.sub(r"[^\d.,]", "", val).replace(",", ".")
        if not s:
            return None
        try:
            return float(s)
        except ValueError:
            return None
    return None


def _parse_dimensions_from_product(product: dict) -> dict | None:
    """Extract {w, h, d} from JSON-LD Product. Returns None if none found."""
    w = _parse_quantitative_value(product.get("width"))
    h = _parse_quantitative_value(product.get("height"))
    d = _parse_quantitative_value(product.get("depth"))
    # additionalProperty: Bredd/Höjd/Djup, width/height/depth
    add_props = product.get("additionalProperty") or []
    if isinstance(add_props, dict):
        add_props = [add_props]
    if not isinstance(add_props, list):
        add_props = []
    for prop in add_props:
        if not isinstance(prop, dict):
            continue
        name = (prop.get("name") or prop.get("propertyID") or "").lower().strip()
        val = _parse_quantitative_value(prop.get("value"))
        if val is None:
            continue
        if name in ("bredd", "width", "bredd (cm)"):
            w = w if w is not None else val
        elif name in ("höjd", "height", "höjd (cm)"):
            h = h if h is not None else val
        elif name in ("djup", "depth", "djup (cm)"):
            d = d if d is not None else val
    if w is None and h is None and d is None:
        return None
    return {"w": w or 0, "h": h or 0, "d": d or 0}


def _clean_text(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def _normalize_label(value: str | None) -> str:
    s = _clean_text(value).lower()
    s = (
        s.replace("å", "a")
        .replace("ä", "a")
        .replace("ö", "o")
        .replace("é", "e")
        .replace("è", "e")
    )
    return re.sub(r"[^a-z0-9]+", "", s)


def _parse_dimension_value_to_cm(value: Any) -> float | None:
    if value is None:
        return None
    text = _clean_text(str(value)).lower().replace(",", ".")
    if not text:
        return None

    # Capture the first number and optional unit.
    m = re.search(r"(-?\d+(?:\.\d+)?)\s*(mm|cm|m)?\b", text)
    if not m:
        return None
    try:
        num = float(m.group(1))
    except (TypeError, ValueError):
        return None
    unit = m.group(2) or "cm"
    if unit == "mm":
        return num / 10.0
    if unit == "m":
        return num * 100.0
    return num


def _parse_dimension_triplet_to_cm(value: Any) -> dict | None:
    if value is None:
        return None
    text = _clean_text(str(value)).lower().replace(",", ".")
    if not text:
        return None
    m = re.search(
        r"(-?\d+(?:\.\d+)?)\s*[x×]\s*(-?\d+(?:\.\d+)?)\s*[x×]\s*(-?\d+(?:\.\d+)?)\s*(mm|cm|m)?",
        text,
    )
    if not m:
        return None
    try:
        w = float(m.group(1))
        h = float(m.group(2))
        d = float(m.group(3))
    except (TypeError, ValueError):
        return None
    unit = m.group(4) or "cm"
    if unit == "mm":
        return {"w": w / 10.0, "h": h / 10.0, "d": d / 10.0}
    if unit == "m":
        return {"w": w * 100.0, "h": h * 100.0, "d": d * 100.0}
    return {"w": w, "h": h, "d": d}


def _iter_spec_pairs_from_dom(soup: Any) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()

    container_selectors = [
        ".specifications",
        ".product-specs",
        ".spec-table",
        "[data-specs]",
        ".product-specifications",
        ".product-details",
        ".product-info",
    ]
    containers = []
    for sel in container_selectors:
        containers.extend(soup.select(sel))
    if not containers:
        containers = [soup]

    def _add_pair(k: Any, v: Any) -> None:
        key = _clean_text(k if isinstance(k, str) else getattr(k, "get_text", lambda **_: "")(strip=True))
        val = _clean_text(v if isinstance(v, str) else getattr(v, "get_text", lambda **_: "")(strip=True))
        if not key or not val:
            return
        tup = (key, val)
        if tup in seen:
            return
        seen.add(tup)
        pairs.append(tup)

    for container in containers:
        for dl in container.find_all("dl"):
            dts = dl.find_all("dt")
            dds = dl.find_all("dd")
            for dt, dd in zip(dts, dds):
                _add_pair(dt, dd)

        for table in container.find_all("table"):
            for row in table.find_all("tr"):
                cells = row.find_all(["th", "td"])
                if len(cells) >= 2:
                    _add_pair(cells[0], cells[1])

        for li in container.find_all("li"):
            text = _clean_text(li.get_text(" ", strip=True))
            if ":" in text:
                key, val = text.split(":", 1)
                _add_pair(key, val)

    return pairs


def _extract_description_from_dom(soup: Any) -> str | None:
    # 1) Most reliable: explicit OG + meta descriptions.
    og_desc = soup.find("meta", attrs={"property": "og:description"})
    if og_desc and og_desc.get("content"):
        v = _clean_text(og_desc.get("content"))
        if v:
            return v

    meta_desc = soup.find("meta", attrs={"name": re.compile(r"^description$", re.IGNORECASE)})
    if meta_desc and meta_desc.get("content"):
        v = _clean_text(meta_desc.get("content"))
        if v:
            return v

    # 2) Product description containers.
    selectors = [
        ".product-description",
        ".product-info__description",
        "[data-product-description]",
        "#product-description",
        ".description",
        ".produktbeskrivning",
        "[itemprop='description']",
    ]
    for sel in selectors:
        el = soup.select_one(sel)
        if not el:
            continue
        v = _clean_text(el.get_text(" ", strip=True))
        if v:
            return v

    # 3) First substantial paragraph in likely product content.
    for container_sel in (".product-detail", ".product-content", "main"):
        container = soup.select_one(container_sel)
        if not container:
            continue
        for p in container.find_all("p"):
            txt = _clean_text(p.get_text(" ", strip=True))
            if len(txt) >= 40:
                return txt

    return None


def _extract_price_raw_from_dom(soup: Any) -> str | None:
    """Extract first plausible price string from common DOM price selectors."""
    selectors = [
        "[itemprop='price']",
        "[data-price]",
        "[data-price-amount]",
        "[data-testid*='price']",
        "[id*='price']",
        "[class*='price']",
        "[class*='pricing']",
        ".price",
        ".product-price",
        ".current-price",
        ".sales-price",
        ".price__value",
    ]
    # Prefer explicit currency-bearing prices first to avoid grabbing
    # unrelated numeric fragments (dimensions, review counts, etc.).
    currency_price_re = re.compile(r"\d[\d\s.,:-]{0,24}\s*(?:kr|sek|eur|usd)\b", re.IGNORECASE)
    fallback_price_re = re.compile(r"\d[\d\s.,:-]{0,24}", re.IGNORECASE)
    for sel in selectors:
        for el in soup.select(sel):
            candidates: list[str] = []
            for attr in ("content", "data-price", "data-price-amount", "value"):
                val = el.get(attr)
                if isinstance(val, str) and val.strip():
                    candidates.append(val.strip())
            txt = _clean_text(el.get_text(" ", strip=True))
            if txt:
                candidates.append(txt)
            for c in candidates:
                m = currency_price_re.search(c) or fallback_price_re.search(c)
                if m:
                    raw = m.group(0).strip()
                    if re.search(r"\d", raw):
                        return raw
    return None


def _extract_dimensions_from_facets(facets: dict | None) -> dict | None:
    if not isinstance(facets, dict) or not facets:
        return None
    w = h = d = None
    for raw_key, raw_val in facets.items():
        key = _normalize_label(str(raw_key))
        val = _clean_text(str(raw_val))
        if not val:
            continue

        triplet = _parse_dimension_triplet_to_cm(val)
        if triplet and key in ("dimensioner", "dimensions", "matt"):
            return triplet

        parsed = _parse_dimension_value_to_cm(val)
        if parsed is None:
            continue
        if key in ("bredd", "width", "totalbredd", "sittbredd"):
            w = w if w is not None else parsed
        elif key in ("hojd", "height", "sitthojd", "totalhojd"):
            h = h if h is not None else parsed
        elif key in ("djup", "depth", "sittdjup", "totaldjup"):
            d = d if d is not None else parsed

    if w is None and h is None and d is None:
        return None
    return {"w": w or 0, "h": h or 0, "d": d or 0}


def _extract_dimensions_from_dom(soup: Any) -> dict | None:
    w = h = d = None
    for raw_key, raw_val in _iter_spec_pairs_from_dom(soup):
        key = _normalize_label(raw_key)
        val = _clean_text(raw_val)
        if not key or not val:
            continue

        # Common compact dimensions format: "220 x 88 x 95 cm"
        triplet = _parse_dimension_triplet_to_cm(val)
        if triplet and key in ("dimensioner", "dimensions", "matt", "storlek", "size"):
            return triplet

        parsed = _parse_dimension_value_to_cm(val)
        if parsed is None:
            continue
        if key in ("bredd", "width", "totalbredd", "sittbredd"):
            w = w if w is not None else parsed
        elif key in ("hojd", "height", "sitthojd", "totalhojd"):
            h = h if h is not None else parsed
        elif key in ("djup", "depth", "sittdjup", "totaldjup"):
            d = d if d is not None else parsed

    if w is None and h is None and d is None:
        return None
    return {"w": w or 0, "h": h or 0, "d": d or 0}


def _extract_material_from_dom(soup: Any) -> str | None:
    from app.normalization import normalize_material

    material_labels = {
        "material",
        "tyg",
        "kladsel",
        "kladselmaterial",
        "cover",
        "upholstery",
        "frame",
    }
    for raw_key, raw_val in _iter_spec_pairs_from_dom(soup):
        key = _normalize_label(raw_key)
        if key not in material_labels:
            continue
        raw = _clean_text(raw_val)
        if not raw:
            continue
        return normalize_material(raw) or raw

    # Microdata fallback
    el = soup.find(attrs={"itemprop": "material"})
    if el:
        raw = _clean_text(el.get("content") or el.get_text(" ", strip=True))
        if raw:
            return normalize_material(raw) or raw
    return None


def _extract_rich_specs_from_dom(soup: Any) -> dict:
    """Extract rich furniture specifications from DOM spec tables.

    Returns a dict with keys: seat_height_cm, seat_depth_cm, seat_width_cm,
    seat_count, weight_kg, frame_material, cover_material, leg_material,
    cushion_filling.  Values are None if not found.
    """
    specs: dict = {
        "seat_height_cm": None,
        "seat_depth_cm": None,
        "seat_width_cm": None,
        "seat_count": None,
        "weight_kg": None,
        "frame_material": None,
        "cover_material": None,
        "leg_material": None,
        "cushion_filling": None,
    }

    _dim_labels = {
        "sitthojd": "seat_height_cm",
        "seat_height": "seat_height_cm",
        "sittdjup": "seat_depth_cm",
        "seat_depth": "seat_depth_cm",
        "sittbredd": "seat_width_cm",
        "seat_width": "seat_width_cm",
    }
    _count_labels = {"antal_sitsar", "antal_sittplatser", "seats", "number_of_seats", "sitsar"}
    _weight_labels = {"vikt", "weight", "totalvikt"}
    _frame_labels = {"stomme", "frame", "stommaterial", "frame_material"}
    _cover_labels = {"kladsel", "kladselmaterial", "cover", "upholstery", "tygkladsel", "tyg"}
    _leg_labels = {"ben", "legs", "fotter", "feet", "benmaterial", "leg_material"}
    _filling_labels = {"kuddfyllning", "fyllning", "filling", "cushion", "sittfyllning"}

    for raw_key, raw_val in _iter_spec_pairs_from_dom(soup):
        key = _normalize_label(raw_key)
        val = _clean_text(raw_val)
        if not key or not val:
            continue

        # Dimensional specs (cm)
        if key in _dim_labels:
            parsed = _parse_dimension_value_to_cm(val)
            if parsed is not None and specs[_dim_labels[key]] is None:
                specs[_dim_labels[key]] = parsed

        # Seat count
        elif key in _count_labels:
            try:
                count = int(re.search(r"\d+", val).group())  # type: ignore[union-attr]
                if 1 <= count <= 20 and specs["seat_count"] is None:
                    specs["seat_count"] = count
            except (AttributeError, ValueError):
                pass

        # Weight
        elif key in _weight_labels:
            try:
                w = float(re.search(r"[\d.]+", val).group())  # type: ignore[union-attr]
                if 0 < w < 500 and specs["weight_kg"] is None:
                    specs["weight_kg"] = round(w, 1)
            except (AttributeError, ValueError):
                pass

        # Material specs (strings)
        elif key in _frame_labels and specs["frame_material"] is None:
            specs["frame_material"] = val[:100]
        elif key in _cover_labels and specs["cover_material"] is None:
            specs["cover_material"] = val[:100]
        elif key in _leg_labels and specs["leg_material"] is None:
            specs["leg_material"] = val[:100]
        elif key in _filling_labels and specs["cushion_filling"] is None:
            specs["cushion_filling"] = val[:100]

    return specs


def _extract_brand_from_dom(soup: Any) -> str | None:
    for prop in ("product:brand", "og:brand"):
        meta = soup.find("meta", attrs={"property": prop})
        if meta and meta.get("content"):
            value = _clean_text(meta.get("content"))
            if value:
                return value

    itemprop_brand = soup.find(attrs={"itemprop": "brand"})
    if itemprop_brand:
        value = _clean_text(itemprop_brand.get("content") or itemprop_brand.get_text(" ", strip=True))
        if value:
            return value

    for sel in (".product-brand", ".brand-name", "[data-brand]"):
        el = soup.select_one(sel)
        if not el:
            continue
        value = _clean_text(el.get_text(" ", strip=True))
        if value:
            return value

    return None


def _pick_jsonld_product(blocks: list[Any]) -> dict | None:
    """
    Find the best JSON-LD Product object from parsed blocks.
    Handles arrays and @graph.
    """

    def iter_objs(x: Any):
        if isinstance(x, dict):
            yield x
            g = x.get("@graph")
            if isinstance(g, list):
                for el in g:
                    yield from iter_objs(el)
        elif isinstance(x, list):
            for el in x:
                yield from iter_objs(el)

    best: dict | None = None
    for obj in iter_objs(blocks):
        if not isinstance(obj, dict):
            continue
        t = obj.get("@type")
        types: list[str] = []
        if isinstance(t, str):
            types = [t]
        elif isinstance(t, list):
            types = [str(x) for x in t]
        types_l = [x.lower() for x in types]
        if "product" not in types_l:
            continue
        best = obj
        # Prefer one that has offers and name
        if obj.get("offers") and obj.get("name"):
            return obj
    return best


def _extract_images_from_dom(html: str, *, base_url: str) -> list[str]:
    """
    Extract product images directly from the HTML DOM as a fallback.

    Searches for <img> tags in product-related containers, <picture> sources,
    and common product image CSS class patterns.
    """
    try:
        from bs4 import BeautifulSoup
    except ImportError:
        return []

    soup = BeautifulSoup(html, "lxml")
    candidates: list[str] = []
    seen: set[str] = set()

    def _add(url: str | None) -> None:
        if not url or not url.strip():
            return
        abs_url = _absolute(url.strip(), base_url)
        if abs_url and abs_url not in seen:
            seen.add(abs_url)
            candidates.append(abs_url)

    # 1. Product gallery containers (most reliable)
    gallery_selectors = [
        ".product-gallery img",
        ".product-images img",
        ".product-image img",
        "#product-image img",
        "#product-images img",
        ".pdp-image img",
        ".product-media img",
        "[data-gallery] img",
        ".gallery img",
        ".swiper-slide img",  # common carousel widget
        ".slick-slide img",   # another carousel
        ".splide__slide img", # Splide carousel
    ]
    for selector in gallery_selectors:
        for img_tag in soup.select(selector):
            # Prefer data-src (lazy-loaded) over src (often a placeholder)
            for attr in ("data-src", "data-original", "data-image", "data-lazy", "src"):
                val = img_tag.get(attr)
                if val and val.strip() and not val.startswith("data:"):
                    _add(val)
                    break

    # 2. <picture> elements with <source srcset>
    for picture in soup.find_all("picture"):
        for source in picture.find_all("source"):
            srcset = source.get("srcset")
            if srcset:
                # srcset can have multiple URLs with descriptors, take the first/largest
                first_url = srcset.split(",")[0].strip().split(" ")[0]
                _add(first_url)
        # Also check the fallback <img> inside <picture>
        fallback_img = picture.find("img")
        if fallback_img:
            _add(fallback_img.get("src"))

    # 3. Any <img> with product-related CSS classes (not in banner/nav/footer)
    product_img_classes = re.compile(
        r"product|pdp|gallery|main-image|primary-image",
        re.IGNORECASE,
    )
    # Containers that likely hold NON-product images (banners, navigation, etc.)
    _non_product_tags = {"header", "nav", "footer", "aside"}
    _non_product_classes = re.compile(
        r"banner|hero-banner|site-header|nav-bar|footer|newsletter|promo-strip|campaign-banner|cookie",
        re.IGNORECASE,
    )

    def _is_inside_non_product_container(tag: Any) -> bool:
        """Check if an image tag is inside a banner/nav/footer/aside container."""
        for parent in tag.parents:
            if parent.name in _non_product_tags:
                return True
            parent_classes = " ".join(parent.get("class", []))
            if _non_product_classes.search(parent_classes):
                return True
        return False

    for img_tag in soup.find_all("img"):
        if _is_inside_non_product_container(img_tag):
            continue
        classes = " ".join(img_tag.get("class", []))
        img_id = img_tag.get("id", "")
        if product_img_classes.search(classes) or product_img_classes.search(img_id):
            for attr in ("data-src", "data-original", "src"):
                val = img_tag.get(attr)
                if val and val.strip() and not val.startswith("data:"):
                    _add(val)
                    break

    # 4. Large images by dimension hints (width/height attributes > 300)
    #    Skip images inside non-product containers.
    if not candidates:
        for img_tag in soup.find_all("img"):
            if _is_inside_non_product_container(img_tag):
                continue
            w = img_tag.get("width", "")
            h = img_tag.get("height", "")
            try:
                w_val = int(str(w).replace("px", "")) if w else 0
                h_val = int(str(h).replace("px", "")) if h else 0
            except (ValueError, TypeError):
                w_val, h_val = 0, 0
            # Penalise banner-like aspect ratios (very wide images)
            if w_val > 0 and h_val > 0 and w_val / h_val > 3.0:
                continue
            if w_val >= 300 or h_val >= 300:
                for attr in ("data-src", "src"):
                    val = img_tag.get(attr)
                    if val and val.strip() and not val.startswith("data:"):
                        _add(val)
                        break

    # Filter through validation
    validated = [u for u in candidates if _is_likely_image_url(u) and not _looks_truncated(u)]
    return validated if validated else candidates[:5]


def _extract_from_jsonld(product: dict) -> dict:
    title = clean_title_text(product.get("name")) or ""
    canonical = (product.get("url") or product.get("id") or "").strip()
    img = product.get("image")
    images: list[str] = []
    if isinstance(img, str) and img.strip():
        images = [img.strip()]
    elif isinstance(img, list):
        for el in img:
            if isinstance(el, str) and el.strip():
                images.append(el.strip())
            elif isinstance(el, dict):
                # Prefer contentUrl (Schema.org ImageObject), fall back to url
                u = el.get("contentUrl") or el.get("url")
                if u and isinstance(u, str):
                    images.append(u.strip())

    brand = None
    b = product.get("brand")
    if isinstance(b, dict):
        brand = (b.get("name") or "").strip() or None
    elif isinstance(b, str):
        brand = b.strip() or None

    desc_raw = product.get("description")
    if isinstance(desc_raw, list):
        # Some sites (e.g. Jotex) provide description as an array of paragraphs
        desc = " ".join(str(p).strip() for p in desc_raw if p).strip() or None
    else:
        desc = (desc_raw or "").strip() or None

    price_raw = None
    currency = None
    offers = product.get("offers")
    if isinstance(offers, dict):
        currency = (offers.get("priceCurrency") or "").strip() or None
        price_raw = offers.get("price") or None
        if price_raw is None:
            ps = offers.get("priceSpecification")
            if isinstance(ps, dict):
                price_raw = ps.get("price")
                currency = currency or (ps.get("priceCurrency") or "").strip() or None
            elif isinstance(ps, list):
                for spec in ps:
                    if not isinstance(spec, dict):
                        continue
                    if price_raw is None:
                        price_raw = spec.get("price")
                    if not currency:
                        currency = (spec.get("priceCurrency") or "").strip() or None
                    if price_raw is not None and currency:
                        break
    elif isinstance(offers, list) and offers:
        for o in offers:
            if not isinstance(o, dict):
                continue
            if not currency:
                currency = (o.get("priceCurrency") or "").strip() or None
            if price_raw is None:
                price_raw = o.get("price") or None
            if price_raw is None:
                ps = o.get("priceSpecification")
                if isinstance(ps, dict):
                    price_raw = ps.get("price")
                    if not currency:
                        currency = (ps.get("priceCurrency") or "").strip() or None
                elif isinstance(ps, list):
                    for spec in ps:
                        if not isinstance(spec, dict):
                            continue
                        if price_raw is None:
                            price_raw = spec.get("price")
                        if not currency:
                            currency = (spec.get("priceCurrency") or "").strip() or None
                        if price_raw is not None and currency:
                            break
            if price_raw is not None and currency:
                break

    # P1: dimensions, material, color
    dimensions_raw = _parse_dimensions_from_product(product)
    material_raw = product.get("material")
    if isinstance(material_raw, dict):
        material_raw = material_raw.get("name") or material_raw.get("value")
    material_raw = str(material_raw).strip() if material_raw else None
    color_raw = product.get("color")
    color_raw = str(color_raw).strip() if color_raw else None
    # additionalProperty for Färg, Material, etc.
    add_props = product.get("additionalProperty") or []
    if isinstance(add_props, dict):
        add_props = [add_props]
    for prop in add_props if isinstance(add_props, list) else []:
        if not isinstance(prop, dict):
            continue
        name = (prop.get("name") or prop.get("propertyID") or "").lower().strip()
        val = prop.get("value")
        if not val:
            continue
        val_str = str(val).strip()
        if name in ("färg", "color", "colour", "colour (english)"):
            color_raw = color_raw or val_str
        elif name in ("material", "materiel", "tyg"):
            material_raw = material_raw or val_str

    return {
        "title": title,
        "canonicalUrl": canonical,
        "images": images,
        "brand": brand,
        "description": desc,
        "priceRaw": str(price_raw).strip() if price_raw is not None else None,
        "priceCurrency": currency,
        "dimensionsRaw": dimensions_raw,
        "materialRaw": material_raw,
        "colorRaw": color_raw,
    }


def _encode_non_ascii(url: str) -> str:
    """
    Percent-encode non-ASCII characters in a URL while preserving valid structure.

    Many Swedish retailers return image URLs with raw Unicode path segments
    (e.g., /assets/blobs/möbler-soffor-...).  Browsers and HTTP clients need
    these encoded as UTF-8 percent-encoding (%C3%B6 for ö, %C3%A4 for ä, etc.).

    Strategy: fully decode the path first (handles mixed / double encoding),
    then re-encode only non-ASCII characters.
    """
    if not url or not any(ord(c) > 127 for c in url):
        return url
    try:
        from urllib.parse import urlsplit, urlunsplit, quote, unquote
        parts = urlsplit(url)
        # Fully decode first (handles mixed / double encoding)
        path = parts.path
        for _ in range(5):
            decoded = unquote(path)
            if decoded == path:
                break
            path = decoded
        # Re-encode non-ASCII characters
        encoded_path = quote(path, safe="/:@!$&'()*+,;=-._~")
        query = parts.query or ""
        for _ in range(5):
            decoded = unquote(query)
            if decoded == query:
                break
            query = decoded
        encoded_query = quote(query, safe="=&+?/:@!$'()*,;-._~") if query else ""
        return urlunsplit((parts.scheme, parts.netloc, encoded_path, encoded_query, parts.fragment))
    except Exception:
        return url


def _absolute(u: str | None, base: str) -> str | None:
    if not u:
        return None
    u = u.strip()
    if u.startswith("//"):
        result = "https:" + u
    else:
        result = urljoin(base, u)
    return _encode_non_ascii(result)


def _normalize_images(imgs: list[str], *, base_url: str) -> list[str]:
    """
    Normalize image URLs: make absolute, deduplicate, validate, filter.

    Applies _is_likely_image_url() to filter out page URLs.
    If ALL images fail validation, returns the unfiltered list as fallback
    (better to have a potentially bad image than no image at all).
    """
    all_urls: list[str] = []
    seen: set[str] = set()
    for u in imgs:
        uu = _absolute(u, base_url)
        if not uu:
            continue
        if uu in seen:
            continue
        # Skip obviously truncated URLs
        if _looks_truncated(uu):
            continue
        seen.add(uu)
        all_urls.append(uu)

    # Filter to likely image URLs
    validated = [u for u in all_urls if _is_likely_image_url(u)]

    # Fallback: if validation rejected everything, return unfiltered
    # (better to show a potentially wrong image than no image)
    if not validated and all_urls:
        return all_urls

    return validated


def _iter_nodes(root: Any, *, max_nodes: int = 20_000, max_depth: int = 8) -> list[dict]:
    """
    Return a flat list of dict nodes from an arbitrary JSON blob (depth-limited).
    """
    out: list[dict] = []
    stack: list[tuple[Any, int]] = [(root, 0)]
    seen_ids: set[int] = set()
    while stack and len(out) < max_nodes:
        node, depth = stack.pop()
        if depth > max_depth:
            continue
        if isinstance(node, dict):
            nid = id(node)
            if nid in seen_ids:
                continue
            seen_ids.add(nid)
            out.append(node)
            for v in node.values():
                if isinstance(v, (dict, list)):
                    stack.append((v, depth + 1))
        elif isinstance(node, list):
            for v in node:
                if isinstance(v, (dict, list)):
                    stack.append((v, depth + 1))
    return out


def _extract_images_from_any(value: Any) -> list[str]:
    """
    Recursively extract image URLs from arbitrary JSON structures.

    Key changes from original:
    - Prefer 'src' over 'url' (src is almost always an image)
    - Removed 'href' (too often points to product pages)
    - Added lazy-loading keys (data-src, data-image, data-original)
    - Added 'contentUrl' for schema.org ImageObject
    """
    imgs: list[str] = []
    if isinstance(value, str) and value.strip():
        imgs.append(value.strip())
    elif isinstance(value, list):
        for el in value:
            imgs.extend(_extract_images_from_any(el))
    elif isinstance(value, dict):
        # Prefer src (almost always an image) over url (can be a page URL)
        # Include lazy-loading and schema.org keys
        for k in ("src", "contentUrl", "url", "data-src", "data-image", "data-original"):
            v = value.get(k)
            if v and isinstance(v, str) and v.strip():
                imgs.append(v.strip())
                break  # Take the first match from this dict to avoid duplicates
    return imgs


def _extract_from_embedded_json(signals: PageSignals, *, base_url: str) -> dict | None:
    """
    Heuristic embedded JSON extractor (no per-site mapping).

    Picks the \"best\" dict node that looks product-like, then maps common keys.
    """
    best_node: dict | None = None
    best_score = 0.0

    for cand in signals.embedded_json_candidates:
        data = cand.get("data")
        nodes = _iter_nodes(data)
        for node in nodes:
            # product-ish key presence
            keys = {str(k).lower() for k in node.keys()}
            if not any(k in keys for k in ("name", "title", "productname")):
                continue
            if not any(k in keys for k in ("price", "priceamount", "offers", "currentprice", "saleprice")):
                continue

            title = clean_title_text(
                node.get("name") or node.get("title") or node.get("productName")
            ) or ""
            if len(title) < 3:
                continue

            imgs = []
            for k in ("images", "image", "gallery", "media"):
                if k in node:
                    imgs = _extract_images_from_any(node.get(k))
                    if imgs:
                        break

            # Try to find raw price-ish value
            price_val = node.get("price") or node.get("priceAmount") or node.get("currentPrice") or node.get("salePrice")
            if price_val is None and isinstance(node.get("offers"), dict):
                price_val = node["offers"].get("price")

            price_raw = str(price_val).strip() if price_val is not None else None
            money = parse_money_sv(price_raw)

            score = 0.0
            score += 2.0  # has title
            score += 1.5 if imgs else 0.0
            score += 1.5 if money.amount is not None else 0.0
            score += 0.5 if node.get("sku") or node.get("gtin") else 0.0

            if score > best_score:
                best_score = score
                best_node = node

    if best_node is None:
        return None

    title = clean_title_text(
        best_node.get("name") or best_node.get("title") or best_node.get("productName")
    ) or ""
    canonical = best_node.get("canonicalUrl") or best_node.get("url") or None
    canonical = str(canonical).strip() if canonical is not None else ""

    imgs: list[str] = []
    for k in ("images", "image", "gallery", "media"):
        if k in best_node:
            imgs = _extract_images_from_any(best_node.get(k))
            if imgs:
                break

    price_val = best_node.get("price") or best_node.get("priceAmount") or best_node.get("currentPrice") or best_node.get("salePrice")
    currency = best_node.get("currency") or best_node.get("priceCurrency") or None
    if price_val is None and isinstance(best_node.get("offers"), dict):
        currency = currency or best_node["offers"].get("priceCurrency")
        price_val = best_node["offers"].get("price") or price_val

    # P1: dimensions, material, color from embedded JSON
    dimensions_raw = None
    dims = best_node.get("dimensionsCm") or best_node.get("dimensions")
    if isinstance(dims, dict):
        w = _parse_quantitative_value(dims.get("w") or dims.get("width"))
        h = _parse_quantitative_value(dims.get("h") or dims.get("height"))
        d = _parse_quantitative_value(dims.get("d") or dims.get("depth"))
        if w is not None or h is not None or d is not None:
            dimensions_raw = {"w": w or 0, "h": h or 0, "d": d or 0}
    elif best_node.get("width") is not None or best_node.get("height") is not None or best_node.get("depth") is not None:
        w = _parse_quantitative_value(best_node.get("width"))
        h = _parse_quantitative_value(best_node.get("height"))
        d = _parse_quantitative_value(best_node.get("depth"))
        if w is not None or h is not None or d is not None:
            dimensions_raw = {"w": w or 0, "h": h or 0, "d": d or 0}

    material_raw = best_node.get("material") or best_node.get("materialName") or best_node.get("fabric") or best_node.get("coverMaterial")
    material_raw = str(material_raw).strip() if material_raw else None
    color_raw = best_node.get("color") or best_node.get("colorName") or best_node.get("colorFamily") or best_node.get("colour") or best_node.get("variantColor")
    color_raw = str(color_raw).strip() if color_raw else None

    return {
        "title": title,
        "canonicalUrl": canonical,
        "images": [u for u in imgs if isinstance(u, str) and u.strip()],
        "brand": (best_node.get("brand") or {}).get("name") if isinstance(best_node.get("brand"), dict) else best_node.get("brand"),
        "description": best_node.get("description") if isinstance(best_node.get("description"), str) else None,
        "priceRaw": str(price_val).strip() if price_val is not None else None,
        "priceCurrency": str(currency).strip() if currency else None,
        "dimensionsRaw": dimensions_raw,
        "materialRaw": material_raw,
        "colorRaw": color_raw,
    }


def _validate_required(*, title: str, canonical_url: str) -> list[str]:
    errs: list[str] = []
    if not title.strip():
        errs.append("missing_title")
    if not canonical_url.strip() or not canonical_url.startswith(("http://", "https://")):
        errs.append("missing_or_invalid_canonical")
    return errs


def _score(
    *,
    title: bool,
    canonical: bool,
    images: bool,
    price_amount: bool,
    price_currency: bool,
    description: bool = False,
    dimensions: bool = False,
    material: bool = False,
    color: bool = False,
    brand: bool = False,
) -> float:
    weights = {
        "title": 3,
        "canonical": 3,
        "images": 2,
        "price_amount": 2,
        "price_currency": 1,
        "description": 2,
        "dimensions": 1,
        "material": 1,
        "color": 1,
        "brand": 1,
    }
    got = 0
    total = sum(weights.values())
    if title:
        got += weights["title"]
    if canonical:
        got += weights["canonical"]
    if images:
        got += weights["images"]
    if price_amount:
        got += weights["price_amount"]
    if price_currency:
        got += weights["price_currency"]
    if description:
        got += weights["description"]
    if dimensions:
        got += weights["dimensions"]
    if material:
        got += weights["material"]
    if color:
        got += weights["color"]
    if brand:
        got += weights["brand"]
    return got / total if total else 0.0


def _infer_material_from_text(title: str | None, description: str | None) -> str | None:
    """Delegate to normalization module for material inference from text."""
    try:
        from app.normalization import infer_material_from_text
        return infer_material_from_text(title, description)
    except Exception:
        return None


def _apply_enrichment(
    product: NormalizedProduct,
    *,
    jsonld_product: dict | None,
    embedded_node: dict | None,
    html: str,
    jsonld_blocks: list | None,
) -> NormalizedProduct:
    """Apply EPIC B enrichment to a NormalizedProduct, returning a new enriched version."""
    try:
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, "lxml")
    except Exception:
        soup = None

    meta = enrich_product(
        jsonld_product=jsonld_product,
        embedded_node=embedded_node,
        soup=soup,
        jsonld_blocks=jsonld_blocks,
        title=product.title,
        current_price=product.price_amount,
    )

    # --- Post-extraction inference for missing fields ---
    # This runs AFTER extraction so it can use all available data
    # (title, description, facets, etc.) regardless of extraction method.
    from app.normalization import infer_color_from_text, normalize_material

    promoted_dimensions = product.dimensions_raw or _extract_dimensions_from_facets(meta.facets)

    # Color: use extracted value, or infer from title + description
    color_raw = product.color_raw
    if not color_raw:
        color_raw = infer_color_from_text(product.title, product.description)

    # Material: use extracted value, or try to infer from title + description
    material_raw = product.material_raw
    if not material_raw:
        material_raw = _infer_material_from_text(product.title, product.description)

    completeness_score = _score(
        title=bool(product.title),
        canonical=bool(product.canonical_url),
        images=bool(product.images),
        price_amount=product.price_amount is not None,
        price_currency=bool(product.price_currency),
        description=bool(product.description),
        dimensions=bool(promoted_dimensions),
        material=bool(material_raw),
        color=bool(color_raw),
        brand=bool(product.brand),
    )
    return NormalizedProduct(
        retailer_id=product.retailer_id,
        retailer_domain=product.retailer_domain,
        product_url=product.product_url,
        canonical_url=product.canonical_url,
        title=product.title,
        price_amount=product.price_amount,
        price_currency=product.price_currency,
        price_raw=product.price_raw,
        images=product.images,
        description=product.description,
        brand=product.brand,
        extracted_at=product.extracted_at,
        method=product.method,
        recipe_id=product.recipe_id,
        recipe_version=product.recipe_version,
        completeness_score=completeness_score,
        warnings=product.warnings,
        debug=product.debug,
        dimensions_raw=promoted_dimensions,
        material_raw=material_raw,
        color_raw=color_raw,
        # Enriched fields
        breadcrumbs=meta.breadcrumbs or None,
        product_type=meta.product_type,
        retailer_category_label=meta.retailer_category_label,
        facets=meta.facets if meta.facets else None,
        variants=meta.variants if meta.variants else None,
        sku=meta.sku,
        mpn=meta.mpn,
        gtin=meta.gtin,
        model_name=meta.model_name,
        price_original=meta.price_original,
        discount_pct=meta.discount_pct,
        availability=meta.availability,
        delivery_eta=meta.delivery_eta,
        shipping_cost=meta.shipping_cost,
        enrichment_evidence=meta.evidence_sources if meta.evidence_sources else None,
    )


def extract_product_from_html(
    *,
    source_id: str,
    fetched_url: str,
    final_url: str,
    html: str,
    extracted_at_iso: str,
    recipe: dict | None = None,
) -> NormalizedProduct | None:
    signals: PageSignals = extract_page_signals(html, final_url=final_url)
    canonical = (_absolute(signals.canonical_url, final_url) or _absolute(signals.og_url, final_url) or final_url).strip()

    warnings: list[str] = []
    debug: dict = {"finalUrl": final_url, "signals": {"ogType": signals.og_type}}

    # JSON-LD first
    jsonld_obj = _pick_jsonld_product(signals.jsonld_blocks)
    if isinstance(jsonld_obj, dict):
        raw = _extract_from_jsonld(jsonld_obj)
        canonical2 = (_absolute(raw.get("canonicalUrl"), final_url) or canonical).strip()
        title = clean_title_text(raw.get("title")) or ""
        images = [u for u in (raw.get("images") or []) if isinstance(u, str) and u.strip()]
        images = _normalize_images(images, base_url=final_url)

        # Fallback chain when JSON-LD images fail validation
        image_source = "jsonld"
        if not images and signals.og_images:
            images = _normalize_images(list(signals.og_images), base_url=final_url)
            image_source = "og_image"
        if not images:
            images = _extract_images_from_dom(html, base_url=final_url)
            image_source = "dom_fallback"
        if not images:
            warnings.append("images:none_found")

        money = parse_money_sv(raw.get("priceRaw"))
        jsonld_currency = str(raw.get("priceCurrency") or "").strip().upper() or None
        if jsonld_currency and money.currency and jsonld_currency != money.currency:
            warnings.append("price:currency_mismatch")
        resolved_jsonld_currency = jsonld_currency or money.currency
        if money.warnings:
            warnings.extend([f"price:{w}" for w in money.warnings if w != "missing"])

        errs = _validate_required(title=title, canonical_url=canonical2)
        if not errs:
            score = _score(
                title=bool(title),
                canonical=bool(canonical2),
                images=bool(images),
                price_amount=money.amount is not None,
                price_currency=bool(resolved_jsonld_currency),
                description=bool(raw.get("description")),
                dimensions=bool(raw.get("dimensionsRaw")),
                material=bool(raw.get("materialRaw")),
                color=bool(raw.get("colorRaw")),
                brand=bool(raw.get("brand")),
            )
            product = NormalizedProduct(
                retailer_id=source_id,
                retailer_domain=_domain(canonical2 or final_url),
                product_url=fetched_url,
                canonical_url=canonical2,
                title=title,
                price_amount=money.amount,
                price_currency=resolved_jsonld_currency,
                price_raw=money.raw or None,
                images=images,
                description=raw.get("description"),
                brand=raw.get("brand"),
                extracted_at=extracted_at_iso,
                method="jsonld",
                recipe_id=None,
                recipe_version=None,
                completeness_score=score,
                warnings=warnings,
                debug={"strategy": "jsonld", "imageSource": image_source, **debug},
                dimensions_raw=raw.get("dimensionsRaw"),
                material_raw=raw.get("materialRaw"),
                color_raw=raw.get("colorRaw"),
            )
            return _apply_enrichment(
                product,
                jsonld_product=jsonld_obj,
                embedded_node=None,
                html=html,
                jsonld_blocks=signals.jsonld_blocks,
            )

    # Embedded JSON (Next.js and generic blobs) – heuristic extraction
    embedded = _extract_from_embedded_json(signals, base_url=final_url)
    if embedded:
        canonical2 = (_absolute(embedded.get("canonicalUrl"), final_url) or canonical).strip()
        title = clean_title_text(embedded.get("title")) or ""
        images = _normalize_images([u for u in (embedded.get("images") or []) if isinstance(u, str)], base_url=final_url)

        # Fallback chain when embedded JSON images fail validation
        image_source = "embedded_json"
        if not images and signals.og_images:
            images = _normalize_images(list(signals.og_images), base_url=final_url)
            image_source = "og_image"
        if not images:
            images = _extract_images_from_dom(html, base_url=final_url)
            image_source = "dom_fallback"
        if not images:
            warnings.append("images:none_found")

        money = parse_money_sv(embedded.get("priceRaw"))
        if embedded.get("priceCurrency") and money.currency and embedded.get("priceCurrency") != money.currency:
            warnings.append("price:currency_mismatch")
        if money.warnings:
            warnings.extend([f"price:{w}" for w in money.warnings if w != "missing"])

        errs = _validate_required(title=title, canonical_url=canonical2)
        if not errs:
            score = _score(
                title=bool(title),
                canonical=bool(canonical2),
                images=bool(images),
                price_amount=money.amount is not None,
                price_currency=bool(money.currency),
                description=bool(embedded.get("description")),
                dimensions=bool(embedded.get("dimensionsRaw")),
                material=bool(embedded.get("materialRaw")),
                color=bool(embedded.get("colorRaw")),
                brand=bool(embedded.get("brand")),
            )
            product = NormalizedProduct(
                retailer_id=source_id,
                retailer_domain=_domain(canonical2 or final_url),
                product_url=fetched_url,
                canonical_url=canonical2,
                title=title,
                price_amount=money.amount,
                price_currency=embedded.get("priceCurrency") or money.currency,
                price_raw=money.raw or None,
                images=images,
                description=embedded.get("description"),
                brand=(str(embedded.get("brand")).strip() if embedded.get("brand") else None),
                extracted_at=extracted_at_iso,
                method="embedded_json",
                recipe_id=None,
                recipe_version=None,
                completeness_score=score,
                warnings=warnings,
                debug={"strategy": "embedded_json", "imageSource": image_source, "embeddedCandidates": len(signals.embedded_json_candidates), **debug},
                dimensions_raw=embedded.get("dimensionsRaw"),
                material_raw=embedded.get("materialRaw"),
                color_raw=embedded.get("colorRaw"),
            )
            return _apply_enrichment(
                product,
                jsonld_product=jsonld_obj if isinstance(jsonld_obj, dict) else None,
                embedded_node=None,  # embedded dict isn't the raw node
                html=html,
                jsonld_blocks=signals.jsonld_blocks,
            )

    # Recipe runner (deterministic, per-retailer)
    if recipe:
        try:
            from app.recipes.runner import run_recipe_on_html
            from app.recipes.schema import get_meta

            meta = get_meta(recipe)
            rr = run_recipe_on_html(recipe=recipe, html=html, final_url=final_url)
            if rr.ok:
                canonical2 = (_absolute(rr.output.get("canonicalUrl"), final_url) or canonical).strip()
                title = clean_title_text(rr.output.get("title")) or ""
                images = rr.output.get("images")
                if not isinstance(images, list):
                    images = []
                images = _normalize_images([str(x) for x in images], base_url=final_url)
                price_raw = None
                price_currency = None
                if isinstance(rr.output.get("price"), dict):
                    price_raw = rr.output["price"].get("raw")
                    price_currency = rr.output["price"].get("currency")
                money = parse_money_sv(price_raw)
                warnings.extend(rr.warnings)
                if money.warnings:
                    warnings.extend([f"price:{w}" for w in money.warnings if w != "missing"])
                errs = _validate_required(title=title, canonical_url=canonical2)
                if not errs:
                    # P1: recipe pass-through for dimensions, material, color
                    dims_out = rr.output.get("dimensionsCm") or rr.output.get("dimensions")
                    dimensions_raw = None
                    if isinstance(dims_out, dict):
                        w = _parse_quantitative_value(dims_out.get("w") or dims_out.get("width"))
                        h = _parse_quantitative_value(dims_out.get("h") or dims_out.get("height"))
                        d = _parse_quantitative_value(dims_out.get("d") or dims_out.get("depth"))
                        if w is not None or h is not None or d is not None:
                            dimensions_raw = {"w": w or 0, "h": h or 0, "d": d or 0}
                    material_raw = rr.output.get("material") or rr.output.get("materialRaw")
                    material_raw = str(material_raw).strip() if material_raw else None
                    color_raw = rr.output.get("color") or rr.output.get("colorFamily") or rr.output.get("colorRaw")
                    color_raw = str(color_raw).strip() if color_raw else None
                    score = _score(
                        title=bool(title),
                        canonical=bool(canonical2),
                        images=bool(images),
                        price_amount=money.amount is not None,
                        price_currency=bool(price_currency or money.currency),
                        description=bool(rr.output.get("description")),
                        dimensions=bool(dimensions_raw),
                        material=bool(material_raw),
                        color=bool(color_raw),
                        brand=bool(rr.output.get("brand")),
                    )
                    product = NormalizedProduct(
                        retailer_id=source_id,
                        retailer_domain=_domain(canonical2 or final_url),
                        product_url=fetched_url,
                        canonical_url=canonical2,
                        title=title,
                        price_amount=money.amount,
                        price_currency=price_currency or money.currency,
                        price_raw=money.raw or None,
                        images=images,
                        description=rr.output.get("description") if isinstance(rr.output.get("description"), str) else None,
                        brand=str(rr.output.get("brand")).strip() if rr.output.get("brand") else None,
                        extracted_at=extracted_at_iso,
                        method="recipe",
                        recipe_id=meta.recipe_id,
                        recipe_version=meta.version,
                        completeness_score=score,
                        warnings=warnings,
                        debug={"strategy": "recipe", "recipeTrace": rr.debug_trace, **debug},
                        dimensions_raw=dimensions_raw,
                        material_raw=material_raw,
                        color_raw=color_raw,
                    )
                    return _apply_enrichment(
                        product,
                        jsonld_product=jsonld_obj if isinstance(jsonld_obj, dict) else None,
                        embedded_node=None,
                        html=html,
                        jsonld_blocks=signals.jsonld_blocks,
                    )
        except Exception as e:
            warnings.append("recipe:runner_error")

    # DOM semantic fallback: rely on og tags + title from H1, and semantic meta tags for price.
    try:
        from app.locator.classifier import classify_url
        from bs4 import BeautifulSoup

        soup = BeautifulSoup(html, "lxml")
        h1 = soup.find("h1")
        title = clean_title_text(h1.get_text(strip=True) if h1 else "") or ""
        if not title:
            mt = soup.find("meta", property="og:title")
            title = clean_title_text(mt.get("content") if mt else "") or ""

        # Try og:image first, then DOM image extraction
        imgs = _normalize_images(list(signals.og_images), base_url=final_url)
        image_source = "og_image"
        if not imgs:
            imgs = _extract_images_from_dom(html, base_url=final_url)
            image_source = "dom_img"
        if not imgs:
            warnings.append("images:none_found")

        price_raw = None
        dom_price_currency = None
        mp = soup.find("meta", property="product:price:amount")
        if mp and mp.get("content"):
            price_raw = mp.get("content")
        mpc = soup.find("meta", property="product:price:currency")
        if mpc and mpc.get("content"):
            dom_price_currency = str(mpc.get("content")).strip().upper() or None
        if not dom_price_currency:
            ip_currency = soup.find(attrs={"itemprop": "priceCurrency"})
            if ip_currency:
                dom_price_currency = str(ip_currency.get("content") or ip_currency.get_text(" ", strip=True)).strip().upper() or None
        if not price_raw:
            price_raw = _extract_price_raw_from_dom(soup)
        money = parse_money_sv(price_raw)
        if dom_price_currency and money.currency and dom_price_currency != money.currency:
            warnings.append("price:currency_mismatch")
        resolved_dom_currency = dom_price_currency or money.currency
        if money.warnings:
            warnings.extend([f"price:{w}" for w in money.warnings if w != "missing"])

        # Guardrail: avoid treating category/listing pages as products.
        # For DOM-only extraction, require either:
        # - og:type=product, or
        # - a parseable price AND a product-like URL classification.
        og_type = (signals.og_type or "").lower()
        cls = classify_url(final_url)
        productish_url = cls.url_type_hint == "product" or cls.confidence >= 0.65
        if ("product" not in og_type) and not (money.amount is not None and productish_url):
            return None

        errs = _validate_required(title=title, canonical_url=canonical)
        if not errs:
            from app.normalization import infer_color_from_title

            description_raw = _extract_description_from_dom(soup)
            dimensions_raw = _extract_dimensions_from_dom(soup)
            material_raw = _extract_material_from_dom(soup)
            brand_raw = _extract_brand_from_dom(soup)
            color_raw = infer_color_from_title(title)
            rich_specs = _extract_rich_specs_from_dom(soup)
            score = _score(
                title=bool(title),
                canonical=bool(canonical),
                images=bool(imgs),
                price_amount=money.amount is not None,
                price_currency=bool(resolved_dom_currency),
                description=bool(description_raw),
                dimensions=bool(dimensions_raw),
                material=bool(material_raw),
                color=bool(color_raw),
                brand=bool(brand_raw),
            )
            product = NormalizedProduct(
                retailer_id=source_id,
                retailer_domain=_domain(canonical),
                product_url=fetched_url,
                canonical_url=canonical,
                title=title,
                price_amount=money.amount,
                price_currency=resolved_dom_currency,
                price_raw=money.raw or None,
                images=imgs,
                description=description_raw,
                brand=brand_raw,
                extracted_at=extracted_at_iso,
                method="dom",
                recipe_id=None,
                recipe_version=None,
                completeness_score=score,
                warnings=warnings,
                debug={"strategy": "dom_semantic", "imageSource": image_source, **debug},
                dimensions_raw=dimensions_raw,
                material_raw=material_raw,
                color_raw=color_raw,
                seat_height_cm=rich_specs.get("seat_height_cm"),
                seat_depth_cm=rich_specs.get("seat_depth_cm"),
                seat_width_cm=rich_specs.get("seat_width_cm"),
                seat_count=rich_specs.get("seat_count"),
                weight_kg=rich_specs.get("weight_kg"),
                frame_material=rich_specs.get("frame_material"),
                cover_material=rich_specs.get("cover_material"),
                leg_material=rich_specs.get("leg_material"),
                cushion_filling=rich_specs.get("cushion_filling"),
            )
            return _apply_enrichment(
                product,
                jsonld_product=jsonld_obj if isinstance(jsonld_obj, dict) else None,
                embedded_node=None,
                html=html,
                jsonld_blocks=signals.jsonld_blocks,
            )
    except Exception:
        pass

    return None


# ============================================================================
# BATCH EXTRACTION FROM EMBEDDED STATE
# ============================================================================

def _description_matches_title(title: str | None, description: str | None) -> bool:
    """Check if a description plausibly belongs to the given product title.

    Returns True if at least one significant word (>3 chars) from the title
    appears in the first 300 characters of the description.  This catches
    obvious mismatches where the description is for an entirely different product.
    """
    if not title or not description:
        return True  # can't validate, allow through
    title_words = {
        w.lower()
        for w in re.split(r"[\s,\-/]+", title)
        if len(w) > 3 and w.isalpha()
    }
    if not title_words:
        return True
    desc_prefix = description[:300].lower()
    return any(w in desc_prefix for w in title_words)


def extract_products_batch_from_html(
    *,
    source_id: str,
    fetched_url: str,
    final_url: str,
    html: str,
    extracted_at_iso: str,
) -> list[NormalizedProduct]:
    """
    Extract MULTIPLE products from a single page using embedded JS state.

    This handles category/listing pages where the full product catalog is
    embedded in window.INITIAL_DATA, window.__INITIAL_STATE__, etc.

    Returns a list of NormalizedProduct objects (may be empty).
    """
    signals: PageSignals = extract_page_signals(html, final_url=final_url)

    # Only process embedded state candidates that are window-level state
    state_candidates = [
        c for c in signals.embedded_json_candidates
        if c.get("kind") == "windowState" and isinstance(c.get("data"), dict)
    ]
    if not state_candidates:
        return []

    all_products: list[NormalizedProduct] = []

    for candidate in state_candidates:
        state_id = candidate.get("id", "")
        state_data = candidate["data"]
        base_url = f"{urlparse(final_url).scheme}://{urlparse(final_url).netloc}"

        raw_products = extract_products_from_state(
            state_id=state_id,
            data=state_data,
            base_url=base_url,
        )

        for raw in raw_products:
            title = clean_title_text(raw.get("title")) or ""
            if not title:
                continue

            product_url = (raw.get("url") or "").strip()
            canonical = product_url or final_url

            # Normalize images
            raw_images = raw.get("images") or []
            images = _normalize_images(
                [u for u in raw_images if isinstance(u, str) and u.strip()],
                base_url=base_url,
            )

            # Price
            price_amount = raw.get("price_amount")
            price_currency = raw.get("price_currency") or "SEK"

            # Completeness score
            score = _score(
                title=bool(title),
                canonical=bool(canonical and canonical.startswith("http")),
                images=bool(images),
                price_amount=price_amount is not None,
                price_currency=bool(price_currency),
                description=bool(raw.get("description")),
                dimensions=False,
                material=False,
                color=False,
                brand=bool(raw.get("brand")),
            )

            warnings: list[str] = []
            if not images:
                warnings.append("images:none_found")

            errs = _validate_required(title=title, canonical_url=canonical)
            if errs:
                continue

            product = NormalizedProduct(
                retailer_id=source_id,
                retailer_domain=_domain(canonical or final_url),
                product_url=product_url or fetched_url,
                canonical_url=canonical,
                title=title,
                price_amount=price_amount,
                price_currency=price_currency,
                price_raw=str(price_amount) if price_amount is not None else None,
                images=images,
                description=(
                    raw.get("description")
                    if _description_matches_title(title, raw.get("description"))
                    else None
                ),
                brand=raw.get("brand"),
                extracted_at=extracted_at_iso,
                method="embedded_state",
                recipe_id=None,
                recipe_version=None,
                completeness_score=score,
                warnings=warnings,
                debug={
                    "strategy": "embedded_state",
                    "stateVar": state_id,
                    "batchSource": final_url,
                },
                dimensions_raw=None,
                material_raw=None,
                color_raw=None,
                breadcrumbs=list(raw.get("category_names", [])) or None,
                sku=raw.get("sku"),
                price_original=raw.get("price_original"),
            )
            all_products.append(product)

    return all_products
