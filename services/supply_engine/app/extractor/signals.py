from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse, urljoin

from bs4 import BeautifulSoup


@dataclass(frozen=True)
class PageSignals:
    canonical_url: str | None
    og_url: str | None
    og_type: str | None
    og_images: list[str]
    jsonld_blocks: list[Any]
    embedded_json_candidates: list[dict]


def _safe_json_loads(s: str) -> Any | None:
    try:
        return json.loads(s)
    except Exception:
        return None


def _absolute(url: str | None, base: str) -> str | None:
    if not url:
        return None
    url = url.strip()
    if url.startswith("//"):
        return "https:" + url
    if url.startswith("http://") or url.startswith("https://"):
        return url
    if url.startswith("/"):
        return urljoin(base.rstrip("/") + "/", url.lstrip("/"))
    return urljoin(base.rstrip("/") + "/", url)


def extract_page_signals(html: str, *, final_url: str) -> PageSignals:
    soup = BeautifulSoup(html, "lxml")

    canonical = None
    ln = soup.find("link", rel=lambda x: x and "canonical" in x.lower())
    if ln and ln.get("href"):
        canonical = _absolute(ln.get("href"), final_url)

    og_url = None
    og_type = None
    og_images: list[str] = []
    for meta in soup.find_all("meta"):
        prop = (meta.get("property") or meta.get("name") or "").strip().lower()
        if prop == "og:url" and meta.get("content"):
            og_url = _absolute(meta.get("content"), final_url)
        if prop == "og:type" and meta.get("content"):
            og_type = meta.get("content").strip()
        if prop == "og:image" and meta.get("content"):
            u = _absolute(meta.get("content"), final_url)
            if u:
                og_images.append(u)

    jsonld_blocks: list[Any] = []
    for script in soup.find_all("script", type=lambda x: x and "ld+json" in x):
        data = _safe_json_loads(script.string or "")
        if data is not None:
            jsonld_blocks.append(data)

    # Embedded JSON candidates: prioritise known IDs, then window.* state,
    # then large JSON-like scripts.
    embedded: list[dict] = []

    # Next.js: <script id="__NEXT_DATA__" type="application/json">{...}</script>
    nxt = soup.find("script", id="__NEXT_DATA__")
    if nxt and (nxt.string or "").strip().startswith("{"):
        data = _safe_json_loads(nxt.string or "")
        if isinstance(data, dict):
            embedded.append({"kind": "scriptTag", "id": "__NEXT_DATA__", "format": "json", "data": data})

    # ── Window-level JavaScript state variables ──
    # Many modern e-commerce sites embed the full product catalog in the
    # initial HTML inside a window.* variable (NOT a JSON script tag).
    # We scan all <script> blocks for known patterns.
    _WINDOW_STATE_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
        # Chilli: window.INITIAL_DATA = JSON.parse('...')
        ("INITIAL_DATA", re.compile(
            r"window\.INITIAL_DATA\s*=\s*JSON\.parse\(\s*'(.+?)'\s*\)",
            re.DOTALL,
        )),
        # RoyalDesign & others: window.__INITIAL_STATE__ = {...};
        ("__INITIAL_STATE__", re.compile(
            r"window\.__INITIAL_STATE__\s*=\s*(\{.+?\});\s*(?:</script>|$)",
            re.DOTALL,
        )),
        # Nuxt.js: window.__NUXT__ = {...};
        ("__NUXT__", re.compile(
            r"window\.__NUXT__\s*=\s*(\{.+?\});\s*(?:</script>|$)",
            re.DOTALL,
        )),
        # Generic: window.__PRELOADED_STATE__ = {...};
        ("__PRELOADED_STATE__", re.compile(
            r"window\.__PRELOADED_STATE__\s*=\s*(\{.+?\});\s*(?:</script>|$)",
            re.DOTALL,
        )),
    ]

    # Build a single text of all script bodies to run regex against.
    # (Cheaper than running per-script; we only care about presence.)
    all_script_text = "\n".join(
        (script.string or "")
        for script in soup.find_all("script")
        if script.string and len(script.string) > 500
    )

    for var_name, pattern in _WINDOW_STATE_PATTERNS:
        if len(embedded) >= 8:
            break
        m = pattern.search(all_script_text)
        if not m:
            continue
        raw_json = m.group(1)
        # INITIAL_DATA uses JSON.parse() with escaped single quotes
        if var_name == "INITIAL_DATA":
            raw_json = raw_json.replace("\\'", "'").replace('\\"', '"').replace("\\\\", "\\")
        data = _safe_json_loads(raw_json)
        if isinstance(data, dict):
            embedded.append({
                "kind": "windowState",
                "id": var_name,
                "format": "js_assignment",
                "data": data,
            })

    # ── Next.js App Router (RSC streaming) ──
    # Next.js 14/15 App Router streams data via self.__next_f.push([1,"..."])
    # inside regular <script> tags.  JSON-LD and product data are embedded
    # as escaped strings in these payloads.
    _RSC_PUSH_RE = re.compile(
        r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)',
        re.DOTALL,
    )
    rsc_payloads_found = False
    for script in soup.find_all("script"):
        txt = script.string or ""
        if "self.__next_f.push" not in txt:
            continue
        for m in _RSC_PUSH_RE.finditer(txt):
            raw = m.group(1)
            # Un-escape the JSON string (it's double-escaped)
            try:
                decoded: str = json.loads(f'"{raw}"')
            except Exception:
                continue
            decoded_stripped = decoded.strip()
            # Check if this chunk is a standalone JSON-LD object
            if decoded_stripped.startswith("{") and '"@type"' in decoded_stripped:
                obj = _safe_json_loads(decoded_stripped)
                if isinstance(obj, dict) and obj.get("@type"):
                    jsonld_blocks.append(obj)
                    rsc_payloads_found = True

    # Generic: large script tags that are valid JSON and contain product-ish keys
    for script in soup.find_all("script"):
        if len(embedded) >= 8:
            break
        txt = (script.string or "").strip()
        if len(txt) < 2000:
            continue
        if not (txt.startswith("{") or txt.startswith("[")):
            continue
        data = _safe_json_loads(txt)
        if not isinstance(data, (dict, list)):
            continue
        # Heuristic key scan (cheap)
        blob = txt.lower()
        if not any(k in blob for k in ("price", "product", "images", "sku", "variant", "name")):
            continue
        embedded.append({"kind": "scriptTag", "id": script.get("id"), "format": "json", "data": data})

    return PageSignals(
        canonical_url=canonical,
        og_url=og_url,
        og_type=og_type,
        og_images=og_images[:10],
        jsonld_blocks=jsonld_blocks[:20],
        embedded_json_candidates=embedded,
    )

