from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from bs4 import BeautifulSoup

from app.extractor.signals import extract_page_signals
from app.recipes.jsonpath import extract_jsonpath
from app.recipes.schema import validate_recipe_json
from app.recipes.transforms import ensure_absolute_urls, parse_money_number_sv


@dataclass(frozen=True)
class RecipeRunResult:
    ok: bool
    output: dict
    warnings: list[str]
    debug_trace: dict


def _set_nested(out: dict, dotted_key: str, value: Any) -> None:
    parts = dotted_key.split(".")
    cur = out
    for p in parts[:-1]:
        if p not in cur or not isinstance(cur[p], dict):
            cur[p] = {}
        cur = cur[p]
    cur[parts[-1]] = value


def _first_non_empty(values: list[Any]) -> Any | None:
    for v in values:
        if v is None:
            continue
        if isinstance(v, str) and not v.strip():
            continue
        if isinstance(v, list) and not v:
            continue
        return v
    return None


def _extract_dom_value(soup: BeautifulSoup, spec: dict) -> Any | None:
    sel = spec.get("selector")
    attr = spec.get("attr", "text")
    if not sel:
        return None
    el = soup.select_one(sel)
    if not el:
        return None
    if attr == "text":
        return el.get_text(strip=True)
    return el.get(attr)


def run_recipe_on_html(*, recipe: dict, html: str, final_url: str) -> RecipeRunResult:
    """
    Execute a deterministic recipe against a page.

    Output shape follows the spec’s NormalizedProduct-ish keys:
    title, canonicalUrl, images, price.raw, price.amount, price.currency, description, brand
    """
    validate_recipe_json(recipe)

    warnings: list[str] = []
    debug: dict = {"finalUrl": final_url, "strategies": []}
    out: dict = {}

    signals = extract_page_signals(html, final_url=final_url)
    soup = BeautifulSoup(html, "lxml")

    for strat in recipe.get("strategies", []):
        if not isinstance(strat, dict) or not strat.get("enabled", True):
            continue
        stype = strat.get("type")
        field_map = strat.get("fieldMap") or {}
        if not isinstance(field_map, dict):
            continue

        trace_entry: dict = {"name": strat.get("name"), "type": stype, "used": False, "fields": {}}

        candidate_out: dict = {}
        if stype == "jsonld":
            # Use the first Product JSON-LD object (cascade has a smarter picker; this is deterministic).
            product_obj = None
            for b in signals.jsonld_blocks:
                if isinstance(b, dict) and b.get("@type") == "Product":
                    product_obj = b
                    break
                if isinstance(b, list):
                    for el in b:
                        if isinstance(el, dict) and el.get("@type") == "Product":
                            product_obj = el
                            break
                if product_obj is not None:
                    break
            if product_obj is None:
                debug["strategies"].append(trace_entry)
                continue
            for field, paths in field_map.items():
                vals: list[Any] = []
                for p in paths if isinstance(paths, list) else [paths]:
                    if isinstance(p, str) and p.startswith("$"):
                        vals.extend(extract_jsonpath(product_obj, p))
                if field == "images":
                    imgs = [str(v).strip() for v in vals if isinstance(v, str) and str(v).strip()]
                    if imgs:
                        candidate_out["images"] = imgs
                        trace_entry["fields"][field] = {"source": "jsonpath", "picked": True, "count": len(imgs)}
                else:
                    v = _first_non_empty(vals)
                    if v is not None:
                        _set_nested(candidate_out, field, v)
                        trace_entry["fields"][field] = {"source": "jsonpath", "pathCount": len(paths), "picked": True}

        elif stype == "embedded_json":
            # Sources: scriptTag selectors (default to __NEXT_DATA__ if not specified)
            sources = strat.get("sources") or [{"kind": "scriptTag", "selector": "script#__NEXT_DATA__", "format": "json"}]
            payloads: list[Any] = []
            for src in sources:
                if not isinstance(src, dict) or src.get("kind") != "scriptTag":
                    continue
                sel = src.get("selector")
                if not sel:
                    continue
                el = soup.select_one(sel)
                if not el:
                    continue
                txt = (el.string or "").strip()
                if not txt:
                    continue
                try:
                    payloads.append(json.loads(txt))
                except Exception:
                    continue
            if not payloads:
                debug["strategies"].append(trace_entry)
                continue

            for field, paths in field_map.items():
                vals: list[Any] = []
                for payload in payloads:
                    for p in paths if isinstance(paths, list) else [paths]:
                        if isinstance(p, str) and p.startswith("$"):
                            vals.extend(extract_jsonpath(payload, p))
                if field == "images":
                    imgs = [str(v).strip() for v in vals if isinstance(v, str) and str(v).strip()]
                    if imgs:
                        candidate_out["images"] = imgs
                        trace_entry["fields"][field] = {"source": "jsonpath", "picked": True, "count": len(imgs)}
                else:
                    v = _first_non_empty(vals)
                    if v is not None:
                        _set_nested(candidate_out, field, v)
                        trace_entry["fields"][field] = {"source": "jsonpath", "picked": True}

        elif stype == "dom":
            for field, specs in field_map.items():
                vals: list[Any] = []
                for spec in specs if isinstance(specs, list) else [specs]:
                    if isinstance(spec, dict) and spec.get("selector"):
                        vals.append(_extract_dom_value(soup, spec))
                    elif isinstance(spec, str) and spec.startswith("$"):
                        # allow JSONPath against page signals for convenience
                        vals.extend(extract_jsonpath({"signals": signals.__dict__}, spec))
                v = _first_non_empty(vals)
                if v is not None:
                    _set_nested(candidate_out, field, v)
                    trace_entry["fields"][field] = {"source": "dom", "picked": True}

        else:
            debug["strategies"].append(trace_entry)
            continue

        # Transforms (minimal MVP)
        transforms = strat.get("transforms") or {}
        if isinstance(transforms, dict):
            # price.amount from price.raw
            for t in transforms.get("price.amount", []) if isinstance(transforms.get("price.amount"), list) else []:
                if not isinstance(t, dict):
                    continue
                if t.get("op") == "parseMoneyNumber" and t.get("from") == "price.raw":
                    raw = (((candidate_out.get("price") or {}) if isinstance(candidate_out.get("price"), dict) else {}).get("raw"))
                    amt, cur, warns, raw_s = parse_money_number_sv(raw)
                    if amt is not None:
                        candidate_out.setdefault("price", {})["amount"] = amt
                    if cur:
                        candidate_out.setdefault("price", {})["currency"] = cur
                    if warns:
                        warnings.extend([f"price:{w}" for w in warns if w != "missing"])
                    if raw_s and candidate_out.get("price") and isinstance(candidate_out["price"], dict):
                        candidate_out["price"]["raw"] = raw_s

            # images absolute
            for t in transforms.get("images", []) if isinstance(transforms.get("images"), list) else []:
                if not isinstance(t, dict):
                    continue
                if t.get("op") == "ensureAbsoluteUrls":
                    imgs = candidate_out.get("images")
                    if isinstance(imgs, list):
                        candidate_out["images"] = ensure_absolute_urls([str(x) for x in imgs], base_url=final_url)

        # Merge into out (first strategy that satisfies required validators wins)
        merged = {**out, **candidate_out}
        # Basic validators: title and canonicalUrl required (hard invariants)
        title_ok = bool(str(merged.get("title") or "").strip())
        canon_ok = bool(str(merged.get("canonicalUrl") or "").strip().startswith(("http://", "https://")))
        trace_entry["used"] = True
        debug["strategies"].append(trace_entry)

        if title_ok and canon_ok:
            out = merged
            break

    ok = bool(str(out.get("title") or "").strip()) and bool(
        str(out.get("canonicalUrl") or "").strip().startswith(("http://", "https://"))
    )

    return RecipeRunResult(ok=ok, output=out, warnings=warnings, debug_trace=debug)

