from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse, urljoin

from app.extractor.money import parse_money_sv
from app.extractor.signals import extract_page_signals, PageSignals


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


def _extract_from_jsonld(product: dict) -> dict:
    title = (product.get("name") or "").strip()
    canonical = (product.get("url") or product.get("id") or "").strip()
    img = product.get("image")
    images: list[str] = []
    if isinstance(img, str) and img.strip():
        images = [img.strip()]
    elif isinstance(img, list):
        for el in img:
            if isinstance(el, str) and el.strip():
                images.append(el.strip())
            elif isinstance(el, dict) and el.get("url"):
                images.append(str(el.get("url")).strip())

    brand = None
    b = product.get("brand")
    if isinstance(b, dict):
        brand = (b.get("name") or "").strip() or None
    elif isinstance(b, str):
        brand = b.strip() or None

    desc = (product.get("description") or "").strip() or None

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
    elif isinstance(offers, list) and offers:
        o = offers[0]
        if isinstance(o, dict):
            currency = (o.get("priceCurrency") or "").strip() or None
            price_raw = o.get("price") or None

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


def _absolute(u: str | None, base: str) -> str | None:
    if not u:
        return None
    u = u.strip()
    if u.startswith("//"):
        return "https:" + u
    if u.startswith(("http://", "https://")):
        return u
    if u.startswith("/"):
        return urljoin(base.rstrip("/") + "/", u.lstrip("/"))
    return urljoin(base.rstrip("/") + "/", u)


def _normalize_images(imgs: list[str], *, base_url: str) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for u in imgs:
        uu = _absolute(u, base_url)
        if not uu:
            continue
        if uu not in seen:
            seen.add(uu)
            out.append(uu)
    return out


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
    imgs: list[str] = []
    if isinstance(value, str) and value.strip():
        imgs.append(value.strip())
    elif isinstance(value, list):
        for el in value:
            imgs.extend(_extract_images_from_any(el))
    elif isinstance(value, dict):
        for k in ("url", "src", "href"):
            if value.get(k) and isinstance(value.get(k), str):
                imgs.append(str(value.get(k)).strip())
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

            title = str(node.get("name") or node.get("title") or node.get("productName") or "").strip()
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

    title = str(best_node.get("name") or best_node.get("title") or best_node.get("productName") or "").strip()
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


def _score(*, title: bool, canonical: bool, images: bool, price_amount: bool, price_currency: bool) -> float:
    weights = {"title": 3, "canonical": 3, "images": 2, "price_amount": 2, "price_currency": 1}
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
    return got / total if total else 0.0


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
        title = (raw.get("title") or "").strip()
        images = [u for u in (raw.get("images") or []) if isinstance(u, str) and u.strip()]
        if not images and signals.og_images:
            images = signals.og_images
        images = _normalize_images(images, base_url=final_url)

        money = parse_money_sv(raw.get("priceRaw"))
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
            )
            return NormalizedProduct(
                retailer_id=source_id,
                retailer_domain=_domain(canonical2 or final_url),
                product_url=fetched_url,
                canonical_url=canonical2,
                title=title,
                price_amount=money.amount,
                price_currency=money.currency,
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
                debug={"strategy": "jsonld", **debug},
                dimensions_raw=raw.get("dimensionsRaw"),
                material_raw=raw.get("materialRaw"),
                color_raw=raw.get("colorRaw"),
            )

    # Embedded JSON (Next.js and generic blobs) – heuristic extraction
    embedded = _extract_from_embedded_json(signals, base_url=final_url)
    if embedded:
        canonical2 = (_absolute(embedded.get("canonicalUrl"), final_url) or canonical).strip()
        title = (embedded.get("title") or "").strip()
        images = _normalize_images([u for u in (embedded.get("images") or []) if isinstance(u, str)], base_url=final_url)
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
            )
            return NormalizedProduct(
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
                debug={"strategy": "embedded_json", "embeddedCandidates": len(signals.embedded_json_candidates), **debug},
                dimensions_raw=embedded.get("dimensionsRaw"),
                material_raw=embedded.get("materialRaw"),
                color_raw=embedded.get("colorRaw"),
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
                title = str(rr.output.get("title") or "").strip()
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
                    score = _score(
                        title=bool(title),
                        canonical=bool(canonical2),
                        images=bool(images),
                        price_amount=money.amount is not None,
                        price_currency=bool(price_currency or money.currency),
                    )
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
                    return NormalizedProduct(
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
        except Exception as e:
            warnings.append("recipe:runner_error")

    # DOM semantic fallback: rely on og tags + title from H1, and semantic meta tags for price.
    try:
        from bs4 import BeautifulSoup

        soup = BeautifulSoup(html, "lxml")
        h1 = soup.find("h1")
        title = (h1.get_text(strip=True) if h1 else "").strip()
        if not title:
            mt = soup.find("meta", property="og:title")
            title = (mt.get("content") if mt else "").strip()
        imgs = _normalize_images(list(signals.og_images), base_url=final_url)
        price_raw = None
        mp = soup.find("meta", property="product:price:amount")
        if mp and mp.get("content"):
            price_raw = mp.get("content")
        money = parse_money_sv(price_raw)
        if money.warnings:
            warnings.extend([f"price:{w}" for w in money.warnings if w != "missing"])

        # Guardrail: avoid treating category/listing pages as products.
        # For DOM-only extraction, require either og:type=product OR a parseable price.
        og_type = (signals.og_type or "").lower()
        if ("product" not in og_type) and (money.amount is None):
            return None

        errs = _validate_required(title=title, canonical_url=canonical)
        if not errs:
            from app.normalization import infer_color_from_title
            color_raw = infer_color_from_title(title)
            score = _score(
                title=bool(title),
                canonical=bool(canonical),
                images=bool(imgs),
                price_amount=money.amount is not None,
                price_currency=bool(money.currency),
            )
            return NormalizedProduct(
                retailer_id=source_id,
                retailer_domain=_domain(canonical),
                product_url=fetched_url,
                canonical_url=canonical,
                title=title,
                price_amount=money.amount,
                price_currency=money.currency,
                price_raw=money.raw or None,
                images=imgs,
                description=None,
                brand=None,
                extracted_at=extracted_at_iso,
                method="dom",
                recipe_id=None,
                recipe_version=None,
                completeness_score=score,
                warnings=warnings,
                debug={"strategy": "dom_semantic", **debug},
                dimensions_raw=None,
                material_raw=None,
                color_raw=color_raw,
            )
    except Exception:
        pass

    return None

