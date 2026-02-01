"""Default extractor: JSON-LD product schema + heuristic selectors."""
import json
import re
from typing import Any

from bs4 import BeautifulSoup


def extract_product_list(html: str) -> list[dict]:
    """Extract product list URLs from HTML. Returns [{sourceUrl, ...}]."""
    soup = BeautifulSoup(html, "lxml")
    out = []
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(script.string or "{}")
            if isinstance(data, dict) and data.get("@type") == "ItemList":
                for item in data.get("itemListElement", []):
                    url = item.get("url") if isinstance(item, dict) else None
                    if url:
                        out.append({"sourceUrl": url})
            if isinstance(data, list):
                for el in data:
                    if isinstance(el, dict) and el.get("@type") == "Product" and el.get("url"):
                        out.append({"sourceUrl": el["url"]})
        except (json.JSONDecodeError, TypeError):
            continue
    if not out:
        for a in soup.select('a[href*="/product/"], a[href*="/p/"], a[data-product-id"]'):
            href = a.get("href")
            if href and href.startswith("http"):
                out.append({"sourceUrl": href})
    return out[:100]


def extract_product_detail(html: str) -> dict | None:
    """Extract product detail from HTML. Returns normalized fields or None."""
    soup = BeautifulSoup(html, "lxml")
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(script.string or "{}")
            if isinstance(data, dict) and data.get("@type") == "Product":
                return _normalize_jsonld_product(data)
            if isinstance(data, list):
                for el in data:
                    if isinstance(el, dict) and el.get("@type") == "Product":
                        return _normalize_jsonld_product(el)
        except (json.JSONDecodeError, TypeError):
            continue
    return _heuristic_extract(soup)


def _normalize_jsonld_product(data: dict) -> dict:
    out = {}
    out["title"] = data.get("name") or ""
    out["price"] = None
    if "offers" in data:
        offers = data["offers"]
        if isinstance(offers, dict):
            out["price"] = offers.get("price")
            out["currency"] = offers.get("priceCurrency") or "SEK"
        elif isinstance(offers, list) and offers:
            o = offers[0]
            out["price"] = o.get("price")
            out["currency"] = o.get("priceCurrency") or "SEK"
    out["url"] = data.get("url") or data.get("id") or ""
    out["image_url"] = ""
    img = data.get("image")
    if isinstance(img, str):
        out["image_url"] = img
    elif isinstance(img, list) and img:
        out["image_url"] = img[0] if isinstance(img[0], str) else img[0].get("url", "")
    out["brand"] = data.get("brand", {}).get("name") if isinstance(data.get("brand"), dict) else data.get("brand") or ""
    out["description"] = data.get("description") or ""
    return out


def _heuristic_extract(soup: BeautifulSoup) -> dict | None:
    title = ""
    for sel in ("h1", "[data-product-name]", ".product-title"):
        el = soup.select_one(sel)
        if el and el.get_text(strip=True):
            title = el.get_text(strip=True)[:500]
            break
    price_el = soup.select_one("[data-price], .price, .product-price")
    price = None
    if price_el:
        text = price_el.get_text(strip=True)
        match = re.search(r"[\d\s]+[,.]?\d*", text.replace(" ", ""))
        if match:
            try:
                price = float(match.group().replace(",", "."))
            except ValueError:
                pass
    img_el = soup.select_one(".product-image img, [data-product-image] img, main img")
    image_url = img_el.get("src", "") if img_el else ""
    return {"title": title, "price": price, "currency": "SEK", "url": "", "image_url": image_url, "brand": "", "description": ""} if title or price else None
