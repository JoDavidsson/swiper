from __future__ import annotations

import json
import re
from typing import Any


def _iter_json_nodes(obj: Any):
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            if isinstance(v, (dict, list)):
                yield from _iter_json_nodes(v)
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, (dict, list)):
                yield from _iter_json_nodes(item)


def _has_jsonld_product(soup: Any) -> bool:
    for script in soup.find_all("script", attrs={"type": re.compile("ld\\+json", re.IGNORECASE)}):
        raw = (script.string or script.get_text() or "").strip()
        if not raw:
            continue
        try:
            data = json.loads(raw)
        except Exception:
            continue
        for node in _iter_json_nodes(data):
            if not isinstance(node, dict):
                continue
            t = node.get("@type")
            if isinstance(t, str) and t.lower() == "product":
                return True
            if isinstance(t, list) and any(str(x).lower() == "product" for x in t):
                return True
    return False


def is_waf_block_page(html: str) -> bool:
    """Detect WAF/CDN block pages (Cloudflare, Akamai, etc.).

    These pages return HTTP 200 but contain a challenge or block message
    instead of the real content.  Browser fallback should always be
    attempted when a WAF block is detected.
    """
    if not html:
        return False

    lower = html[:8_000].lower()  # Only scan the top of the page

    # Cloudflare challenge / block
    if "cloudflare" in lower and (
        "you have been blocked" in lower
        or "attention required" in lower
        or "checking your browser" in lower
        or "cf-challenge" in lower
        or "cf-error-details" in lower
    ):
        return True

    # Akamai bot manager
    if "akamai" in lower and "access denied" in lower:
        return True

    # PerimeterX / HUMAN
    if "perimeterx" in lower or "px-captcha" in lower:
        return True

    # DataDome
    if "datadome" in lower and "captcha" in lower:
        return True

    return False


def needs_browser_render(html: str) -> bool:
    """
    Heuristic detector for client-side rendered shells and WAF block pages.

    Returns True when:
    - A WAF/CDN block page is detected (immediate True), OR
    - 2+ independent signals indicate the raw HTTP response likely needs
      JS execution to expose product data.
    """
    if not html:
        return False

    # Fast-path: WAF block pages should always trigger browser fallback.
    if is_waf_block_page(html):
        return True

    try:
        from bs4 import BeautifulSoup
    except Exception:
        return False

    soup = BeautifulSoup(html, "lxml")
    score = 0

    # Signal 1: Minimal body payload once scripts/styles are removed.
    body = soup.body or soup
    body_clone = BeautifulSoup(str(body), "lxml")
    for tag in body_clone(["script", "style", "noscript", "template"]):
        tag.decompose()
    body_text = re.sub(r"\s+", " ", body_clone.get_text(" ", strip=True))
    if len(body_text.encode("utf-8")) < 2_048:
        score += 1

    # Signal 2: Framework root node exists but has little/no rendered content.
    for root_id in ("__next", "app", "root"):
        root = soup.find("div", id=root_id)
        if not root:
            continue
        root_text = re.sub(r"\s+", " ", root.get_text(" ", strip=True))
        if len(root_text) < 120:
            score += 1
            break

    # Signal 3: JS-required noscript banner.
    for ns in soup.find_all("noscript"):
        text = (ns.get_text(" ", strip=True) or "").lower()
        if "enable javascript" in text or "javascript" in text:
            score += 1
            break

    # Signal 4: Missing product signals.
    has_og_title = bool(soup.find("meta", attrs={"property": "og:title"}))
    has_h1 = any(len((h.get_text(" ", strip=True) or "").strip()) >= 8 for h in soup.find_all("h1"))
    has_price_meta = bool(
        soup.find("meta", attrs={"property": "product:price:amount"})
        or soup.find("meta", attrs={"property": "product:price"})
        or soup.find("meta", attrs={"itemprop": "price"})
    )
    has_jsonld_product = _has_jsonld_product(soup)
    if not (has_og_title or has_h1 or has_price_meta or has_jsonld_product):
        score += 1

    return score >= 2
