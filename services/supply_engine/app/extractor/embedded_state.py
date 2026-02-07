"""
Embedded JS State Extractor – extracts products from window.* state variables.

Many modern e-commerce sites embed their full product catalog in the initial
HTML as a JavaScript state variable (e.g., window.INITIAL_DATA, window.__INITIAL_STATE__).
This module parses these known patterns and extracts normalized product data.

Supports:
- Chilli:       window.INITIAL_DATA = JSON.parse('...')
- RoyalDesign:  window.__INITIAL_STATE__ = {...}
- Generic:      Any embedded JSON with product-like arrays

Each handler returns a list of dicts with normalized keys:
    title, url, brand, price_amount, price_currency, images[], sku,
    category_names[], description
"""
from __future__ import annotations

import logging
from typing import Any
from urllib.parse import urljoin, urlsplit, urlunsplit, quote

log = logging.getLogger(__name__)


def _safe_urljoin(base: str, path: str) -> str:
    """urljoin + percent-encode non-ASCII characters (Swedish chars ö, ä, å, etc.)."""
    url = urljoin(base, path)
    if not any(ord(c) > 127 for c in url):
        return url
    try:
        parts = urlsplit(url)
        encoded_path = quote(parts.path, safe="/:@!$&'()*+,;=-._~")
        encoded_query = quote(parts.query, safe="=&+?/:@!$'()*,;-._~") if parts.query else ""
        return urlunsplit((parts.scheme, parts.netloc, encoded_path, encoded_query, parts.fragment))
    except Exception:
        return url


# ============================================================================
# HANDLER REGISTRY
# ============================================================================

def extract_products_from_state(
    *,
    state_id: str,
    data: dict,
    base_url: str,
) -> list[dict]:
    """
    Dispatch to the appropriate handler based on the state variable name.

    Returns a list of dicts, each with:
        title, url, brand, price_amount, price_currency, images,
        sku, category_names, description
    """
    handler = _HANDLERS.get(state_id)
    if handler:
        try:
            return handler(data, base_url)
        except Exception as e:
            log.warning("Handler %s failed: %s", state_id, e)
            return []

    # Generic fallback: search for product arrays anywhere in the tree
    return _extract_generic(data, base_url)


# ============================================================================
# CHILLI: window.INITIAL_DATA = JSON.parse('...')
# ============================================================================

def _extract_chilli(data: dict, base_url: str) -> list[dict]:
    """
    Chilli stores products at data["page"]["products"], each with:
      - displayName, url, brand (str), price.current.inclVat,
        images[].url, currentSku, categoryNames[]
    """
    products = data.get("page", {}).get("products", [])
    if not isinstance(products, list):
        return []

    results: list[dict] = []
    for p in products:
        if not isinstance(p, dict):
            continue

        name = p.get("displayName", "").strip()
        if not name:
            continue

        url = p.get("url", "")
        if url and not url.startswith("http"):
            url = _safe_urljoin(base_url, url)

        # Price: nested under price.current.inclVat
        price_amount = None
        price_original = None
        price_obj = p.get("price", {})
        if isinstance(price_obj, dict):
            current = price_obj.get("current", {})
            if isinstance(current, dict):
                price_amount = current.get("inclVat")
            regular = price_obj.get("regular", {})
            if isinstance(regular, dict):
                price_original = regular.get("inclVat")

        # Images: relative paths, need base URL
        images: list[str] = []
        for img in p.get("images", []):
            if isinstance(img, dict):
                img_url = img.get("url", "")
            elif isinstance(img, str):
                img_url = img
            else:
                continue
            if img_url:
                if not img_url.startswith("http"):
                    img_url = _safe_urljoin(base_url, img_url)
                images.append(img_url)

        brand = p.get("brand", "")
        if isinstance(brand, dict):
            brand = brand.get("name", "")

        results.append({
            "title": name,
            "url": url,
            "brand": brand or None,
            "price_amount": _to_float(price_amount),
            "price_original": _to_float(price_original),
            "price_currency": "SEK",
            "images": images,
            "sku": p.get("currentSku") or p.get("productKey"),
            "category_names": p.get("categoryNames", []),
            "description": None,
        })

    return results


# ============================================================================
# ROYALDESIGN: window.__INITIAL_STATE__ = {...}
# ============================================================================

def _extract_royaldesign(data: dict, base_url: str) -> list[dict]:
    """
    RoyalDesign stores products and variants in separate dicts:
      - data["productInfo"]["products"]  – dict keyed by product ID
        Fields: name, slug, subHeader, manufacturer.name, defaultVariant
      - data["productInfo"]["variants"]  – dict keyed by variant partNo
        Fields: price.salesPriceInclVat, imageUrl, additionalImages[].url

    The product's `defaultVariant` is a partNo string that maps into the
    top-level variants dict (NOT into the product's own `variants` field,
    which is always empty on category pages).
    """
    product_info = data.get("productInfo", {})
    product_map = product_info.get("products", {})
    # Variants live at the TOP LEVEL of productInfo, not inside each product
    global_variants = product_info.get("variants", {})

    if not isinstance(product_map, dict):
        return []

    results: list[dict] = []
    for pid, p in product_map.items():
        if not isinstance(p, dict):
            continue

        name = p.get("name", "").strip()
        if not name:
            continue

        slug = p.get("slug", "")
        url = _safe_urljoin(base_url, slug) if slug else ""

        brand = None
        mfg = p.get("manufacturer")
        if isinstance(mfg, dict):
            brand = mfg.get("name")

        # Resolve the default variant from the GLOBAL variants map
        default_var_id = p.get("defaultVariant")
        price_amount = None
        price_original = None
        images: list[str] = []

        if default_var_id and isinstance(global_variants, dict):
            var = global_variants.get(str(default_var_id), {})
            if isinstance(var, dict):
                # Price: salesPriceInclVat (incl. VAT) is the consumer-facing price
                price_data = var.get("price", {})
                if isinstance(price_data, dict):
                    price_amount = _to_float(
                        price_data.get("salesPriceInclVat")
                        or price_data.get("regularPriceInclVat")
                    )
                    price_original = _to_float(price_data.get("regularPriceInclVat"))
                    # If sale = regular, there's no discount
                    if price_amount == price_original:
                        price_original = None

                # Primary image: imageUrl (direct string, not array)
                img_url = var.get("imageUrl", "")
                if img_url:
                    if not img_url.startswith("http"):
                        img_url = _safe_urljoin(base_url, img_url)
                    images.append(img_url)

                # Additional images
                for img in var.get("additionalImages", []):
                    if isinstance(img, dict):
                        extra_url = img.get("url", "")
                        if extra_url:
                            if not extra_url.startswith("http"):
                                extra_url = _safe_urljoin(base_url, extra_url)
                            images.append(extra_url)

        # Fallback: try any related variant from variantPartNos
        if price_amount is None or not images:
            part_nos = p.get("variantPartNos", [])
            if isinstance(part_nos, list):
                for pno in part_nos:
                    var = global_variants.get(str(pno), {})
                    if not isinstance(var, dict):
                        continue
                    if price_amount is None:
                        pd = var.get("price", {})
                        if isinstance(pd, dict):
                            price_amount = _to_float(
                                pd.get("salesPriceInclVat")
                                or pd.get("regularPriceInclVat")
                            )
                    if not images:
                        img_url = var.get("imageUrl", "")
                        if img_url:
                            if not img_url.startswith("http"):
                                img_url = _safe_urljoin(base_url, img_url)
                            images.append(img_url)
                    if price_amount is not None and images:
                        break

        results.append({
            "title": name,
            "url": url,
            "brand": brand or None,
            "price_amount": price_amount,
            "price_original": price_original,
            "price_currency": "SEK",
            "images": images,
            "sku": str(pid),
            "category_names": [],
            "description": (p.get("subHeader") or "").strip() or None,
        })

    return results


# ============================================================================
# GENERIC FALLBACK: search for product-like arrays
# ============================================================================

def _extract_generic(data: dict, base_url: str) -> list[dict]:
    """
    Walk the state tree looking for arrays of objects that look like products.

    A product-like object has at least: a name/title field AND a price-like field.
    """
    candidate_arrays = _find_product_arrays(data, max_depth=6)
    if not candidate_arrays:
        return []

    # Pick the array with the most product-like objects
    best_array: list[dict] = []
    best_score = 0
    for arr in candidate_arrays:
        score = _score_product_array(arr)
        if score > best_score:
            best_score = score
            best_array = arr

    if not best_array:
        return []

    results: list[dict] = []
    for item in best_array:
        if not isinstance(item, dict):
            continue
        product = _normalize_generic_product(item, base_url)
        if product:
            results.append(product)

    return results


def _find_product_arrays(data: Any, *, max_depth: int = 6, _depth: int = 0) -> list[list]:
    """Recursively find all arrays of 3+ dicts that might be product lists."""
    if _depth > max_depth:
        return []
    found: list[list] = []
    if isinstance(data, dict):
        for v in data.values():
            if isinstance(v, list) and len(v) >= 3:
                # Check if most elements are dicts
                dict_count = sum(1 for el in v if isinstance(el, dict))
                if dict_count >= len(v) * 0.7:
                    found.append(v)
            if isinstance(v, (dict, list)):
                found.extend(_find_product_arrays(v, max_depth=max_depth, _depth=_depth + 1))
    elif isinstance(data, list):
        for v in data:
            if isinstance(v, (dict, list)):
                found.extend(_find_product_arrays(v, max_depth=max_depth, _depth=_depth + 1))
    return found


def _score_product_array(arr: list) -> int:
    """Score how product-like an array is (higher = more likely products)."""
    score = 0
    for item in arr[:10]:  # Sample first 10
        if not isinstance(item, dict):
            continue
        keys_lower = {str(k).lower() for k in item.keys()}
        has_name = bool(keys_lower & {"name", "title", "displayname", "productname", "product_name"})
        has_price = bool(keys_lower & {"price", "currentprice", "saleprice", "price_amount", "priceamount"})
        has_url = bool(keys_lower & {"url", "slug", "href", "link", "product_url", "producturl"})
        has_image = bool(keys_lower & {"image", "images", "img", "imageurl", "image_url", "thumbnail"})
        has_sku = bool(keys_lower & {"sku", "productid", "product_id", "id", "articleno", "articlenumber"})

        if has_name:
            score += 3
        if has_price:
            score += 3
        if has_url:
            score += 2
        if has_image:
            score += 1
        if has_sku:
            score += 1
    return score


def _normalize_generic_product(item: dict, base_url: str) -> dict | None:
    """Normalize a generic product-like dict into our standard format."""
    # Title
    title = ""
    for key in ("name", "title", "displayName", "productName", "product_name"):
        val = item.get(key)
        if isinstance(val, str) and val.strip():
            title = val.strip()
            break
    if not title:
        return None

    # URL
    url = ""
    for key in ("url", "slug", "href", "link", "product_url", "productUrl"):
        val = item.get(key)
        if isinstance(val, str) and val.strip():
            url = val.strip()
            break
    if url and not url.startswith("http"):
        url = _safe_urljoin(base_url, url)

    # Price
    price_amount = None
    for key in ("price", "currentPrice", "salePrice", "price_amount", "priceAmount"):
        val = item.get(key)
        if isinstance(val, (int, float)):
            price_amount = float(val)
            break
        if isinstance(val, dict):
            # Nested price object
            for sub_key in ("current", "inclVat", "amount", "value", "sale", "price"):
                sv = val.get(sub_key)
                if isinstance(sv, (int, float)):
                    price_amount = float(sv)
                    break
                if isinstance(sv, dict):
                    for ssub in ("inclVat", "amount", "value"):
                        ssv = sv.get(ssub)
                        if isinstance(ssv, (int, float)):
                            price_amount = float(ssv)
                            break
                if price_amount is not None:
                    break
            break
        if isinstance(val, str):
            price_amount = _to_float(val)
            break

    # Images
    images: list[str] = []
    for key in ("images", "image", "img", "gallery", "media"):
        val = item.get(key)
        if isinstance(val, list):
            for el in val:
                img_url = ""
                if isinstance(el, str):
                    img_url = el
                elif isinstance(el, dict):
                    img_url = el.get("url") or el.get("src") or el.get("image") or ""
                if img_url:
                    if not img_url.startswith("http"):
                        img_url = _safe_urljoin(base_url, img_url)
                    images.append(img_url)
            if images:
                break
        elif isinstance(val, str) and val.strip():
            img_url = val.strip()
            if not img_url.startswith("http"):
                img_url = _safe_urljoin(base_url, img_url)
            images = [img_url]
            break

    # Brand
    brand = None
    for key in ("brand", "manufacturer", "brandName", "brand_name"):
        val = item.get(key)
        if isinstance(val, str) and val.strip():
            brand = val.strip()
            break
        if isinstance(val, dict):
            brand = (val.get("name") or val.get("label") or "").strip() or None
            break

    # SKU
    sku = None
    for key in ("sku", "currentSku", "productId", "product_id", "articleNumber", "id"):
        val = item.get(key)
        if val is not None:
            sku = str(val).strip()
            break

    # Category
    category_names: list[str] = []
    for key in ("categoryNames", "categories", "category"):
        val = item.get(key)
        if isinstance(val, list):
            category_names = [str(c) for c in val if c]
            break
        if isinstance(val, str) and val.strip():
            category_names = [val.strip()]
            break

    # Description
    description = None
    for key in ("description", "subHeader", "shortDescription", "summary"):
        val = item.get(key)
        if isinstance(val, str) and val.strip():
            description = val.strip()
            break

    # Require at least a title to be useful
    if not title:
        return None

    return {
        "title": title,
        "url": url,
        "brand": brand,
        "price_amount": price_amount,
        "price_original": None,
        "price_currency": "SEK",  # Default for Swedish retailers
        "images": images,
        "sku": sku,
        "category_names": category_names,
        "description": description,
    }


# ============================================================================
# UTILS
# ============================================================================

def _to_float(val: Any) -> float | None:
    """Safely convert a value to float."""
    if val is None:
        return None
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str):
        # Remove currency symbols, spaces, thousands separators
        cleaned = val.replace(" ", "").replace("\xa0", "").replace(",", ".")
        # Remove trailing currency codes
        for suffix in ("sek", "kr", ":-"):
            if cleaned.lower().endswith(suffix):
                cleaned = cleaned[: -len(suffix)]
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


# ============================================================================
# HANDLER REGISTRY
# ============================================================================

_HANDLERS: dict[str, Any] = {
    "INITIAL_DATA": _extract_chilli,
    "__INITIAL_STATE__": _extract_royaldesign,
    # Add more handlers here as new patterns are discovered
}
