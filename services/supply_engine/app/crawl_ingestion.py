"""
Crawl ingestion: allowlisted URLs only, robots.txt respected, rate limited.

Pipeline:
1) Discover candidate URLs (sitemaps + bounded category crawl)
2) Extract product data via deterministic cascade (JSON-LD -> semantic DOM)
   - Uses concurrent fetching for speed (configurable workers)
3) Normalize into existing `items` schema and upsert into Firestore
4) Persist snapshots, failures, and daily metrics for monitoring/healing
"""
from __future__ import annotations

import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
from types import SimpleNamespace
from typing import Any


# ============================================================================
# VERBOSE LOGGING - prints to terminal so you can follow crawl progress
# ============================================================================
class CrawlLogger:
    """Simple logger that prints timestamped messages to terminal with run correlation."""
    
    def __init__(self, source_id: str, run_id: str | None = None):
        self.source_id = source_id
        self.run_id = run_id or "----"
        self.start_time = time.time()
    
    def _prefix(self) -> str:
        """Return prefix with run_id and timestamp for log correlation."""
        elapsed = time.time() - self.start_time
        return f"[{self.run_id}][{elapsed:6.1f}s]"
    
    def header(self, msg: str):
        print(f"\n{'='*70}", flush=True)
        print(f"  [{self.run_id}] {msg}", flush=True)
        print(f"{'='*70}", flush=True)
    
    def section(self, msg: str):
        print(f"\n{self._prefix()} ▶ {msg}", flush=True)
    
    def info(self, msg: str):
        print(f"{self._prefix()}   {msg}", flush=True)

    def detail(self, msg: str):
        """Low-priority diagnostic output."""
        print(f"{self._prefix()}   · {msg}", flush=True)
    
    def success(self, msg: str):
        print(f"{self._prefix()}   ✓ {msg}", flush=True)
    
    def warning(self, msg: str):
        print(f"{self._prefix()}   ⚠ {msg}", flush=True)
    
    def error(self, msg: str):
        print(f"{self._prefix()}   ✗ {msg}", flush=True)
    
    def progress(self, current: int, total: int, msg: str):
        pct = (current / total * 100) if total > 0 else 0
        bar_len = 20
        filled = int(bar_len * current / total) if total > 0 else 0
        bar = "█" * filled + "░" * (bar_len - filled)
        print(f"{self._prefix()}   [{bar}] {current}/{total} ({pct:.0f}%) {msg}", flush=True)
    
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
        if stats.get("currencyMismatchSkipped", 0) > 0:
            print(f"  Currency mismatch:  {stats.get('currencyMismatchSkipped', 0)}", flush=True)
        if stats.get("currencyUnknownSkipped", 0) > 0:
            print(f"  Currency unknown:   {stats.get('currencyUnknownSkipped', 0)}", flush=True)
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
    get_known_hashes,
    update_crawl_url_hash,
)
from app.http.fetcher import PoliteFetcher, FetchError
from app.locator.sitemap import discover_from_sitemaps
from app.locator.crawler import discover_from_category_crawl
from app.extractor.cascade import extract_product_from_html, extract_products_batch_from_html
from app.extractor.signals import extract_page_signals
from app.normalization import (
    canonical_url as canonicalize_url,
    clean_description_text,
    infer_color_from_title,
    infer_size_from_title,
    normalize_color_family,
    normalize_material,
    normalize_price_amount,
    normalize_size_class,
    validate_currency,
)
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


def _source_category_filter(source: dict) -> list[str]:
    """
    Get category filter patterns from source config.
    
    These patterns are used to filter sitemap/discovered URLs to only include
    URLs that match at least one pattern. This focuses the crawl on specific
    product categories (e.g., sofas) rather than the entire site.
    
    Example: ["soffor", "soffa", "hornsoffa"] will only keep URLs containing
    any of these substrings in their path.
    
    Returns empty list if no filter is configured (all URLs pass).
    """
    filters = source.get("categoryFilter") or source.get("category_filter")
    if isinstance(filters, str):
        # Single pattern as string - split by comma or treat as single pattern
        if "," in filters:
            filters = [f.strip() for f in filters.split(",")]
        else:
            filters = [filters.strip()]
    if isinstance(filters, list) and filters:
        return [str(f).strip().lower() for f in filters if str(f).strip()]
    return []


def _filter_urls_by_category(urls: list, category_patterns: list[str], logger=None) -> list:
    """
    Filter discovered URLs by category patterns.
    
    Only keeps URLs where the path contains at least one of the category patterns.
    If category_patterns is empty, all URLs pass through (no filtering).
    
    Args:
        urls: List of DiscoveredUrl or similar objects with .url attribute
        category_patterns: List of lowercase patterns to match against URL paths
        logger: Optional logger for debug output
        
    Returns:
        Filtered list of URLs
    """
    if not category_patterns:
        return urls  # No filter configured, return all
    
    original_count = len(urls)
    filtered = []
    
    for u in urls:
        url_lower = (u.url if hasattr(u, 'url') else str(u)).lower()
        if any(pattern in url_lower for pattern in category_patterns):
            filtered.append(u)
    
    if logger:
        logger.info(f"Category filter [{', '.join(category_patterns[:3])}{'...' if len(category_patterns) > 3 else ''}]: {original_count} -> {len(filtered)} URLs")
    
    return filtered


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


def _source_browser_fallback(source: dict) -> bool:
    v = source.get("useBrowserFallback")
    if v is None:
        v = source.get("use_browser_fallback")
    return bool(v) if v is not None else False


def _source_quality_refetch(source: dict) -> bool:
    v = source.get("enableQualityRefetch")
    if v is None:
        v = source.get("enable_quality_refetch")
    return bool(v) if v is not None else False


def _missing_fields_for_product(product: Any) -> list[str]:
    missing: list[str] = []
    if not (product.description and str(product.description).strip()):
        missing.append("description")
    if not product.dimensions_raw:
        missing.append("dimensions")
    if not (product.material_raw and str(product.material_raw).strip()):
        missing.append("material")
    if not (product.color_raw and str(product.color_raw).strip()):
        missing.append("color")
    if not (product.brand and str(product.brand).strip()):
        missing.append("brand")
    return missing


def _coerce_item_price(*candidates: Any) -> float | None:
    """Return first valid positive price from candidate raw values."""
    for raw in candidates:
        value = normalize_price_amount(raw)
        if value is not None:
            return value
    return None


_NON_SEK_CURRENCY_RE = re.compile(r"(?i)(?:\beur\b|€|\busd\b|\$|\bgbp\b|£|\bdkk\b|\bnok\b|\bchf\b)")
_SEK_CURRENCY_RE = re.compile(r"(?i)(?:\bsek\b|\bkr\b|\bkron(?:a|or)\b)")


def _currency_evidence_from_raw(raw: Any) -> str | None:
    """Infer currency evidence from raw price text.

    Returns:
      - "sek" when there is explicit SEK/kr evidence
      - "non_sek" when there is explicit foreign-currency evidence
      - None when no clear currency token is present
    """
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    if _NON_SEK_CURRENCY_RE.search(text):
        return "non_sek"
    if _SEK_CURRENCY_RE.search(text):
        return "sek"
    return None


def _resolve_item_currency(product: Any) -> tuple[str | None, str]:
    """Resolve item currency with strict SEK-only policy.

    Returns (currency, reason):
      - ("SEK", "ok") for accepted SEK prices
      - (None, "mismatch") for explicit non-SEK evidence
      - (None, "unknown") when currency cannot be confidently determined
    """
    evidence = _currency_evidence_from_raw(getattr(product, "price_raw", None))
    # Raw text evidence is the strongest signal. It catches cases where parser
    # defaults (or stale fields) would otherwise mask explicit foreign currency.
    if evidence == "non_sek":
        return None, "mismatch"

    raw_currency = getattr(product, "price_currency", None)
    validated = validate_currency(raw_currency)
    if validated:
        return validated, "ok"

    if evidence == "sek":
        return "SEK", "ok"

    # Explicit, non-accepted currency from extractor.
    if raw_currency is not None and str(raw_currency).strip():
        return None, "mismatch"
    return None, "unknown"


def _base_url(source: dict) -> str:
    """Get and normalize the base URL, ensuring it has a protocol."""
    url = (source.get("baseUrl") or source.get("base_url") or "").strip()
    if url and not url.startswith(('http://', 'https://')):
        url = 'https://' + url
    return url


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


# ============================================================================
# CONCURRENT EXTRACTION HELPERS
# ============================================================================

# Default number of concurrent fetch+extract workers per source
DEFAULT_CONCURRENCY = 5
MAX_CONCURRENCY = 15


@dataclass
class _ExtractionResult:
    """Result from a single fetch+extract worker."""
    url: str
    fetch_ok: bool = False
    product: Any = None
    html_hash: str | None = None
    error_msg: str | None = None
    error_type: str | None = None  # "fetch_blocked", "fetch_error", "parse"
    page_signals: dict | None = None
    method: str | None = None
    fetch_method: str = "http"
    fetch_elapsed_ms: int = 0
    fetch_final_url: str | None = None
    fetch_text: str | None = None


def _fetch_and_extract_one(
    url: str,
    fetcher: "PoliteFetcher",
    base_url: str,
    allowlist_policy: dict | None,
    robots_respect: bool,
    rate_limit_rps: float | None,
    source_id: str,
    extracted_at_iso: str,
    active_recipe: dict | None,
    known_hash: str | None = None,
) -> _ExtractionResult:
    """
    Fetch and extract a single URL. Designed to run in a thread pool.

    Returns an _ExtractionResult with all data needed by the main thread
    to update stats, write to Firestore, and collect items.

    If known_hash is provided and matches the fetched content, extraction is
    skipped (incremental recrawl optimisation - A3).
    """
    result = _ExtractionResult(url=url)

    # 1) Fetch
    try:
        r = fetcher.fetch(
            url,
            base_url=base_url,
            allowlist_policy=allowlist_policy,
            robots_respect=robots_respect,
            rate_limit_rps=rate_limit_rps,
        )
        result.fetch_ok = True
        result.html_hash = r.html_hash
        result.fetch_elapsed_ms = r.elapsed_ms
        result.fetch_method = r.method
        result.fetch_final_url = r.final_url
        result.fetch_text = r.text
    except FetchError as e:
        msg = str(e)
        if "robots" in msg.lower() or "allowlist" in msg.lower():
            result.error_type = "fetch_blocked"
        else:
            result.error_type = "fetch_error"
        result.error_msg = msg
        return result

    # 1b) Incremental skip: if content hash matches previous crawl, skip extraction
    if known_hash and r.html_hash == known_hash:
        result.error_type = "skipped_unchanged"
        result.error_msg = "Content unchanged (hash match)"
        return result

    # 2) Extract
    product = extract_product_from_html(
        source_id=source_id,
        fetched_url=url,
        final_url=r.final_url,
        html=r.text,
        extracted_at_iso=extracted_at_iso,
        recipe=active_recipe,
    )

    if product is None:
        sig = extract_page_signals(r.text, final_url=r.final_url)
        result.error_type = "parse"
        result.error_msg = (
            f"No product extracted (JSON-LD blocks: {len(sig.jsonld_blocks)}, og:type: {sig.og_type})"
        )
        result.page_signals = {
            "finalUrl": r.final_url,
            "canonical": sig.canonical_url,
            "ogUrl": sig.og_url,
            "ogType": sig.og_type,
            "ogImagesCount": len(sig.og_images),
            "jsonldBlockCount": len(sig.jsonld_blocks),
            "embeddedJsonCandidatesCount": len(sig.embedded_json_candidates),
        }
        return result

    # 3) Success – attach product and snapshot data
    result.product = product
    result.method = product.method
    return result


def run_crawl_ingestion(source_id: str, source: dict, *, run_id: str | None = None) -> dict:
    """
    Run crawl ingestion for a source.

    Supports two configuration formats:
    1. New format (derived): Auto-discovered configuration with baseUrl, seedUrl, strategy
    2. Legacy format: Direct fields like baseUrl, seedUrls, seedType
    
    Required source fields (legacy):
    - baseUrl
    - seedUrls (1-3 URLs; sitemap or sofa category)
    - allowlistPolicy (recommended)
    
    Args:
        source_id: Firestore document ID of the source
        source: Source configuration dict
        run_id: Optional correlation ID for logs (passed from API caller)
    """
    # Use provided run_id for correlation, or generate one
    correlation_id = run_id or "auto"
    log = CrawlLogger(source_id, run_id=correlation_id)
    log.header(f"CRAWL INGESTION: {source_id}")
    
    db = get_firestore_client()
    db_run_id = create_run(db, source_id, "running")
    started_at = time.time()

    # --- Stop-signal helper -------------------------------------------
    _stop_check_counter = 0

    def _is_stopped(every: int = 10) -> bool:
        """Check Firestore every *every* calls for a 'stopped' status.

        This avoids hammering Firestore on every single URL while still
        being responsive (within ~10 iterations).
        """
        nonlocal _stop_check_counter
        _stop_check_counter += 1
        if _stop_check_counter % every != 0:
            return False
        try:
            snap = db.collection("ingestionRuns").document(db_run_id).get()
            if snap.exists and snap.to_dict().get("status") == "stopped":
                return True
        except Exception:
            pass
        return False

    def _handle_stop(log, stats):
        """Finalise a stopped run — update Firestore and return result dict."""
        log.warning("Stop signal received — aborting crawl")
        stats["stoppedByUser"] = True
        update_run(db, db_run_id, "stopped", stats, error_summary="Stopped by user")
        return {"runId": db_run_id, "status": "stopped", "stats": stats}
    # ------------------------------------------------------------------
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
        "descriptionRate": 0.0,
        "dimensionsRate": 0.0,
        "materialRate": 0.0,
        "browserFetchCount": 0,
        "invalidPriceSkipped": 0,
        "currencyMismatchSkipped": 0,
        "currencyUnknownSkipped": 0,
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
    category_filter = _source_category_filter(source)  # NEW: Category filter for focused crawling
    rate_limit_rps = _source_rate_limit(source)
    allowlist_policy = _allowlist_policy(source)
    robots_respect = _robots_respect(source)
    use_browser_fallback = _source_browser_fallback(source)
    enable_quality_refetch = _source_quality_refetch(source)
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
    if category_filter:
        log.info(f"Category filter: {category_filter[:5]}{'...' if len(category_filter) > 5 else ''}")
    else:
        log.info("Category filter: (none - all categories)")
    log.info(f"Rate limit: {rate_limit_rps or 'default'} req/s")
    log.info(f"Robots.txt respect: {robots_respect}")
    log.info(f"Browser fallback: {use_browser_fallback}")
    log.info(f"Quality refetch: {enable_quality_refetch}")

    if not base_url:
        log.error("baseUrl is required but missing!")
        update_run(db, db_run_id, "failed", stats, error_summary="baseUrl required for crawl sources")
        return {"runId": db_run_id, "status": "failed", "stats": stats, "errorSummary": "baseUrl required"}
    
    # Auto-discover mode: if no seedUrls and no derived config, use sitemap discovery from baseUrl
    auto_discover = not seed_urls and not use_derived
    if auto_discover:
        seed_type = "sitemap"  # Force sitemap discovery mode

    max_urls = int(source.get("maxUrlsPerRun") or 200)
    max_pages = int(source.get("maxPagesPerRun") or 50)
    max_depth = int(source.get("maxDepth") or 2)

    # Use a realistic browser user-agent by default.  Many sites (especially
    # those behind Cloudflare) will hard-block requests with a bot-style UA.
    _DEFAULT_UA = (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/131.0.0.0 Safari/537.36"
    )
    fetcher = PoliteFetcher(
        user_agent=user_agent or _DEFAULT_UA,
        browser_fallback=use_browser_fallback,
    )
    extracted_at_iso = _utc_now_iso()

    try:
        # 1) Discover
        log.section("PHASE 1: URL Discovery")
        job_id = create_job(
            db,
            source_id,
            db_run_id,
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
                    max_urls=200_000,  # Increased to allow scanning more sitemaps when filtering
                    category_filter=category_filter if category_filter else None,
                    min_matching_urls=2000,  # Get at least 2000 matching products
                )
                if discovered:
                    # Filter by seed path pattern if present
                    if derived_seed_path_pattern:
                        original_count = len(discovered)
                        unfiltered_discovered = discovered  # Keep original for fallback
                        discovered = [
                            d for d in discovered 
                            if derived_seed_path_pattern.lower() in d.url.lower()
                        ]
                        log.info(f"Filtered by path pattern '{derived_seed_path_pattern}': {original_count} -> {len(discovered)}")
                        
                        # FALLBACK: If filtering removed ALL URLs, try fallback strategies
                        if not discovered and original_count > 0:
                            log.warning(f"Path filter removed all {original_count} URLs!")
                            
                            # Fallback strategy 1: Try category crawl from seed URL
                            log.info("Fallback: Trying category crawl from seed URL...")
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
                            
                            # Fallback strategy 2: If crawl also yields nothing, use unfiltered sitemap URLs
                            if not discovered:
                                log.warning("Crawl fallback found no URLs, using unfiltered sitemap URLs")
                                discovered = unfiltered_discovered
                                log.info(f"Using {len(discovered)} unfiltered sitemap URLs")
                            else:
                                log.success(f"Found {len(discovered)} URLs from crawl fallback")
                    
                    if discovered:
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
                max_urls=200_000,  # Increased to allow scanning more sitemaps when filtering
                category_filter=category_filter if category_filter else None,
                min_matching_urls=2000,  # Get at least 2000 matching products
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
            update_run(db, db_run_id, "failed", stats, error_summary="No discovery method available")
            return {"runId": db_run_id, "status": "failed", "stats": stats, "errorSummary": "No discovery method available"}

        # ===== APPLY CATEGORY FILTER (for non-sitemap discovery) =====
        # For sitemap discovery, the filter is applied during discovery for efficiency.
        # For other discovery methods (category crawl, manual), apply the filter here.
        # Check if filter was already applied by checking the log messages or URL count
        if category_filter and discovered and seed_type != "sitemap" and not use_derived:
            pre_filter_count = len(discovered)
            discovered = _filter_urls_by_category(discovered, category_filter, log)
            if not discovered and pre_filter_count > 0:
                log.warning(f"Category filter removed ALL {pre_filter_count} URLs! Check your filter patterns.")
                log.info(f"Configured patterns: {category_filter}")
                # Don't fail - just continue with empty list to record the run

        # Persist discovered URLs and select product candidates
        log.info("Filtering for product candidates...")
        product_candidates: list[str] = []
        high_confidence_candidates: list[str] = []
        
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
                high_confidence_candidates.append(d.url)
        
        # If category filter was applied, we already filtered for relevant URLs - use ALL of them
        # Otherwise fall back to confidence-based filtering
        if category_filter:
            log.info(f"Category filter active - using all {len(discovered)} discovered URLs as candidates")
            product_candidates = [d.url for d in discovered]
        elif high_confidence_candidates:
            product_candidates = high_confidence_candidates
        else:
            log.info("No high-confidence product URLs, using all discovered URLs")
            product_candidates = [d.url for d in discovered]

        # No artificial limit - process ALL discovered products
        # The sitemap discovery already respects min_matching_urls for efficiency
        stats["urlsDiscovered"] = len(discovered)
        stats["urlsCandidateProducts"] = len(product_candidates)
        log.success(f"Selected {len(product_candidates)} product candidates")
        update_job(db, job_id, "succeeded")
        
        # Update run with discovery results so UI shows progress
        update_run(db, db_run_id, "running", stats)

        if not product_candidates:
            log.warning("No product candidates to extract - ending early")
            log.summary(stats)
            update_run(db, db_run_id, "succeeded", stats)
            return {"runId": db_run_id, "status": "succeeded", "stats": stats}

        # ──────────────────────────────────────────────────────────────
        # PHASE 1.5: Batch Extraction from Category Pages
        # ──────────────────────────────────────────────────────────────
        # Many retailers embed the full product catalog in the initial
        # HTML of category pages as a window.* JS state variable.
        # We fetch the seed/category page once and try to extract all
        # products from the embedded state.  Products found here are
        # added directly; their URLs are removed from the individual-
        # page extraction queue to avoid duplicates.
        batch_items: list[dict] = []
        batch_urls_extracted: set[str] = set()
        batch_category_pages: list[str] = []
        batch_browser_fetches = 0
        batch_description_count = 0
        batch_dimensions_count = 0
        batch_material_count = 0
        batch_completeness_sum = 0.0

        # Decide which pages to try: seed URL + any explicit category pages
        if use_derived and derived_seed_url:
            batch_category_pages.append(derived_seed_url)
        elif seed_urls:
            batch_category_pages.extend(seed_urls[:3])
        else:
            # Fallback: use the base_url
            batch_category_pages.append(base_url)

        if batch_category_pages:
            log.section("PHASE 1.5: Batch Extraction from Category Pages")
            for cat_url in batch_category_pages:
                try:
                    log.info(f"Fetching category page: {cat_url}")
                    resp = fetcher.fetch(
                        cat_url,
                        rate_limit_rps=rate_limit_rps,
                        robots_respect=robots_respect,
                    )
                    if not resp or not resp.text:
                        log.warning(f"Empty response from {cat_url}")
                        continue

                    batch_products = extract_products_batch_from_html(
                        source_id=source_id,
                        fetched_url=cat_url,
                        final_url=resp.final_url or cat_url,
                        html=resp.text,
                        extracted_at_iso=extracted_at_iso,
                    )

                    if not batch_products:
                        log.info(f"No embedded state products on {cat_url}")
                        continue

                    if resp.method == "browser":
                        batch_browser_fetches += len(batch_products)

                    log.success(f"Batch extracted {len(batch_products)} products from embedded state on {cat_url}")

                    for product in batch_products:
                        batch_completeness_sum += float(product.completeness_score or 0.0)
                        if product.description:
                            batch_description_count += 1
                        if product.dimensions_raw:
                            batch_dimensions_count += 1
                        if product.material_raw:
                            batch_material_count += 1
                        # Normalise into items schema (same as Phase 2)
                        canon = canonicalize_url(product.canonical_url)
                        title = product.title.strip()[:500] if product.title else "Untitled"
                        img_objs = [
                            {"url": u, "alt": title[:200]}
                            for u in (product.images or [])
                            if isinstance(u, str) and u
                        ]
                        price_amount = _coerce_item_price(
                            product.price_amount, product.price_original, product.price_raw
                        )
                        if price_amount is None or price_amount <= 0:
                            stats["invalidPriceSkipped"] = (
                                int(stats.get("invalidPriceSkipped") or 0) + 1
                            )
                            continue
                        price_currency, currency_reason = _resolve_item_currency(product)
                        if price_currency is None:
                            if currency_reason == "mismatch":
                                stats["currencyMismatchSkipped"] = int(stats.get("currencyMismatchSkipped") or 0) + 1
                                log.detail(
                                    f"Skipping item with non-SEK currency evidence: "
                                    f"{(product.price_currency or product.price_raw or '')[:60]}"
                                )
                            else:
                                stats["currencyUnknownSkipped"] = int(stats.get("currencyUnknownSkipped") or 0) + 1
                                log.detail(
                                    f"Skipping item with unknown currency (no SEK evidence): "
                                    f"{(product.price_raw or '')[:60]}"
                                )
                            continue

                        batch_items.append({
                            "sourceId": source_id,
                            "sourceType": "crawl",
                            "sourceUrl": product.product_url or cat_url,
                            "canonicalUrl": canon,
                            "title": title,
                            "brand": (product.brand or "").strip() or None,
                            "descriptionShort": clean_description_text(product.description),
                            "priceAmount": price_amount,
                            "priceCurrency": price_currency,
                            "dimensionsCm": product.dimensions_raw,
                            "sizeClass": normalize_size_class(None, None, title=title),
                            "material": normalize_material(product.material_raw) or "mixed",
                            "colorFamily": normalize_color_family(product.color_raw) or infer_color_from_title(product.title) or "multi",
                            "styleTags": [],
                            "newUsed": "new",
                            "deliveryComplexity": "medium",
                            "smallSpaceFriendly": False,
                            "modular": False,
                            "ecoTags": [],
                            "availabilityStatus": product.availability or "unknown",
                            "outboundUrl": product.product_url or cat_url,
                            "images": img_objs,
                            "lastUpdatedAt": None,
                            "firstSeenAt": None,
                            "lastSeenAt": None,
                            "isActive": True,
                            "breadcrumbs": product.breadcrumbs or [],
                            "productType": product.product_type,
                            "retailerCategoryLabel": product.retailer_category_label,
                            "facets": product.facets or {},
                            "variants": product.variants or [],
                            "sku": product.sku,
                            "mpn": product.mpn,
                            "gtin": product.gtin,
                            "modelName": product.model_name,
                            "priceOriginal": product.price_original,
                            "discountPct": product.discount_pct,
                            "deliveryEta": product.delivery_eta,
                            "shippingCost": product.shipping_cost,
                            "enrichmentEvidence": product.enrichment_evidence or [],
                            # Rich furniture specs
                            "seatHeightCm": product.seat_height_cm,
                            "seatDepthCm": product.seat_depth_cm,
                            "seatWidthCm": product.seat_width_cm,
                            "seatCount": product.seat_count,
                            "weightKg": product.weight_kg,
                            "frameMaterial": product.frame_material,
                            "coverMaterial": product.cover_material,
                            "legMaterial": product.leg_material,
                            "cushionFilling": product.cushion_filling,
                            "extractionMeta": {
                                "method": "browser" if resp.method == "browser" else product.method,
                                "extractorMethod": product.method,
                                "completeness": float(product.completeness_score or 0.0),
                                "missingFields": _missing_fields_for_product(product),
                                "fetchMethod": resp.method,
                                "extractedAt": product.extracted_at,
                            },
                        })
                        # Track canonical URLs to skip in Phase 2
                        if canon:
                            batch_urls_extracted.add(canon)
                        if product.product_url:
                            batch_urls_extracted.add(product.product_url)

                except Exception as e:
                    log.warning(f"Batch extraction failed for {cat_url}: {e}")

            if batch_items:
                log.success(f"Total batch-extracted: {len(batch_items)} products from {len(batch_category_pages)} category page(s)")
                stats["batchExtracted"] = len(batch_items)

                # Remove batch-extracted URLs from the per-page queue to avoid duplicates
                before = len(product_candidates)
                product_candidates = [
                    u for u in product_candidates
                    if u not in batch_urls_extracted
                    and canonicalize_url(u) not in batch_urls_extracted
                ]
                deduped = before - len(product_candidates)
                if deduped:
                    log.info(f"Removed {deduped} URLs already batch-extracted from Phase 2 queue")
            else:
                log.info("No products found via batch extraction, proceeding with per-page extraction")

        # 2) Extract (concurrent: multiple pages fetched + extracted in parallel)
        log.section("PHASE 2: Product Extraction (Concurrent)")
        concurrency = min(int(source.get("concurrency") or DEFAULT_CONCURRENCY), MAX_CONCURRENCY)
        log.info(f"Workers: {concurrency} concurrent threads")
        job_id = create_job(
            db,
            source_id,
            db_run_id,
            "extract",
            {"count": len(product_candidates), "concurrency": concurrency},
            "running",
        )
        items: list[dict] = []
        successes = 0
        method_counts = {"jsonld": 0, "embedded_json": 0, "embedded_state": 0, "recipe": 0, "dom": 0}
        completeness_sum = 0.0
        blocked_count = 0
        browser_fetch_count = 0
        description_count = 0
        dimensions_count = 0
        material_count = 0
        active_recipe = None
        try:
            rdoc = get_active_recipe(db, source_id=source_id)
            if rdoc and isinstance(rdoc.get("recipeJson"), dict):
                active_recipe = rdoc["recipeJson"]
                log.info(f"Using active recipe: {rdoc.get('recipeId', 'unknown')}")
        except Exception:
            active_recipe = None
        
        total = len(product_candidates)
        log.info(f"Extracting from {total} URLs with {concurrency} workers...")
        stats_update_interval = 10  # Update Firestore every N completed for real-time UI
        extraction_start = time.time()

        # A3: Load known hashes for incremental recrawl
        known_hashes: dict[str, str] = {}
        incremental = source.get("incremental", True)  # default on
        skipped_unchanged = 0
        if incremental:
            try:
                known_hashes = get_known_hashes(db, source_id=source_id, urls=product_candidates[:500])
                if known_hashes:
                    log.info(f"Incremental mode: {len(known_hashes)} URLs have known hashes (will skip if unchanged)")
            except Exception:
                log.warning("Failed to load known hashes, proceeding without incremental skip")

        # Submit all URLs to thread pool for concurrent fetch + extract
        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = {
                executor.submit(
                    _fetch_and_extract_one,
                    url, fetcher, base_url, allowlist_policy,
                    robots_respect, rate_limit_rps, source_id,
                    extracted_at_iso, active_recipe,
                    known_hashes.get(url),
                ): url
                for url in product_candidates
            }

            completed = 0
            for future in as_completed(futures):
                # --- Check for user-initiated stop ---
                if _is_stopped(every=10):
                    # Cancel remaining futures
                    for f in futures:
                        if not f.done():
                            f.cancel()
                    return _handle_stop(log, stats)

                completed += 1
                er = future.result()  # _ExtractionResult (never raises)

                # --- Progress + stats updates ---
                if completed == 1 or completed == total or completed % 5 == 0:
                    elapsed = time.time() - extraction_start
                    rate = completed / elapsed if elapsed > 0 else 0
                    eta = int((total - completed) / rate) if rate > 0 else 0
                    url_short = er.url[:55] + "..." if len(er.url) > 55 else er.url
                    log.progress(completed, total, f"{url_short}  ({rate:.1f}/s, ETA {eta}s)")

                if completed % stats_update_interval == 0:
                    stats["success"] = successes
                    stats["fetched"] = stats.get("fetched", 0)
                    update_run(db, db_run_id, "running", stats)

                # --- Handle incremental skip (A3) ---
                if er.error_type == "skipped_unchanged":
                    skipped_unchanged += 1
                    continue

                # --- Handle fetch errors ---
                if er.error_type == "fetch_blocked":
                    stats["failed"] += 1
                    blocked_count += 1
                    log.warning(f"Blocked: {er.url[:50]}... ({(er.error_msg or '')[:40]})")
                    record_extraction_failure(
                        db, source_id=source_id, url=er.url,
                        failure_type="fetch", error=er.error_msg or "Blocked",
                        html_hash=None, signals={"url": er.url, "finalUrl": None},
                    )
                    continue

                if er.error_type == "fetch_error":
                    stats["failed"] += 1
                    log.error(f"Fetch failed: {er.url[:50]}... ({(er.error_msg or '')[:40]})")
                    record_extraction_failure(
                        db, source_id=source_id, url=er.url,
                        failure_type="fetch", error=er.error_msg or "Fetch error",
                        html_hash=None, signals={"url": er.url, "finalUrl": None},
                    )
                    continue

                # Fetch succeeded
                stats["fetched"] = stats.get("fetched", 0) + 1
                stats["urlsExtracted"] += 1

                # --- Handle extraction failures ---
                if er.error_type == "parse":
                    stats["failed"] += 1
                    log.warning(f"No product: {er.url[:50]}... ({(er.error_msg or '')[:50]})")
                    record_extraction_failure(
                        db, source_id=source_id, url=er.url,
                        failure_type="parse",
                        error=er.error_msg or "No product extracted",
                        html_hash=er.html_hash,
                        signals=er.page_signals,
                    )
                    continue

                # --- Success! ---
                product = er.product
                successes += 1
                method_counts[product.method] = method_counts.get(product.method, 0) + 1
                completeness_sum += float(product.completeness_score or 0.0)
                if er.fetch_method == "browser":
                    browser_fetch_count += 1
                if product.description:
                    description_count += 1
                if product.dimensions_raw:
                    dimensions_count += 1
                if product.material_raw:
                    material_count += 1

                # A3: Store content hash for future incremental recrawl
                if er.html_hash and incremental:
                    try:
                        update_crawl_url_hash(db, url=er.url, html_hash=er.html_hash, source_id=source_id)
                    except Exception:
                        pass  # Best-effort

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

                # Map into existing `items` schema
                canon = canonicalize_url(product.canonical_url)
                title = product.title.strip()[:500] if product.title else "Untitled"
                img_objs = [{"url": u, "alt": title[:200]} for u in (product.images or []) if isinstance(u, str) and u]
                price_amount = _coerce_item_price(
                    product.price_amount, product.price_original, product.price_raw
                )
                if price_amount is None or price_amount <= 0:
                    stats["invalidPriceSkipped"] = (
                        int(stats.get("invalidPriceSkipped") or 0) + 1
                    )
                    continue
                price_currency, currency_reason = _resolve_item_currency(product)
                if price_currency is None:
                    if currency_reason == "mismatch":
                        stats["currencyMismatchSkipped"] = int(stats.get("currencyMismatchSkipped") or 0) + 1
                        log.detail(
                            f"Skipping item with non-SEK currency evidence: "
                            f"{(product.price_currency or product.price_raw or '')[:60]}"
                        )
                    else:
                        stats["currencyUnknownSkipped"] = int(stats.get("currencyUnknownSkipped") or 0) + 1
                        log.detail(
                            f"Skipping item with unknown currency (no SEK evidence): "
                            f"{(product.price_raw or '')[:60]}"
                        )
                    continue
                dims = product.dimensions_raw
                width_cm = (dims or {}).get("w") if dims else None
                items.append(
                    {
                        "sourceId": source_id,
                        "sourceType": "crawl",
                        "sourceUrl": er.url,
                        "canonicalUrl": canon,
                        "title": title,
                        "brand": (product.brand or "").strip() or None,
                        "descriptionShort": clean_description_text(product.description),
                        "priceAmount": price_amount,
                        "priceCurrency": price_currency,
                        "dimensionsCm": dims,
                        "sizeClass": normalize_size_class(None, width_cm, title=title),
                        "material": normalize_material(product.material_raw) or "mixed",
                        "colorFamily": normalize_color_family(product.color_raw) or infer_color_from_title(product.title) or "multi",
                        "styleTags": [],
                        "newUsed": "new",
                        "deliveryComplexity": "medium",
                        "smallSpaceFriendly": False,
                        "modular": False,
                        "ecoTags": [],
                        "availabilityStatus": product.availability or "unknown",
                        "outboundUrl": er.url,
                        "images": img_objs,
                        "lastUpdatedAt": None,
                        "firstSeenAt": None,
                        "lastSeenAt": None,
                        "isActive": True,
                        # EPIC B: Enriched metadata
                        "breadcrumbs": product.breadcrumbs or [],
                        "productType": product.product_type,
                        "retailerCategoryLabel": product.retailer_category_label,
                        "facets": product.facets or {},
                        "variants": product.variants or [],
                        "sku": product.sku,
                        "mpn": product.mpn,
                        "gtin": product.gtin,
                        "modelName": product.model_name,
                        "priceOriginal": product.price_original,
                        "discountPct": product.discount_pct,
                        "deliveryEta": product.delivery_eta,
                        "shippingCost": product.shipping_cost,
                        "enrichmentEvidence": product.enrichment_evidence or [],
                        # Rich furniture specs
                        "seatHeightCm": product.seat_height_cm,
                        "seatDepthCm": product.seat_depth_cm,
                        "seatWidthCm": product.seat_width_cm,
                        "seatCount": product.seat_count,
                        "weightKg": product.weight_kg,
                        "frameMaterial": product.frame_material,
                        "coverMaterial": product.cover_material,
                        "legMaterial": product.leg_material,
                        "cushionFilling": product.cushion_filling,
                        "extractionMeta": {
                            "method": "browser" if er.fetch_method == "browser" else product.method,
                            "extractorMethod": product.method,
                            "completeness": float(product.completeness_score or 0.0),
                            "missingFields": _missing_fields_for_product(product),
                            "fetchMethod": er.fetch_method,
                            "extractedAt": product.extracted_at,
                        },
                    }
                )

        extraction_elapsed = time.time() - extraction_start
        stats["success"] = successes
        stats["skippedUnchanged"] = skipped_unchanged
        stats["extractionDurationSec"] = round(extraction_elapsed, 1)
        stats["extractionRatePerSec"] = round(completed / extraction_elapsed, 2) if extraction_elapsed > 0 else 0
        stats["concurrency"] = concurrency
        stats["blockedCount"] = blocked_count
        stats["blockedRate"] = (blocked_count / stats["urlsCandidateProducts"]) if stats["urlsCandidateProducts"] else 0.0
        update_job(db, job_id, "succeeded")
        
        log.info(f"Extraction complete: {successes} products from {stats['urlsExtracted']} pages in {extraction_elapsed:.1f}s ({stats['extractionRatePerSec']}/s)")
        if successes > 0 or batch_items:
            log.info(f"Methods used: JSON-LD={method_counts.get('jsonld', 0)}, EmbeddedJSON={method_counts.get('embedded_json', 0)}, EmbeddedState={method_counts.get('embedded_state', 0)}, DOM={method_counts.get('dom', 0)}")

        # 3) Upsert
        # Merge batch-extracted items from Phase 1.5 into the items list
        if batch_items:
            items.extend(batch_items)
            log.info(f"Added {len(batch_items)} batch-extracted items (total: {len(items)})")
            method_counts["embedded_state"] = method_counts.get("embedded_state", 0) + len(batch_items)
            completeness_sum += batch_completeness_sum
            browser_fetch_count += batch_browser_fetches
            description_count += batch_description_count
            dimensions_count += batch_dimensions_count
            material_count += batch_material_count

        # Optional quality pass: reprocess stale low-completeness items with browser fallback.
        refetch_successes = 0
        refetch_failed = 0
        if enable_quality_refetch:
            try:
                from app.refetch_queue import get_refetch_candidates

                refetch_limit = int(source.get("qualityRefetchLimit") or 100)
                candidates = get_refetch_candidates(db, source_id=source_id, limit=refetch_limit)
                stats["refetchCandidates"] = len(candidates)
                if candidates:
                    log.section("PHASE 2.5: Quality Refetch")
                    if not use_browser_fallback:
                        log.warning("Quality refetch requested but useBrowserFallback is disabled; skipping")
                    else:
                        candidate_urls: list[str] = []
                        already_queued = set(product_candidates)
                        for cand in candidates:
                            refetch_url = (
                                cand.get("sourceUrl")
                                or cand.get("outboundUrl")
                                or cand.get("canonicalUrl")
                            )
                            if not refetch_url or refetch_url in already_queued:
                                continue
                            already_queued.add(refetch_url)
                            candidate_urls.append(refetch_url)
                        log.info(
                            f"Reprocessing {len(candidate_urls)} low-quality candidate URLs with browser fallback"
                        )
                        for refetch_url in candidate_urls:
                            rer = _fetch_and_extract_one(
                                refetch_url,
                                fetcher,
                                base_url,
                                allowlist_policy,
                                robots_respect,
                                rate_limit_rps,
                                source_id,
                                extracted_at_iso,
                                active_recipe,
                                None,
                            )
                            if rer.error_type or rer.product is None:
                                refetch_failed += 1
                                continue
                            rp = rer.product
                            refetch_successes += 1
                            method_counts[rp.method] = method_counts.get(rp.method, 0) + 1
                            completeness_sum += float(rp.completeness_score or 0.0)
                            if rer.fetch_method == "browser":
                                browser_fetch_count += 1
                            if rp.description:
                                description_count += 1
                            if rp.dimensions_raw:
                                dimensions_count += 1
                            if rp.material_raw:
                                material_count += 1

                            canon = canonicalize_url(rp.canonical_url)
                            title = rp.title.strip()[:500] if rp.title else "Untitled"
                            img_objs = [
                                {"url": u, "alt": title[:200]}
                                for u in (rp.images or [])
                                if isinstance(u, str) and u
                            ]
                            price_amount = _coerce_item_price(
                                rp.price_amount, rp.price_original, rp.price_raw
                            )
                            if price_amount is None or price_amount <= 0:
                                stats["invalidPriceSkipped"] = (
                                    int(stats.get("invalidPriceSkipped") or 0) + 1
                                )
                                continue
                            price_currency, currency_reason = _resolve_item_currency(rp)
                            if price_currency is None:
                                if currency_reason == "mismatch":
                                    stats["currencyMismatchSkipped"] = int(stats.get("currencyMismatchSkipped") or 0) + 1
                                    log.detail(
                                        f"Skipping refetch item with non-SEK currency evidence: "
                                        f"{(rp.price_currency or rp.price_raw or '')[:60]}"
                                    )
                                else:
                                    stats["currencyUnknownSkipped"] = int(stats.get("currencyUnknownSkipped") or 0) + 1
                                    log.detail(
                                        f"Skipping refetch item with unknown currency (no SEK evidence): "
                                        f"{(rp.price_raw or '')[:60]}"
                                    )
                                continue
                            dims = rp.dimensions_raw
                            width_cm = (dims or {}).get("w") if dims else None
                            items.append(
                                {
                                    "sourceId": source_id,
                                    "sourceType": "crawl",
                                    "sourceUrl": refetch_url,
                                    "canonicalUrl": canon,
                                    "title": title,
                                    "brand": (rp.brand or "").strip() or None,
                                    "descriptionShort": clean_description_text(rp.description),
                                    "priceAmount": price_amount,
                                    "priceCurrency": price_currency,
                                    "dimensionsCm": dims,
                                    "sizeClass": normalize_size_class(None, width_cm, title=title),
                                    "material": normalize_material(rp.material_raw) or "mixed",
                                    "colorFamily": normalize_color_family(rp.color_raw)
                                    or infer_color_from_title(rp.title)
                                    or "multi",
                                    "styleTags": [],
                                    "newUsed": "new",
                                    "deliveryComplexity": "medium",
                                    "smallSpaceFriendly": False,
                                    "modular": False,
                                    "ecoTags": [],
                                    "availabilityStatus": rp.availability or "unknown",
                                    "outboundUrl": refetch_url,
                                    "images": img_objs,
                                    "lastUpdatedAt": None,
                                    "firstSeenAt": None,
                                    "lastSeenAt": None,
                                    "isActive": True,
                                    "breadcrumbs": rp.breadcrumbs or [],
                                    "productType": rp.product_type,
                                    "retailerCategoryLabel": rp.retailer_category_label,
                                    "facets": rp.facets or {},
                                    "variants": rp.variants or [],
                                    "sku": rp.sku,
                                    "mpn": rp.mpn,
                                    "gtin": rp.gtin,
                                    "modelName": rp.model_name,
                                    "priceOriginal": rp.price_original,
                                    "discountPct": rp.discount_pct,
                                    "deliveryEta": rp.delivery_eta,
                                    "shippingCost": rp.shipping_cost,
                                    "enrichmentEvidence": rp.enrichment_evidence or [],
                                    # Rich furniture specs
                                    "seatHeightCm": rp.seat_height_cm,
                                    "seatDepthCm": rp.seat_depth_cm,
                                    "seatWidthCm": rp.seat_width_cm,
                                    "seatCount": rp.seat_count,
                                    "weightKg": rp.weight_kg,
                                    "frameMaterial": rp.frame_material,
                                    "coverMaterial": rp.cover_material,
                                    "legMaterial": rp.leg_material,
                                    "cushionFilling": rp.cushion_filling,
                                    "extractionMeta": {
                                        "method": "browser" if rer.fetch_method == "browser" else rp.method,
                                        "extractorMethod": rp.method,
                                        "completeness": float(rp.completeness_score or 0.0),
                                        "missingFields": _missing_fields_for_product(rp),
                                        "fetchMethod": rer.fetch_method,
                                        "extractedAt": rp.extracted_at,
                                    },
                                }
                            )
                stats["refetchExtracted"] = refetch_successes
                stats["refetchFailed"] = refetch_failed
            except Exception as refetch_err:
                log.warning(f"Quality refetch step failed: {refetch_err}")

        total_successes = successes + len(batch_items) + refetch_successes
        stats["success"] = total_successes
        stats["jsonldRate"] = (method_counts.get("jsonld", 0) / total_successes) if total_successes else 0
        stats["embeddedJsonRate"] = (method_counts.get("embedded_json", 0) / total_successes) if total_successes else 0
        stats["recipeRate"] = (method_counts.get("recipe", 0) / total_successes) if total_successes else 0
        stats["domRate"] = (method_counts.get("dom", 0) / total_successes) if total_successes else 0
        stats["avgCompleteness"] = (completeness_sum / total_successes) if total_successes else 0.0
        stats["descriptionRate"] = (description_count / total_successes) if total_successes else 0.0
        stats["dimensionsRate"] = (dimensions_count / total_successes) if total_successes else 0.0
        stats["materialRate"] = (material_count / total_successes) if total_successes else 0.0
        stats["browserFetchCount"] = browser_fetch_count

        log.section("PHASE 3: Database Upsert")
        job_id = create_job(db, source_id, db_run_id, "upsert", {"count": len(items)}, "running")
        log.info(f"Writing {len(items)} items to Firestore...")
        upserted, failed, item_ids = write_items(db, items, source_id)
        stats["upserted"] = upserted
        stats["failed"] = int(stats.get("failed") or 0) + failed
        stats["normalized"] = len(items)
        update_job(db, job_id, "succeeded")
        log.success(f"Upserted {upserted} items, {failed} failed")

        # 4) Auto-classify + Gold promotion
        log.section("PHASE 4: Classification + Gold Promotion")
        classified = 0
        gold_promoted = 0
        review_queued = 0
        try:
            from app.sorting.policy import classify_and_decide
            log.info(f"Classifying {len(items)} items...")
            for item_id, item_data in zip(item_ids, items):
                if not item_id:
                    continue  # Skip items that failed to write
                try:
                    result = classify_and_decide(item_id=item_id, item_data=item_data)
                    # Write classification + eligibility + sub-category + room types back to item
                    cls = result["classification"]
                    update_fields: dict = {
                        "classification": cls,
                        "eligibility": result["decisions"],
                    }
                    # Promote subCategory and roomTypes to top-level fields for
                    # fast Firestore queries and deck filtering
                    if cls.get("subCategory"):
                        update_fields["subCategory"] = cls["subCategory"]
                    if cls.get("roomTypes"):
                        update_fields["roomTypes"] = cls["roomTypes"]
                    db.collection("items").document(item_id).update(update_fields)
                    if result["goldDoc"]:
                        db.collection("goldItems").document(item_id).set(result["goldDoc"], merge=True)
                        gold_promoted += 1
                    else:
                        has_uncertain = any(
                            d["decision"] == "UNCERTAIN" for d in result["decisions"].values()
                        )
                        if has_uncertain:
                            db.collection("reviewQueue").document(item_id).set({
                                "itemId": item_id,
                                "classification": result["classification"],
                                "decisions": result["decisions"],
                                "status": "pending",
                                "createdAt": extracted_at_iso,
                            }, merge=True)
                            review_queued += 1
                    classified += 1
                except Exception as cls_err:
                    log.warning(f"Classification failed for {item_id}: {cls_err}")
            log.success(f"Classified {classified} items: {gold_promoted} promoted to Gold, {review_queued} sent to review")
        except Exception as phase_err:
            log.warning(f"Phase 4 classification skipped: {phase_err}")
        stats["classified"] = classified
        stats["goldPromoted"] = gold_promoted
        stats["reviewQueued"] = review_queued

        # 5) Daily metrics (best-effort)
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
                "descriptionRate": stats.get("descriptionRate", 0.0),
                "dimensionsRate": stats.get("dimensionsRate", 0.0),
                "materialRate": stats.get("materialRate", 0.0),
                "browserFetchCount": stats.get("browserFetchCount", 0),
                "blockedRate": stats["blockedRate"],
                "currencyMismatchSkipped": int(stats.get("currencyMismatchSkipped") or 0),
                "currencyUnknownSkipped": int(stats.get("currencyUnknownSkipped") or 0),
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
        update_run(db, db_run_id, "succeeded", stats)
        
        log.summary(stats)
        log.header(f"CRAWL COMPLETE: {source_id} - SUCCESS")
        
        return {"runId": db_run_id, "status": "succeeded", "stats": stats}
    except Exception as e:
        duration_ms = int((time.time() - started_at) * 1000)
        stats["durationMs"] = duration_ms
        update_run(db, db_run_id, "failed", stats, error_summary=str(e))
        
        log.error(f"Crawl failed with exception: {e}")
        log.summary(stats)
        log.header(f"CRAWL COMPLETE: {source_id} - FAILED")
        
        return {"runId": db_run_id, "status": "failed", "stats": stats, "errorSummary": str(e)}
    finally:
        try:
            fetcher.close()
        except Exception:
            pass
