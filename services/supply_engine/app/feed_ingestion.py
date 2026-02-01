"""
Feed ingestion: CSV/JSON/XML -> normalized items -> Firestore.
"""
import csv
import json
import os
import time
from pathlib import Path
from typing import Any

from app.firestore_client import get_firestore_client, write_items, create_run, update_run, create_job, update_job
from app.normalization import (
    canonical_url,
    normalize_material,
    normalize_color_family,
    normalize_size_class,
    normalize_new_used,
)


def run_feed_ingestion(source_id: str, source: dict) -> dict:
    """Run feed ingestion for a source. Returns run stats."""
    feed_url = source.get("feedUrl") or source.get("feed_format_url")
    feed_format = (source.get("feedFormat") or source.get("feed_format") or "csv").lower()
    if not feed_url:
        raise ValueError("feedUrl required for feed source")

    db = get_firestore_client()
    run_id = create_run(db, source_id, "running")
    started_at = time.time()
    stats = {"fetched": 0, "parsed": 0, "normalized": 0, "upserted": 0, "failed": 0}

    try:
        job_id = create_job(db, source_id, run_id, "fetch_feed", {"url": feed_url}, "running")
        rows = _fetch_feed(feed_url, feed_format)
        stats["fetched"] = len(rows)
        update_job(db, job_id, "succeeded")
    except Exception as e:
        update_job(db, job_id, "failed", error=str(e))
        update_run(db, run_id, "failed", stats, error_summary=str(e))
        return {"runId": run_id, "status": "failed", "stats": stats, "errorSummary": str(e)}

    try:
        job_id = create_job(db, source_id, run_id, "parse", {"count": len(rows)}, "running")
        raw_items = _parse_feed_rows(rows, feed_format)
        stats["parsed"] = len(raw_items)
        update_job(db, job_id, "succeeded")
    except Exception as e:
        update_job(db, job_id, "failed", error=str(e))
        update_run(db, run_id, "failed", stats, error_summary=str(e))
        return {"runId": run_id, "status": "failed", "stats": stats, "errorSummary": str(e)}

    try:
        job_id = create_job(db, source_id, run_id, "normalize", {}, "running")
        items = [_normalize_item(raw, source_id) for raw in raw_items]
        items = [x for x in items if x is not None]
        stats["normalized"] = len(items)
        update_job(db, job_id, "succeeded")
    except Exception as e:
        update_job(db, job_id, "failed", error=str(e))
        update_run(db, run_id, "failed", stats, error_summary=str(e))
        return {"runId": run_id, "status": "failed", "stats": stats, "errorSummary": str(e)}

    try:
        job_id = create_job(db, source_id, run_id, "upsert", {"count": len(items)}, "running")
        upserted, failed = write_items(db, items, source_id)
        stats["upserted"] = upserted
        stats["failed"] = failed
        update_job(db, job_id, "succeeded")
    except Exception as e:
        update_job(db, job_id, "failed", error=str(e))
        update_run(db, run_id, "failed", stats, error_summary=str(e))
        return {"runId": run_id, "status": "failed", "stats": stats, "errorSummary": str(e)}

    duration_ms = int((time.time() - started_at) * 1000)
    stats["durationMs"] = duration_ms
    update_run(db, run_id, "succeeded", stats)
    return {"runId": run_id, "status": "succeeded", "stats": stats}


def _fetch_feed(feed_url: str, feed_format: str) -> list[dict]:
    """Fetch feed from URL or local path."""
    from urllib.parse import urlparse
    if urlparse(feed_url).scheme in ("http", "https"):
        path = None
    else:
        path = Path(feed_url)
        if not path.is_absolute():
            repo_root = Path(__file__).resolve().parent.parent.parent.parent
            path = repo_root / path
    if path is not None and path.is_file():
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            if feed_format == "csv":
                return list(csv.DictReader(f))
            if feed_format == "json":
                data = json.load(f)
                return data if isinstance(data, list) else data.get("items", data.get("products", [data]))
            return []
    # HTTP fetch
    import httpx
    with httpx.Client(headers={"User-Agent": os.environ.get("USER_AGENT", "SwiperBot/0.1")}, follow_redirects=True) as client:
        r = client.get(feed_url)
        r.raise_for_status()
        text = r.text
    if feed_format == "csv":
        return list(csv.DictReader(text.splitlines()))
    if feed_format == "json":
        data = json.loads(text)
        return data if isinstance(data, list) else data.get("items", data.get("products", [data]))
    return []


def _parse_feed_rows(rows: list[dict], feed_format: str) -> list[dict]:
    """Map feed rows to raw item dict (common keys)."""
    out = []
    for row in rows:
        if feed_format == "csv":
            raw = {
                "title": row.get("title") or row.get("name") or row.get("Title") or "",
                "price": row.get("price") or row.get("Price") or row.get("price_amount") or 0,
                "currency": (row.get("currency") or row.get("Currency") or "SEK").strip(),
                "url": row.get("url") or row.get("link") or row.get("source_url") or "",
                "image_url": row.get("image_url") or row.get("image") or row.get("image_url_1") or "",
                "brand": row.get("brand") or row.get("Brand") or "",
                "description": row.get("description") or row.get("Description") or "",
                "width": row.get("width") or row.get("width_cm") or row.get("Width") or "",
                "height": row.get("height") or row.get("height_cm") or row.get("Height") or "",
                "depth": row.get("depth") or row.get("depth_cm") or row.get("Depth") or "",
                "material": row.get("material") or row.get("Material") or "",
                "color": row.get("color") or row.get("colour") or row.get("Color") or "",
                "new_used": row.get("new_used") or row.get("condition") or "",
            }
        else:
            raw = {
                "title": row.get("title") or row.get("name") or "",
                "price": row.get("price") or row.get("priceAmount") or 0,
                "currency": row.get("currency") or row.get("priceCurrency") or "SEK",
                "url": row.get("url") or row.get("link") or row.get("sourceUrl") or "",
                "image_url": row.get("image_url") or row.get("imageUrl") or (row.get("images") or [{}])[0].get("url") if isinstance(row.get("images"), list) else "",
                "brand": row.get("brand") or "",
                "description": row.get("description") or row.get("descriptionShort") or "",
                "width": row.get("width") or (row.get("dimensionsCm") or {}).get("w"),
                "height": row.get("height") or (row.get("dimensionsCm") or {}).get("h"),
                "depth": row.get("depth") or (row.get("dimensionsCm") or {}).get("d"),
                "material": row.get("material") or "",
                "color": row.get("color") or row.get("colorFamily") or "",
                "new_used": row.get("newUsed") or row.get("new_used") or "",
            }
        if raw.get("title") or raw.get("url"):
            out.append(raw)
    return out


def _normalize_item(raw: dict, source_id: str) -> dict | None:
    """Convert raw item to Firestore item schema."""
    try:
        price = raw.get("price")
        if price is None:
            return None
        try:
            price_amount = float(price)
        except (TypeError, ValueError):
            price_amount = 0.0
        url = (raw.get("url") or "").strip()
        if not url:
            return None
        canonical = canonical_url(url)
        w = _num(raw.get("width"))
        h = _num(raw.get("height"))
        d = _num(raw.get("depth"))
        dimensions = None
        if w is not None or h is not None or d is not None:
            dimensions = {"w": w or 0, "h": h or 0, "d": d or 0}
        size_class = normalize_size_class(raw.get("size_class"), w)
        material = normalize_material(raw.get("material"))
        color_family = normalize_color_family(raw.get("color"))
        new_used = normalize_new_used(raw.get("new_used"))
        images = []
        img_url = (raw.get("image_url") or "").strip()
        if img_url:
            images.append({"url": img_url, "alt": (raw.get("title") or "")[:200]})
        title = (raw.get("title") or "Untitled").strip()[:500]
        desc_short = (raw.get("description") or "")[:500] if raw.get("description") else None
        import hashlib
        item_id = hashlib.sha256(canonical.encode()).hexdigest()[:24]
        return {
            "id": item_id,
            "sourceId": source_id,
            "sourceType": "feed",
            "sourceUrl": url,
            "canonicalUrl": canonical,
            "title": title,
            "brand": (raw.get("brand") or "").strip() or None,
            "descriptionShort": desc_short,
            "priceAmount": price_amount,
            "priceCurrency": (raw.get("currency") or "SEK").strip(),
            "dimensionsCm": dimensions,
            "sizeClass": size_class,
            "material": material or "mixed",
            "colorFamily": color_family or "multi",
            "styleTags": [],
            "newUsed": new_used,
            "deliveryComplexity": "medium",
            "smallSpaceFriendly": False,
            "modular": False,
            "ecoTags": [],
            "availabilityStatus": "in_stock",
            "outboundUrl": url,
            "images": images,
            "lastUpdatedAt": None,
            "firstSeenAt": None,
            "lastSeenAt": None,
            "isActive": True,
        }
    except Exception:
        return None


def _num(v: Any) -> float | None:
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


