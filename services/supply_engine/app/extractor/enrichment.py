"""
EPIC B: Metadata Enrichment – extract breadcrumbs, facets, variants, identity keys, and offer data.

This module enriches the basic NormalizedProduct with additional structured fields
for taxonomy, identity, and offer details. It runs AFTER the main cascade extraction
and adds fields without replacing existing ones.

B1: Breadcrumbs + category labels
B2: Facet dictionaries
B3: Variant matrix (color/material/size)
B4: Identity keys (sku/mpn/gtin)
B5: Offer data (stock, old price, discount)
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any


@dataclass
class EnrichedMetadata:
    """Additional metadata extracted from product pages (EPIC B)."""

    # B1: Breadcrumbs + category
    breadcrumbs: list[str] = field(default_factory=list)
    retailer_category_id: str | None = None
    retailer_category_label: str | None = None
    product_type: str | None = None  # Normalized: "sofa", "armchair", "table", etc.

    # B2: Facets (key-value pairs from PDP)
    facets: dict[str, str] = field(default_factory=dict)

    # B3: Variants
    variants: list[dict[str, Any]] = field(default_factory=list)
    # Each variant: {"color": str, "material": str, "size": str, "sku": str, "price": float, "available": bool}

    # B4: Identity keys
    sku: str | None = None
    mpn: str | None = None
    gtin: str | None = None  # EAN/UPC/GTIN
    model_name: str | None = None
    model_number: str | None = None

    # B5: Offer data
    price_original: float | None = None  # List/compare-at price before discount
    discount_pct: float | None = None
    availability: str | None = None  # "in_stock", "out_of_stock", "preorder", "unknown"
    delivery_eta: str | None = None  # Raw text like "2-5 dagar"
    shipping_cost: float | None = None

    # Provenance
    enrichment_version: int = 1
    evidence_sources: list[str] = field(default_factory=list)


# ============================================================================
# B1: BREADCRUMBS + CATEGORY EXTRACTION
# ============================================================================

def _extract_breadcrumbs_jsonld(jsonld_blocks: list[Any]) -> list[str]:
    """Extract breadcrumbs from JSON-LD BreadcrumbList."""
    for block in jsonld_blocks:
        items = _find_breadcrumb_list(block)
        if items:
            return items
    return []


def _find_breadcrumb_list(obj: Any) -> list[str]:
    """Recursively find BreadcrumbList in JSON-LD."""
    if isinstance(obj, dict):
        t = obj.get("@type", "")
        types = [t] if isinstance(t, str) else (t if isinstance(t, list) else [])
        if "BreadcrumbList" in types:
            items = obj.get("itemListElement", [])
            if isinstance(items, list):
                sorted_items = sorted(items, key=lambda x: x.get("position", 0) if isinstance(x, dict) else 0)
                return [
                    str(item.get("name") or (item.get("item", {}).get("name", "") if isinstance(item.get("item"), dict) else "")).strip()
                    for item in sorted_items
                    if isinstance(item, dict) and (item.get("name") or (isinstance(item.get("item"), dict) and item["item"].get("name")))
                ]
        # Check @graph
        graph = obj.get("@graph", [])
        if isinstance(graph, list):
            for g in graph:
                result = _find_breadcrumb_list(g)
                if result:
                    return result
    elif isinstance(obj, list):
        for item in obj:
            result = _find_breadcrumb_list(item)
            if result:
                return result
    return []


def _extract_breadcrumbs_dom(soup: Any) -> list[str]:
    """Extract breadcrumbs from HTML DOM (common patterns)."""
    # Try common breadcrumb selectors
    selectors = [
        "nav[aria-label*='breadcrumb'] a",
        "nav[aria-label*='Breadcrumb'] a",
        ".breadcrumb a", ".breadcrumbs a",
        "[itemtype*='BreadcrumbList'] [itemprop='name']",
        "ol.breadcrumb li a", "ul.breadcrumb li a",
        ".breadcrumb-nav a",
    ]
    for sel in selectors:
        links = soup.select(sel)
        if links:
            crumbs = [link.get_text(strip=True) for link in links if link.get_text(strip=True)]
            if len(crumbs) >= 2:
                return crumbs

    # Fallback: look for structured data in nav elements
    for nav in soup.find_all("nav"):
        aria = (nav.get("aria-label") or "").lower()
        if "bread" in aria or "crumb" in aria:
            texts = [a.get_text(strip=True) for a in nav.find_all("a")]
            if texts:
                return texts

    return []


# Product type inference from breadcrumbs and title
_PRODUCT_TYPE_MAP = {
    "sofa": ["soffa", "soffor", "sofa", "sofas", "couch"],
    "armchair": ["fåtölj", "fåtöljer", "armchair", "armchairs", "karmstol"],
    "bed_sofa": ["bäddsoffa", "bäddsoffor", "sleeper", "sofa bed"],
    "corner_sofa": ["hörnsoffa", "hörnsoffor", "corner sofa", "divansoffa"],
    "dining_table": ["matbord", "dining table"],
    "coffee_table": ["soffbord", "coffee table"],
    "bookshelf": ["bokhylla", "bookshelf", "bookcase"],
    "desk": ["skrivbord", "desk"],
    "bed": ["säng", "sängar", "bed", "beds"],
    "rug": ["matta", "mattor", "rug", "rugs"],
    "lamp": ["lampa", "lampor", "lamp", "light", "lighting"],
    "chair": ["stol", "stolar", "chair", "chairs"],
    "storage": ["förvaring", "storage", "byrå", "dresser", "sideboard"],
    "outdoor": ["utomhus", "outdoor", "trädgård", "garden"],
}


def _infer_product_type(breadcrumbs: list[str], title: str) -> str | None:
    """Infer normalized product type from breadcrumbs and title."""
    text = " ".join(breadcrumbs).lower() + " " + title.lower()
    for product_type, keywords in _PRODUCT_TYPE_MAP.items():
        if any(kw in text for kw in keywords):
            return product_type
    return None


# ============================================================================
# B2: FACET EXTRACTION
# ============================================================================

def _extract_facets_from_dom(soup: Any) -> dict[str, str]:
    """Extract product facets/specifications from common PDP patterns."""
    facets: dict[str, str] = {}

    # Pattern 1: Definition lists (dt/dd)
    for dl in soup.find_all("dl"):
        dts = dl.find_all("dt")
        dds = dl.find_all("dd")
        for dt, dd in zip(dts, dds):
            key = dt.get_text(strip=True)
            val = dd.get_text(strip=True)
            if key and val and len(key) < 50 and len(val) < 200:
                facets[key] = val

    # Pattern 2: Table rows (th/td or td/td)
    for table in soup.find_all("table"):
        classes = " ".join(table.get("class", []))
        if any(kw in classes.lower() for kw in ("spec", "detail", "info", "attribute", "property", "fact")):
            for row in table.find_all("tr"):
                cells = row.find_all(["th", "td"])
                if len(cells) >= 2:
                    key = cells[0].get_text(strip=True)
                    val = cells[1].get_text(strip=True)
                    if key and val and len(key) < 50 and len(val) < 200:
                        facets[key] = val

    # Pattern 3: Labeled spans/divs (common in React/Next.js sites)
    spec_selectors = [
        ".product-specifications li",
        ".product-details li",
        ".product-info li",
        "[data-testid*='spec'] li",
        ".specification-row",
    ]
    for sel in spec_selectors:
        for item in soup.select(sel):
            text = item.get_text(strip=True)
            # Try to split on colon
            if ":" in text:
                parts = text.split(":", 1)
                key, val = parts[0].strip(), parts[1].strip()
                if key and val and len(key) < 50 and len(val) < 200:
                    facets[key] = val

    return facets


def _extract_facets_from_jsonld(product: dict) -> dict[str, str]:
    """Extract facets from JSON-LD additionalProperty fields."""
    facets: dict[str, str] = {}
    add_props = product.get("additionalProperty", [])
    if isinstance(add_props, dict):
        add_props = [add_props]
    if not isinstance(add_props, list):
        return facets

    for prop in add_props:
        if not isinstance(prop, dict):
            continue
        name = str(prop.get("name") or prop.get("propertyID") or "").strip()
        value = str(prop.get("value") or "").strip()
        if name and value:
            facets[name] = value

    return facets


# ============================================================================
# B3: VARIANT EXTRACTION
# ============================================================================

def _extract_variants_jsonld(product: dict) -> list[dict[str, Any]]:
    """Extract variant information from JSON-LD offers."""
    variants: list[dict[str, Any]] = []

    # Check for hasVariant or model patterns
    has_variants = product.get("hasVariant") or product.get("model")
    if isinstance(has_variants, list):
        for v in has_variants:
            if not isinstance(v, dict):
                continue
            variant: dict[str, Any] = {}
            variant["name"] = str(v.get("name") or "").strip() or None
            variant["sku"] = str(v.get("sku") or "").strip() or None
            variant["color"] = str(v.get("color") or "").strip() or None
            variant["material"] = str(v.get("material") or "").strip() or None

            # Offer inside variant
            offers = v.get("offers")
            if isinstance(offers, dict):
                variant["price"] = offers.get("price")
                variant["available"] = (offers.get("availability") or "").lower() != "outofstock"
            elif isinstance(offers, list) and offers:
                o = offers[0]
                if isinstance(o, dict):
                    variant["price"] = o.get("price")
                    variant["available"] = (o.get("availability") or "").lower() != "outofstock"

            variants.append(variant)

    return variants


def _extract_variants_embedded(node: dict) -> list[dict[str, Any]]:
    """Extract variants from embedded JSON product nodes."""
    variants: list[dict[str, Any]] = []

    for key in ("variants", "skus", "options", "configurations"):
        raw = node.get(key)
        if not isinstance(raw, list):
            continue
        for v in raw:
            if not isinstance(v, dict):
                continue
            variant: dict[str, Any] = {}
            variant["name"] = str(v.get("name") or v.get("label") or "").strip() or None
            variant["sku"] = str(v.get("sku") or v.get("articleNumber") or "").strip() or None
            variant["color"] = str(v.get("color") or v.get("colorName") or "").strip() or None
            variant["material"] = str(v.get("material") or v.get("fabric") or "").strip() or None
            variant["price"] = v.get("price") or v.get("currentPrice")
            variant["available"] = v.get("inStock", v.get("available", True))
            variants.append(variant)
        if variants:
            break

    return variants


# ============================================================================
# B4: IDENTITY KEYS
# ============================================================================

def _extract_identity_jsonld(product: dict) -> dict[str, str | None]:
    """Extract identity keys from JSON-LD Product."""
    return {
        "sku": str(product.get("sku") or "").strip() or None,
        "mpn": str(product.get("mpn") or "").strip() or None,
        "gtin": (
            str(product.get("gtin") or product.get("gtin13") or product.get("gtin14")
                or product.get("gtin8") or product.get("gtin12") or "").strip() or None
        ),
        "model_name": str(product.get("model") or "").strip() or None if isinstance(product.get("model"), str) else None,
        "model_number": str(product.get("productID") or product.get("identifier") or "").strip() or None,
    }


def _extract_identity_embedded(node: dict) -> dict[str, str | None]:
    """Extract identity keys from embedded JSON."""
    return {
        "sku": str(node.get("sku") or node.get("articleNumber") or node.get("productId") or "").strip() or None,
        "mpn": str(node.get("mpn") or node.get("manufacturerPartNumber") or "").strip() or None,
        "gtin": str(node.get("gtin") or node.get("ean") or node.get("upc") or node.get("barcode") or "").strip() or None,
        "model_name": str(node.get("modelName") or node.get("model") or "").strip() or None,
        "model_number": str(node.get("modelNumber") or node.get("productCode") or "").strip() or None,
    }


def _extract_identity_dom(soup: Any) -> dict[str, str | None]:
    """Extract identity keys from DOM meta tags and microdata."""
    identity: dict[str, str | None] = {
        "sku": None, "mpn": None, "gtin": None, "model_name": None, "model_number": None,
    }

    # Schema.org microdata
    for prop, key in [("sku", "sku"), ("mpn", "mpn"), ("gtin13", "gtin"), ("gtin", "gtin"), ("productID", "model_number")]:
        el = soup.find(attrs={"itemprop": prop})
        if el:
            val = (el.get("content") or el.get_text(strip=True) or "").strip()
            if val and identity[key] is None:
                identity[key] = val

    # Meta tags
    for name, key in [("product:retailer_item_id", "sku"), ("product:isbn", "gtin")]:
        meta = soup.find("meta", property=name) or soup.find("meta", attrs={"name": name})
        if meta and meta.get("content"):
            val = meta["content"].strip()
            if val and identity[key] is None:
                identity[key] = val

    return identity


# ============================================================================
# B5: OFFER DATA
# ============================================================================

def _extract_offer_jsonld(product: dict) -> dict[str, Any]:
    """Extract detailed offer data from JSON-LD."""
    offer: dict[str, Any] = {
        "price_original": None,
        "discount_pct": None,
        "availability": "unknown",
        "delivery_eta": None,
        "shipping_cost": None,
    }

    offers_raw = product.get("offers")
    if isinstance(offers_raw, list) and offers_raw:
        offers_raw = offers_raw[0]
    if not isinstance(offers_raw, dict):
        return offer

    # Availability
    avail = (offers_raw.get("availability") or "").lower()
    if "instock" in avail or "instoreonly" in avail:
        offer["availability"] = "in_stock"
    elif "outofstock" in avail:
        offer["availability"] = "out_of_stock"
    elif "preorder" in avail or "presale" in avail:
        offer["availability"] = "preorder"
    elif "backorder" in avail:
        offer["availability"] = "backorder"

    # Original price (compare-at / list price)
    price_spec = offers_raw.get("priceSpecification")
    if isinstance(price_spec, dict):
        list_price = price_spec.get("price")
    else:
        list_price = None

    # Try to find original/compare price in various locations
    for key in ("highPrice", "priceValidUntil"):  # highPrice in AggregateOffer
        pass  # These aren't original prices

    # Shipping
    shipping = offers_raw.get("shippingDetails") or offers_raw.get("deliveryLeadTime")
    if isinstance(shipping, dict):
        cost = shipping.get("shippingRate", {}).get("value") if isinstance(shipping.get("shippingRate"), dict) else None
        if cost is not None:
            try:
                offer["shipping_cost"] = float(cost)
            except (ValueError, TypeError):
                pass
        lead = shipping.get("deliveryLeadTime") or shipping.get("transitTime")
        if isinstance(lead, dict):
            min_d = lead.get("minValue", "")
            max_d = lead.get("maxValue", "")
            offer["delivery_eta"] = f"{min_d}-{max_d} days" if min_d and max_d else None
        elif isinstance(lead, str):
            offer["delivery_eta"] = lead.strip() or None

    return offer


def _extract_offer_embedded(node: dict) -> dict[str, Any]:
    """Extract offer data from embedded JSON."""
    offer: dict[str, Any] = {
        "price_original": None,
        "discount_pct": None,
        "availability": "unknown",
        "delivery_eta": None,
        "shipping_cost": None,
    }

    # Original price
    for key in ("originalPrice", "compareAtPrice", "listPrice", "priceOriginal", "regularPrice", "wasPrice"):
        val = node.get(key)
        if val is not None:
            try:
                offer["price_original"] = float(val)
                break
            except (ValueError, TypeError):
                pass

    # Current price for discount calc
    current = node.get("price") or node.get("currentPrice") or node.get("salePrice")
    if offer["price_original"] and current:
        try:
            current_f = float(current)
            orig_f = offer["price_original"]
            if orig_f > current_f > 0:
                offer["discount_pct"] = round((1 - current_f / orig_f) * 100, 1)
        except (ValueError, TypeError):
            pass

    # Availability
    for key in ("inStock", "available", "availability"):
        val = node.get(key)
        if val is not None:
            if isinstance(val, bool):
                offer["availability"] = "in_stock" if val else "out_of_stock"
            elif isinstance(val, str):
                lower = val.lower()
                if "in" in lower and "stock" in lower:
                    offer["availability"] = "in_stock"
                elif "out" in lower:
                    offer["availability"] = "out_of_stock"
            break

    # Delivery
    for key in ("deliveryTime", "deliveryEta", "shippingTime", "leadTime"):
        val = node.get(key)
        if val and isinstance(val, str):
            offer["delivery_eta"] = val.strip()
            break

    # Shipping cost
    for key in ("shippingCost", "shippingPrice", "deliveryCost"):
        val = node.get(key)
        if val is not None:
            try:
                offer["shipping_cost"] = float(val)
                break
            except (ValueError, TypeError):
                pass

    return offer


def _extract_offer_dom(soup: Any) -> dict[str, Any]:
    """Extract offer data from DOM (meta tags and common patterns)."""
    offer: dict[str, Any] = {
        "price_original": None,
        "discount_pct": None,
        "availability": "unknown",
        "delivery_eta": None,
        "shipping_cost": None,
    }

    # Meta: availability
    avail_meta = soup.find("meta", property="product:availability")
    if avail_meta and avail_meta.get("content"):
        val = avail_meta["content"].lower()
        if "instock" in val or "in stock" in val:
            offer["availability"] = "in_stock"
        elif "oos" in val or "out" in val:
            offer["availability"] = "out_of_stock"

    # Meta: original price
    orig_meta = soup.find("meta", property="product:price:standard_amount")
    if orig_meta and orig_meta.get("content"):
        try:
            offer["price_original"] = float(orig_meta["content"])
        except (ValueError, TypeError):
            pass

    # DOM: crossed-out price
    for sel in (".original-price", ".was-price", ".compare-price", "del", "s.price", ".price--compare"):
        el = soup.select_one(sel)
        if el:
            text = re.sub(r"[^\d.,]", "", el.get_text(strip=True)).replace(",", ".")
            if text:
                try:
                    offer["price_original"] = float(text)
                    break
                except (ValueError, TypeError):
                    pass

    # DOM: delivery info
    for sel in (".delivery-info", ".shipping-info", ".delivery-time", "[data-testid*='delivery']"):
        el = soup.select_one(sel)
        if el:
            text = el.get_text(strip=True)
            if text and len(text) < 100:
                offer["delivery_eta"] = text
                break

    return offer


# ============================================================================
# MAIN ENRICHMENT FUNCTION
# ============================================================================

def enrich_product(
    *,
    jsonld_product: dict | None,
    embedded_node: dict | None,
    soup: Any | None,
    jsonld_blocks: list[Any] | None = None,
    title: str = "",
    current_price: float | None = None,
) -> EnrichedMetadata:
    """
    Run all enrichment extractors and merge results with priority:
    JSON-LD > Embedded JSON > DOM.

    This function is designed to be called after the main extraction cascade,
    using the same parsed data structures.
    """
    meta = EnrichedMetadata()

    # B1: Breadcrumbs + category
    if jsonld_blocks:
        meta.breadcrumbs = _extract_breadcrumbs_jsonld(jsonld_blocks)
        if meta.breadcrumbs:
            meta.evidence_sources.append("breadcrumbs:jsonld")
    if not meta.breadcrumbs and soup:
        meta.breadcrumbs = _extract_breadcrumbs_dom(soup)
        if meta.breadcrumbs:
            meta.evidence_sources.append("breadcrumbs:dom")

    # Infer product type from breadcrumbs + title
    meta.product_type = _infer_product_type(meta.breadcrumbs, title)
    if meta.breadcrumbs:
        # Last breadcrumb is usually the most specific category
        meta.retailer_category_label = meta.breadcrumbs[-1] if meta.breadcrumbs else None

    # B2: Facets
    if jsonld_product:
        meta.facets = _extract_facets_from_jsonld(jsonld_product)
        if meta.facets:
            meta.evidence_sources.append("facets:jsonld")
    if soup:
        dom_facets = _extract_facets_from_dom(soup)
        # Merge: don't overwrite JSON-LD facets
        for k, v in dom_facets.items():
            if k not in meta.facets:
                meta.facets[k] = v
        if dom_facets:
            meta.evidence_sources.append("facets:dom")

    # B3: Variants
    if jsonld_product:
        meta.variants = _extract_variants_jsonld(jsonld_product)
        if meta.variants:
            meta.evidence_sources.append("variants:jsonld")
    if not meta.variants and embedded_node:
        meta.variants = _extract_variants_embedded(embedded_node)
        if meta.variants:
            meta.evidence_sources.append("variants:embedded")

    # B4: Identity keys
    identity: dict[str, str | None] = {}
    if jsonld_product:
        identity = _extract_identity_jsonld(jsonld_product)
        if any(v for v in identity.values()):
            meta.evidence_sources.append("identity:jsonld")
    if embedded_node:
        emb_id = _extract_identity_embedded(embedded_node)
        for k, v in emb_id.items():
            if v and not identity.get(k):
                identity[k] = v
        if any(v for v in emb_id.values()):
            meta.evidence_sources.append("identity:embedded")
    if soup:
        dom_id = _extract_identity_dom(soup)
        for k, v in dom_id.items():
            if v and not identity.get(k):
                identity[k] = v
        if any(v for v in dom_id.values()):
            meta.evidence_sources.append("identity:dom")

    meta.sku = identity.get("sku")
    meta.mpn = identity.get("mpn")
    meta.gtin = identity.get("gtin")
    meta.model_name = identity.get("model_name")
    meta.model_number = identity.get("model_number")

    # B5: Offer data
    offer: dict[str, Any] = {}
    if jsonld_product:
        offer = _extract_offer_jsonld(jsonld_product)
        if offer.get("availability") != "unknown":
            meta.evidence_sources.append("offer:jsonld")
    if embedded_node:
        emb_offer = _extract_offer_embedded(embedded_node)
        for k, v in emb_offer.items():
            if v is not None and (offer.get(k) is None or offer.get(k) == "unknown"):
                offer[k] = v
        meta.evidence_sources.append("offer:embedded")
    if soup:
        dom_offer = _extract_offer_dom(soup)
        for k, v in dom_offer.items():
            if v is not None and (offer.get(k) is None or offer.get(k) == "unknown"):
                offer[k] = v

    meta.price_original = offer.get("price_original")
    meta.availability = offer.get("availability", "unknown")
    meta.delivery_eta = offer.get("delivery_eta")
    meta.shipping_cost = offer.get("shipping_cost")

    # Calculate discount if we have original + current price
    if meta.price_original and current_price and meta.price_original > current_price > 0:
        meta.discount_pct = round((1 - current_price / meta.price_original) * 100, 1)
    elif offer.get("discount_pct"):
        meta.discount_pct = offer["discount_pct"]

    return meta
