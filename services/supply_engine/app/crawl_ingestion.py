"""
Crawl ingestion: allowlisted URLs only, robots.txt respected, rate limited.

Pipeline:
1) Discover candidate URLs (sitemaps + bounded category crawl)
2) Extract product data via deterministic cascade (JSON-LD -> semantic DOM)
3) Normalize into existing `items` schema and upsert into Firestore
4) Persist snapshots, failures, and daily metrics for monitoring/healing
"""
from __future__ import annotations

import sys
import time
from datetime import datetime, timezone
from types import SimpleNamespace
from typing import Any


# ============================================================================
# VERBOSE LOGGING - prints to terminal so you can follow crawl progress
# ============================================================================
class CrawlLogger:
    """Simple logger that prints timestamped messages to terminal."""
    
    def __init__(self, source_id: str):
        self.source_id = source_id
        self.start_time = time.time()
    
    def _timestamp(self) -> str:
        elapsed = time.time() - self.start_time
        return f"[{elapsed:6.1f}s]"
    
    def header(self, msg: str):
        print(f"\n{'='*60}", flush=True)
        print(f"  {msg}", flush=True)
        print(f"{'='*60}", flush=True)
    
    def section(self, msg: str):
        print(f"\n{self._timestamp()} ▶ {msg}", flush=True)
    
    def info(self, msg: str):
        print(f"{self._timestamp()}   {msg}", flush=True)
    
    def success(self, msg: str):
        print(f"{self._timestamp()}   ✓ {msg}", flush=True)
    
    def warning(self, msg: str):
        print(f"{self._timestamp()}   ⚠ {msg}", flush=True)
    
    def error(self, msg: str):
        print(f"{self._timestamp()}   ✗ {msg}", flush=True)
    
    def progress(self, current: int, total: int, msg: str):
        pct = (current / total * 100) if total > 0 else 0
        bar_len = 20
        filled = int(bar_len * current / total) if total > 0 else 0
        bar = "█" * filled + "░" * (bar_len - filled)
        print(f"{self._timestamp()}   [{bar}] {current}/{total} ({pct:.0f}%) {msg}", flush=True)
    
    def summary(self, stats: dict):
        print(f"\n{'-'*60}", flush=True)
        print(f"  SUMMARY for {self.source_id}", flush=True)
        print(f"{'-'*60}", flush=True)
        print(f"  URLs discovered:    {stats.get('urlsDiscovered', 0)}", flush=True)
        print(f"  Product candidates: {stats.get('urlsCandidateProducts', 0)}", flush=True)
        print(f"  Pages fetched:      {stats.get('fetched', 0)}", flush=True)
        print(f"  Extracted:          {stats.get('urlsExtracted', 0)}", flush=True)
        print(f"  Successful:         {stats.get('success', 0)}", flush=True)
        print(f"  Upserted:           {stats.get('upserted', 0)}", flush=True)
        print(f"  Failed:             {stats.get('failed', 0)}", flush=True)
        if stats.get('blockedCount', 0) > 0:
            print(f"  Blocked (robots):   {stats.get('blockedCount', 0)}", flush=True)
        print(f"{'-'*60}\n", flush=True)

from app.firestore_client import (
    get_firestore_client,
    create_run,
    update_run,
    create_job,
    update_job,
    write_items,
    upsert_crawl_url,
    record_extraction_failure,
    write_product_snapshot,
    upsert_metrics_daily,
    get_active_recipe,
)
from app.http.fetcher import PoliteFetcher, FetchError
from app.locator.sitemap import discover_from_sitemaps
from app.locator.crawler import discover_from_category_crawl
from app.extractor.cascade import extract_product_from_html
from app.extractor.signals import extract_page_signals
from app.normalization import canonical_url as canonicalize_url, normalize_material, normalize_color_family, normalize_size_class, infer_color_from_title
from app.monitor.drift import check_drift


def _utc_date() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _source_seed_urls(source: dict) -> list[str]:
    seeds = source.get("seedUrls") or source.get("seed_urls") or []
    if isinstance(seeds, str):
        seeds = [seeds]
    if not isinstance(seeds, list):
        return []
    return [str(u).strip() for u in seeds if str(u).strip()]


def _source_seed_type(source: dict) -> str:
    st = (source.get("seedType") or source.get("seed_type") or "").strip().lower()
    if st in ("sitemap", "category", "manual"):
        return st
    return "manual"


def _source_include_keywords(source: dict) -> list[str]:
    kws = source.get("includeKeywords") or source.get("include_keywords")
    if isinstance(kws, list) and kws:
        return [str(k).strip() for k in kws if str(k).strip()]
    # Sofas-first defaults (Sweden-first)
    return ["soffa", "soffor", "sofa", "sofas", "hörnsoffa", "divansoffa", "divan", "fåtölj", "armchair"]


def _source_rate_limit(source: dict) -> float | None:
    try:
        r = source.get("rateLimitRps") or source.get("rate_limit_rps")
        if r is None:
            return None
        return float(r)
    except Exception:
        return None


def _allowlist_policy(source: dict) -> dict | None:
    pol = source.get("allowlistPolicy") or source.get("allowlist_policy")
    return pol if isinstance(pol, dict) else None


def _robots_respect(source: dict) -> bool:
    v = source.get("robotsRespect")
    if v is None:
        v = source.get("robots_respect")
    return bool(v) if v is not None else True


def _base_url(source: dict) -> str:
    return (source.get("baseUrl") or source.get("base_url") or "").strip()


def _get_derived_config(source: dict) -> dict | None:
    """
    Get the derived configuration from a source, if present.
    
    New sources have a 'derived' object with auto-discovered configuration.
    Old sources use the legacy fields directly.
    """
    return source.get("derived") if isinstance(source.get("derived"), dict) else None


def _get_effective_config(source: dict) -> dict:
    """
    Get effective configuration, preferring derived values over legacy fields.
    
    This supports both:
    - New sources: with 'derived' object from auto-discovery
    - Legacy sources: with direct fields like baseUrl, seedUrls, seedType
    
    Returns a normalized config dict with all necessary fields.
    """
    derived = _get_derived_config(source)
    
    if derived:
        # New format: use derived configuration
        return {
            "baseUrl": derived.get("baseUrl") or _base_url(source),
            "seedUrl": derived.get("seedUrl") or "",
            "seedPath": derived.get("seedPath") or "",
            "seedPathPattern": derived.get("seedPathPattern") or "",
            "strategy": derived.get("strategy") or "sitemap",
            "sitemapUrls": derived.get("sitemapUrls") or [],
            "domain": derived.get("domain") or "",
            "useDerived": True,
        }
    else:
        # Legacy format: use direct fields
        return {
            "baseUrl": _base_url(source),
            "seedUrl": "",
            "seedPath": "",
            "seedPathPattern": "",
            "strategy": _source_seed_type(source),
            "sitemapUrls": [],
            "domain": "",
            "useDerived": False,
        }


def run_crawl_ingestion(source_id: str, source: dict) -> dict:
    """
    Run crawl ingestion for a source.

    Supports two configuration formats:
    1. New format (derived): Auto-discovered configuration with baseUrl, seedUrl, strategy
    2. Legacy format: Direct fields like baseUrl, seedUrls, seedType
    
    Required source fields (legacy):
    - baseUrl
    - seedUrls (1-3 URLs; sitemap or sofa category)
    - allowlistPolicy (recommended)
    """
    log = CrawlLogger(source_id)
    log.header(f"CRAWL INGESTION: {source_id}")
    
    db = get_firestore_client()
    run_id = create_run(db, source_id, "running")
    started_at = time.time()
    stats: dict[str, Any] = {
        "fetched": 0,
        "parsed": 0,
        "normalized": 0,
        "upserted": 0,
        "failed": 0,
        "urlsDiscovered": 0,
        "urlsCandidateProducts": 0,
        "urlsExtracted": 0,
        "success": 0,
        "jsonldRate": 0,
        "domRate": 0,
        "blockedCount": 0,
        "blockedRate": 0.0,
        "avgCompleteness": 0.0,
    }

    # Get effective configuration (supports both new derived and legacy formats)
    config = _get_effective_config(source)
    base_url = config["baseUrl"]
    derived_seed_url = config["seedUrl"]
    derived_strategy = config["strategy"]
    derived_seed_path_pattern = config["seedPathPattern"]
    use_derived = config["useDerived"]
    
    # Legacy fields (used if no derived config)
    seed_urls = _source_seed_urls(source)
    seed_type = _source_seed_type(source) if not use_derived else derived_strategy
    include_keywords = _source_include_keywords(source)
    rate_limit_rps = _source_rate_limit(source)
    allowlist_policy = _allowlist_policy(source)
    robots_respect = _robots_respect(source)
    user_agent = source.get("userAgent") or source.get("user_agent")

    log.section("Configuration")
    if use_derived:
        log.info("Using AUTO-DISCOVERED configuration")
        log.info(f"Base URL: {base_url}")
        log.info(f"Seed URL: {derived_seed_url}")
        log.info(f"Strategy: {derived_strategy}")
        log.info(f"Path pattern: {derived_seed_path_pattern or '(none)'}")
    else:
        log.info("Using LEGACY configuration")
        log.info(f"Base URL: {base_url}")
        log.info(f"Seed URLs: {seed_urls if seed_urls else '(auto-discover from sitemap)'}")
        log.info(f"Seed type: {seed_type}")
    log.info(f"Include keywords: {include_keywords[:5]}{'...' if len(include_keywords) > 5 else ''}")
    log.info(f"Rate limit: {rate_limit_rps or 'default'} req/s")
    log.info(f"Robots.txt respect: {robots_respect}")

    if not base_url:
        log.error("baseUrl is required but missing!")
        update_run(db, run_id, "failed", stats, error_summary="baseUrl required for crawl sources")
        return {"runId": run_id, "status": "failed", "stats": stats, "errorSummary": "baseUrl required"}
    
    # Auto-discover mode: if no seedUrls and no derived config, use sitemap discovery from baseUrl
    auto_discover = not seed_urls and not use_derived
    if auto_discover:
        seed_type = "sitemap"  # Force sitemap discovery mode

    max_urls = int(source.get("maxUrlsPerRun") or 200)
    max_pages = int(source.get("maxPagesPerRun") or 50)
    max_depth = int(source.get("maxDepth") or 2)

    fetcher = PoliteFetcher(user_agent=user_agent or "SwiperBot/0.1 (contact: johannes@branchandleaf.se)")
    extracted_at_iso = _utc_now_iso()

    try:
        # 1) Discover
        log.section("PHASE 1: URL Discovery")
        job_id = create_job(
            db,
            source_id,
            run_id,
            "discover_urls",
            {"seedUrls": seed_urls, "baseUrl": base_url, "strategy": derived_strategy if use_derived else seed_type},
            "running",
        )
        discovered = []
        
        # Determine discovery strategy based on config type
        if use_derived:
            # New derived configuration: use strategy and seed URL
            if derived_strategy == "sitemap":
                log.info("Using SITEMAP strategy (auto-discovered)")
                discovered = discover_from_sitemaps(
                    fetcher,
                    base_url=base_url,
                    allowlist_policy=allowlist_policy,
                    robots_respect=robots_respect,
                    rate_limit_rps=rate_limit_rps,
                    max_urls=50_000,
                )
                if discovered:
                    # Filter by seed path pattern if present
                    if derived_seed_path_pattern:
                        original_count = len(discovered)
                        discovered = [
                            d for d in discovered 
                            if derived_seed_path_pattern.lower() in d.url.lower()
                        ]
                        log.info(f"Filtered by path pattern '{derived_seed_path_pattern}': {original_count} -> {len(discovered)}")
                    log.success(f"Found {len(discovered)} URLs from sitemap")
                else:
                    log.warning("Sitemap discovery found no URLs, trying crawl fallback")
                    # Fallback to crawl from seed URL
                    crawl_seed = derived_seed_url if derived_seed_url else base_url
                    discovered = discover_from_category_crawl(
                        fetcher,
                        base_url=base_url,
                        seed_urls=[crawl_seed],
                        allowlist_policy=allowlist_policy,
                        robots_respect=robots_respect,
                        rate_limit_rps=rate_limit_rps,
                        include_keywords=include_keywords,
                        max_depth=max_depth,
                        max_pages=max_pages,
                        max_out_urls=5000,
                    )
                    if discovered:
                        log.success(f"Found {len(discovered)} URLs from crawl fallback")
            else:
                # Crawl strategy
                log.info("Using CRAWL strategy (auto-discovered)")
                crawl_seed = derived_seed_url if derived_seed_url else base_url
                discovered = discover_from_category_crawl(
                    fetcher,
                    base_url=base_url,
                    seed_urls=[crawl_seed],
                    allowlist_policy=allowlist_policy,
                    robots_respect=robots_respect,
                    rate_limit_rps=rate_limit_rps,
                    include_keywords=include_keywords,
                    max_depth=max_depth,
                    max_pages=max_pages,
                    max_out_urls=5000,
                )
                if discovered:
                    log.success(f"Found {len(discovered)} URLs from crawl")
                else:
                    log.warning("Crawl found no URLs")
        elif seed_type == "manual" and seed_urls:
            # Direct product URL ingestion (no discovery crawl).
            log.info(f"Manual mode: using {len(seed_urls)} provided URLs directly")
            discovered = [
                SimpleNamespace(url=u, source="manual", confidence=1.0, url_type_hint="product") for u in seed_urls
            ]
        elif seed_type == "sitemap" or auto_discover or any("sitemap" in u.lower() for u in seed_urls):
            # Legacy: Auto-discover via sitemap first
            log.info("Attempting sitemap discovery (legacy mode)...")
            discovered = discover_from_sitemaps(
                fetcher,
                base_url=base_url,
                allowlist_policy=allowlist_policy,
                robots_respect=robots_respect,
                rate_limit_rps=rate_limit_rps,
                max_urls=50_000,
            )
            if discovered:
                log.success(f"Found {len(discovered)} URLs from sitemap")
            else:
                log.warning("No sitemap found or sitemap empty")
            # Fallback: if no sitemap found and auto_discover, crawl from homepage
            if not discovered and auto_discover:
                log.info("Falling back to homepage crawl...")
                discovered = discover_from_category_crawl(
                    fetcher,
                    base_url=base_url,
                    seed_urls=[base_url],  # Start from homepage
                    allowlist_policy=allowlist_policy,
                    robots_respect=robots_respect,
                    rate_limit_rps=rate_limit_rps,
                    include_keywords=include_keywords,
                    max_depth=max_depth,
                    max_pages=max_pages,
                    max_out_urls=5000,
                )
                if discovered:
                    log.success(f"Found {len(discovered)} URLs from homepage crawl")
                else:
                    log.warning("Homepage crawl found no URLs")
        elif seed_urls:
            log.info(f"Category crawl from {len(seed_urls)} seed URLs (legacy mode)...")
            discovered = discover_from_category_crawl(
                fetcher,
                base_url=base_url,
                seed_urls=seed_urls,
                allowlist_policy=allowlist_policy,
                robots_respect=robots_respect,
                rate_limit_rps=rate_limit_rps,
                include_keywords=include_keywords,
                max_depth=max_depth,
                max_pages=max_pages,
                max_out_urls=5000,
            )
            if discovered:
                log.success(f"Found {len(discovered)} URLs from category crawl")
            else:
                log.warning("Category crawl found no URLs")
        else:
            # No seed URLs and not sitemap mode - shouldn't happen but handle gracefully
            log.error("No discovery method available!")
            update_run(db, run_id, "failed", stats, error_summary="No discovery method available")
            return {"runId": run_id, "status": "failed", "stats": stats, "errorSummary": "No discovery method available"}

        # Persist discovered URLs and select product candidates
        log.info("Filtering for product candidates...")
        product_candidates: list[str] = []
        for d in discovered:
            upsert_crawl_url(
                db,
                source_id=source_id,
                url=d.url,
                discovered_from=d.source,
                url_type=d.url_type_hint,
                confidence=d.confidence,
                canonical_url=None,
                status="active",
            )
            if d.url_type_hint == "product" or d.confidence >= 0.7:
                product_candidates.append(d.url)
        # If sitemap output had no hints, treat all as candidates but cap.
        if not product_candidates:
            log.info("No high-confidence product URLs, using all discovered URLs")
            product_candidates = [d.url for d in discovered]

        product_candidates = product_candidates[:max_urls]
        stats["urlsDiscovered"] = len(discovered)
        stats["urlsCandidateProducts"] = len(product_candidates)
        log.success(f"Selected {len(product_candidates)} product candidates (max {max_urls})")
        update_job(db, job_id, "succeeded")

        if not product_candidates:
            log.warning("No product candidates to extract - ending early")
            log.summary(stats)
            update_run(db, run_id, "succeeded", stats)
            return {"runId": run_id, "status": "succeeded", "stats": stats}

        # 2) Extract
        log.section("PHASE 2: Product Extraction")
        job_id = create_job(
            db,
            source_id,
            run_id,
            "extract",
            {"count": len(product_candidates)},
            "running",
        )
        items: list[dict] = []
        successes = 0
        method_counts = {"jsonld": 0, "embedded_json": 0, "recipe": 0, "dom": 0}
        completeness_sum = 0.0
        blocked_count = 0
        active_recipe = None
        try:
            rdoc = get_active_recipe(db, source_id=source_id)
            if rdoc and isinstance(rdoc.get("recipeJson"), dict):
                active_recipe = rdoc["recipeJson"]
                log.info(f"Using active recipe: {rdoc.get('recipeId', 'unknown')}")
        except Exception:
            active_recipe = None
        
        log.info(f"Extracting from {len(product_candidates)} URLs...")
        for idx, url in enumerate(product_candidates):
            # Progress update every 5 items or on first/last
            if idx == 0 or idx == len(product_candidates) - 1 or (idx + 1) % 5 == 0:
                log.progress(idx + 1, len(product_candidates), url[:60] + "..." if len(url) > 60 else url)
            
            try:
                r = fetcher.fetch(
                    url,
                    base_url=base_url,
                    allowlist_policy=allowlist_policy,
                    robots_respect=robots_respect,
                    rate_limit_rps=rate_limit_rps,
                )
                stats["fetched"] += 1
            except FetchError as e:
                stats["failed"] += 1
                msg = str(e)
                if "robots" in msg.lower() or "allowlist" in msg.lower():
                    blocked_count += 1
                    log.warning(f"Blocked: {url[:50]}... ({msg[:40]})")
                else:
                    log.error(f"Fetch failed: {url[:50]}... ({msg[:40]})")
                record_extraction_failure(
                    db,
                    source_id=source_id,
                    url=url,
                    failure_type="fetch",
                    error=msg,
                    html_hash=None,
                    signals={"url": url, "finalUrl": None},
                )
                continue

            product = extract_product_from_html(
                source_id=source_id,
                fetched_url=url,
                final_url=r.final_url,
                html=r.text,
                extracted_at_iso=extracted_at_iso,
                recipe=active_recipe,
            )
            stats["urlsExtracted"] += 1
            if product is None:
                stats["failed"] += 1
                # Capture a small, safe \"signals packet\" to support healing later.
                sig = extract_page_signals(r.text, final_url=r.final_url)
                signals_packet = {
                    "finalUrl": r.final_url,
                    "canonical": sig.canonical_url,
                    "ogUrl": sig.og_url,
                    "ogType": sig.og_type,
                    "ogImagesCount": len(sig.og_images),
                    "jsonldBlockCount": len(sig.jsonld_blocks),
                    "embeddedJsonCandidatesCount": len(sig.embedded_json_candidates),
                }
                log.warning(f"No product extracted: {url[:50]}... (JSON-LD blocks: {len(sig.jsonld_blocks)}, og:type: {sig.og_type})")
                record_extraction_failure(
                    db,
                    source_id=source_id,
                    url=url,
                    failure_type="parse",
                    error="No strategy produced a valid product (missing title/canonical).",
                    html_hash=r.html_hash,
                    signals=signals_packet,
                )
                continue

            successes += 1
            method_counts[product.method] = method_counts.get(product.method, 0) + 1
            completeness_sum += float(product.completeness_score or 0.0)
            
            # Log successful extraction
            price_str = f"{product.price_amount} {product.price_currency}" if product.price_amount else "no price"
            log.success(f"Extracted [{product.method}]: {product.title[:40]}... ({price_str})")

            # Snapshot for history/debug
            write_product_snapshot(
                db,
                source_id=source_id,
                canonical_url=product.canonical_url,
                snapshot={
                    "product": {
                        "retailerId": product.retailer_id,
                        "retailerDomain": product.retailer_domain,
                        "productUrl": product.product_url,
                        "canonicalUrl": product.canonical_url,
                        "title": product.title,
                        "price": {
                            "amount": product.price_amount,
                            "currency": product.price_currency,
                            "raw": product.price_raw,
                        }
                        if product.price_amount is not None or product.price_raw
                        else None,
                        "images": product.images,
                        "description": product.description,
                        "brand": product.brand,
                        "extractedAt": product.extracted_at,
                        "extraction": {
                            "method": product.method,
                            "recipeId": product.recipe_id,
                            "recipeVersion": product.recipe_version,
                            "completenessScore": product.completeness_score,
                            "warnings": product.warnings,
                        },
                    },
                    "debug": product.debug,
                },
                extracted_at_iso=product.extracted_at,
            )

            # Map into existing `items` schema (P1: use extracted dimensions, material, color)
            canon = canonicalize_url(product.canonical_url)
            title = product.title.strip()[:500] if product.title else "Untitled"
            img_objs = [{"url": u, "alt": title[:200]} for u in (product.images or []) if isinstance(u, str) and u]
            price_amount = float(product.price_amount) if product.price_amount is not None else 0.0
            price_currency = (product.price_currency or "SEK").strip() or "SEK"
            dims = product.dimensions_raw
            width_cm = (dims or {}).get("w") if dims else None
            items.append(
                {
                    "sourceId": source_id,
                    "sourceType": "crawl",
                    "sourceUrl": url,
                    "canonicalUrl": canon,
                    "title": title,
                    "brand": (product.brand or "").strip() or None,
                    "descriptionShort": (product.description or "")[:500] if product.description else None,
                    "priceAmount": price_amount,
                    "priceCurrency": price_currency,
                    "dimensionsCm": dims,
                    "sizeClass": normalize_size_class(None, width_cm),
                    "material": normalize_material(product.material_raw) or "mixed",
                    "colorFamily": normalize_color_family(product.color_raw) or infer_color_from_title(product.title) or "multi",
                    "styleTags": [],
                    "newUsed": "new",
                    "deliveryComplexity": "medium",
                    "smallSpaceFriendly": False,
                    "modular": False,
                    "ecoTags": [],
                    "availabilityStatus": "unknown",
                    "outboundUrl": url,
                    "images": img_objs,
                    # Image validation / Creative Health (populated async by validation job)
                    "imageValidation": None,  # Populated by image validation job
                    "creativeHealth": None,   # Score 0-100, band (green/yellow/red)
                    "lastUpdatedAt": None,
                    "firstSeenAt": None,
                    "lastSeenAt": None,
                    "isActive": True,
                }
            )

        stats["success"] = successes
        stats["jsonldRate"] = (method_counts.get("jsonld", 0) / successes) if successes else 0
        stats["embeddedJsonRate"] = (method_counts.get("embedded_json", 0) / successes) if successes else 0
        stats["recipeRate"] = (method_counts.get("recipe", 0) / successes) if successes else 0
        stats["domRate"] = (method_counts.get("dom", 0) / successes) if successes else 0
        stats["avgCompleteness"] = (completeness_sum / successes) if successes else 0.0
        stats["blockedCount"] = blocked_count
        stats["blockedRate"] = (blocked_count / stats["urlsCandidateProducts"]) if stats["urlsCandidateProducts"] else 0.0
        update_job(db, job_id, "succeeded")
        
        log.info(f"Extraction complete: {successes} products from {stats['urlsExtracted']} pages")
        if successes > 0:
            log.info(f"Methods used: JSON-LD={method_counts.get('jsonld', 0)}, Embedded={method_counts.get('embedded_json', 0)}, DOM={method_counts.get('dom', 0)}")

        # 3) Upsert
        log.section("PHASE 3: Database Upsert")
        job_id = create_job(db, source_id, run_id, "upsert", {"count": len(items)}, "running")
        log.info(f"Writing {len(items)} items to Firestore...")
        upserted, failed = write_items(db, items, source_id)
        stats["upserted"] = upserted
        stats["failed"] = int(stats.get("failed") or 0) + failed
        stats["normalized"] = len(items)
        update_job(db, job_id, "succeeded")
        log.success(f"Upserted {upserted} items, {failed} failed")

        # 4) Daily metrics (best-effort)
        upsert_metrics_daily(
            db,
            source_id=source_id,
            date=_utc_date(),
            metrics={
                "urlsDiscovered": stats["urlsDiscovered"],
                "urlsExtracted": stats["urlsExtracted"],
                "successRate": (successes / stats["urlsExtracted"]) if stats["urlsExtracted"] else 0.0,
                "avgCompleteness": stats["avgCompleteness"],
                "jsonldRate": stats["jsonldRate"],
                "embeddedJsonRate": stats.get("embeddedJsonRate", 0.0),
                "domRate": stats["domRate"],
                "blockedRate": stats["blockedRate"],
            },
        )

        # Drift detection (best-effort): compare to last 7 days baseline if present.
        try:
            # Query last 7 metric docs (excluding current date is not guaranteed; still useful).
            q = (
                db.collection("metricsDaily")
                .where("sourceId", "==", source_id)
                .order_by("date", direction="DESCENDING")
                .limit(8)
            )
            docs = q.get()
            # Drop the current day doc if it appears first
            baseline_docs = []
            for d in docs:
                data = d.to_dict() or {}
                if data.get("date") == _utc_date():
                    continue
                baseline_docs.append(data)
                if len(baseline_docs) >= 7:
                    break
            if baseline_docs:
                b_success = sum(float(x.get("successRate") or 0.0) for x in baseline_docs) / len(baseline_docs)
                b_comp = sum(float(x.get("avgCompleteness") or 0.0) for x in baseline_docs) / len(baseline_docs)
            else:
                b_success = None
                b_comp = None

            drift = check_drift(
                current_success_rate=(successes / stats["urlsExtracted"]) if stats["urlsExtracted"] else 0.0,
                current_avg_completeness=float(stats["avgCompleteness"] or 0.0),
                baseline_success_rate=b_success,
                baseline_avg_completeness=b_comp,
            )
            if drift.triggered:
                record_extraction_failure(
                    db,
                    source_id=source_id,
                    url=base_url,
                    failure_type="validate",
                    error="Drift trigger fired: " + ", ".join(drift.reasons),
                    html_hash=None,
                    signals={
                        "type": "drift",
                        "reasons": drift.reasons,
                        "baselineSuccessRate": drift.baseline_success_rate,
                        "baselineAvgCompleteness": drift.baseline_avg_completeness,
                        "currentSuccessRate": (successes / stats["urlsExtracted"]) if stats["urlsExtracted"] else 0.0,
                        "currentAvgCompleteness": stats["avgCompleteness"],
                    },
                )
        except Exception:
            pass

        duration_ms = int((time.time() - started_at) * 1000)
        stats["durationMs"] = duration_ms
        update_run(db, run_id, "succeeded", stats)
        
        log.summary(stats)
        log.header(f"CRAWL COMPLETE: {source_id} - SUCCESS")
        
        return {"runId": run_id, "status": "succeeded", "stats": stats}
    except Exception as e:
        duration_ms = int((time.time() - started_at) * 1000)
        stats["durationMs"] = duration_ms
        update_run(db, run_id, "failed", stats, error_summary=str(e))
        
        log.error(f"Crawl failed with exception: {e}")
        log.summary(stats)
        log.header(f"CRAWL COMPLETE: {source_id} - FAILED")
        
        return {"runId": run_id, "status": "failed", "stats": stats, "errorSummary": str(e)}
    finally:
        try:
            fetcher.close()
        except Exception:
            pass
