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

    # Embedded JSON candidates: prioritise known IDs, then large JSON-like scripts
    embedded: list[dict] = []
    # Next.js
    nxt = soup.find("script", id="__NEXT_DATA__")
    if nxt and (nxt.string or "").strip().startswith("{"):
        data = _safe_json_loads(nxt.string or "")
        if isinstance(data, dict):
            embedded.append({"kind": "scriptTag", "id": "__NEXT_DATA__", "format": "json", "data": data})

    # Generic: large script tags that are valid JSON and contain product-ish keys
    for script in soup.find_all("script"):
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
        if len(embedded) >= 5:
            break

    return PageSignals(
        canonical_url=canonical,
        og_url=og_url,
        og_type=og_type,
        og_images=og_images[:10],
        jsonld_blocks=jsonld_blocks[:20],
        embedded_json_candidates=embedded,
    )

