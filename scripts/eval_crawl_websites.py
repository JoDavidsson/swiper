#!/usr/bin/env python3
"""
Batch-evaluate crawl extraction across many retailer websites.

Usage:
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8180 GCLOUD_PROJECT=swiper-95482 \
  PYTHONPATH=services/supply_engine \
  services/supply_engine/.venv/bin/python3 scripts/eval_crawl_websites.py \
    --url-file scripts/url_lists/user_batch_urls_2026-02-08.txt \
    --batch-size 20 \
    --pages-per-site 20
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit

from app.crawl_ingestion import _coerce_item_price, _fetch_and_extract_one, _resolve_item_currency
from app.http.fetcher import PoliteFetcher
from app.image_validation import ImageMetadata, validate_image_url
from app.locator.crawler import discover_from_category_crawl
from app.locator.sitemap import discover_from_sitemaps
from app.normalization import canonical_domain, normalize_source_url

DEFAULT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36"
)

SOFA_KEYWORDS = [
    "soffa",
    "soffor",
    "sofa",
    "sofas",
    "hornsoffa",
    "hörnsoffa",
    "divansoffa",
    "divan",
    "fatolj",
    "fåtölj",
]

# Common non-product collection/category handles often used under /products/{handle}
# by CMS/ecommerce setups that are not Shopify PDP URLs.
NON_PRODUCT_PRODUCT_HANDLES = {
    "sofas",
    "soffor",
    "armchairs",
    "dining-chairs",
    "beds",
    "beds-and-bed-frames",
    "footstools",
    "accessories",
    "chairs",
    "tables",
    "furniture",
}

URL_PATTERN = re.compile(r"https?://.*?(?=https?://|\s|$)", re.IGNORECASE | re.UNICODE)


@dataclass
class ParsedInput:
    raw_url_tokens: list[str]
    normalized_urls: list[str]
    invalid_tokens: list[str]
    unique_urls: list[str]
    duplicate_count: int


def now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def pct(numerator: int, denominator: int) -> float:
    if denominator <= 0:
        return 0.0
    return float(numerator) / float(denominator)


def pct_str(v: float) -> str:
    return f"{v * 100:.1f}%"


def chunked(seq: list[str], size: int) -> list[list[str]]:
    return [seq[i : i + size] for i in range(0, len(seq), size)]


def normalize_url(raw_url: str) -> str | None:
    candidate = raw_url.strip().strip(",);")
    if not candidate:
        return None
    if not candidate.startswith(("http://", "https://")):
        candidate = f"https://{candidate}"

    try:
        p = urlsplit(candidate)
    except Exception:
        return None

    if not p.netloc:
        return None

    host = p.hostname or ""
    if not host:
        return None
    try:
        host = host.encode("idna").decode("ascii")
    except Exception:
        host = host.lower()

    host = host.lower()
    netloc = f"{host}:{p.port}" if p.port else host
    scheme = p.scheme.lower() if p.scheme else "https"
    path = p.path or "/"
    if path != "/":
        path = path.rstrip("/")
        if not path:
            path = "/"
    query = p.query or ""
    return urlunsplit((scheme, netloc, path, query, ""))


def parse_input_urls(raw_text: str) -> ParsedInput:
    tokens = [m.group(0).strip() for m in URL_PATTERN.finditer(raw_text) if m.group(0).strip()]
    normalized: list[str] = []
    invalid: list[str] = []
    for t in tokens:
        n = normalize_url(t)
        if n:
            normalized.append(n)
        else:
            invalid.append(t)

    unique = list(dict.fromkeys(normalized))
    return ParsedInput(
        raw_url_tokens=tokens,
        normalized_urls=normalized,
        invalid_tokens=invalid,
        unique_urls=unique,
        duplicate_count=max(0, len(normalized) - len(unique)),
    )


def domain_allowlist(base_url: str) -> dict[str, Any]:
    host = (urlsplit(base_url).hostname or "").lower()
    if not host:
        return {}
    root = canonical_domain(host)
    domains = {root, f"www.{root}", host}
    return {"domains": sorted(domains)}


def dedup_key(url: str) -> str:
    try:
        p = urlsplit(url)
        return urlunsplit((p.scheme.lower(), p.netloc.lower(), p.path.rstrip("/"), "", ""))
    except Exception:
        return url


def summarize_fetch_error(message: str) -> str:
    msg = (message or "").strip()
    lower = msg.lower()
    if "blocked by robots" in lower:
        return "robots-blocked"
    if "allowlist" in lower:
        return "allowlist-blocked"
    if "429" in lower:
        return "http-429"
    if "403" in lower:
        return "http-403"
    if "404" in lower:
        return "http-404"
    if "503" in lower:
        return "http-503"
    if "timeout" in lower:
        return "timeout"
    if "tls" in lower or "ssl" in lower or "certificate" in lower:
        return "tls-certificate"
    if "name or service not known" in lower or "nodename nor servname provided" in lower:
        return "dns-failure"
    return msg[:140] if msg else "unknown-fetch-error"


def discover_candidates_for_site(
    seed_url: str,
    pages_per_site: int,
    rate_limit_rps: float,
) -> dict[str, Any]:
    """
    Discover candidate product URLs for a site using sitemap/crawl strategy.
    """
    try:
        normalized = normalize_source_url(seed_url)
    except Exception as e:
        return {
            "discovery": {
                "inputUrl": seed_url,
                "normalizedUrl": "",
                "baseUrl": "",
                "seedUrl": "",
                "seedPathPattern": "",
                "suggestedStrategy": "crawl",
                "strategyReason": f"url-normalization-failed: {e}",
                "strategyUsed": "none",
                "fallbackUsed": False,
                "sitemapCount": 0,
                "warnings": [],
                "errors": [str(e)],
                "discoveryError": str(e),
                "discoveredCount": 0,
                "productHintCount": 0,
                "highConfidenceCount": 0,
            },
            "allowlistPolicy": {},
            "candidates": [],
        }

    base_url = normalized["baseUrl"]
    normalized_seed = normalized["seedUrl"] or base_url
    seed_pattern = normalized["seedPathPattern"]

    allowlist = domain_allowlist(base_url)
    fetcher = PoliteFetcher(user_agent=DEFAULT_UA, timeout_s=12.0, max_retries=1)
    # Browser auto-refetch in worker threads can trigger Playwright greenlet
    # cross-thread errors; keep this evaluator strictly HTTP-based.
    fetcher._should_refetch_with_browser = lambda _html: False  # type: ignore[attr-defined]
    discovered: list[Any] = []
    strategy_used = "crawl"
    fallback_used = False
    discovery_error = ""

    # Keep discovery broad enough to surface product URLs on large sitemaps
    # where relevant paths may not appear in the first few hundred entries.
    max_urls = max(1200, pages_per_site * 60)
    min_matching = max(120, pages_per_site * 6)

    try:
        # Crawl-first to keep discovery bounded and avoid huge sitemap parsing stalls.
        discovered = discover_from_category_crawl(
            fetcher,
            base_url=base_url,
            seed_urls=[normalized_seed],
            allowlist_policy=allowlist,
            robots_respect=True,
            rate_limit_rps=rate_limit_rps,
            include_keywords=SOFA_KEYWORDS,
            max_depth=2,
            max_pages=12,
            max_out_urls=max_urls,
        )

        product_hints = sum(1 for d in discovered if getattr(d, "url_type_hint", "") == "product")
        high_conf_hints = sum(1 for d in discovered if float(getattr(d, "confidence", 0.0) or 0.0) >= 0.7)
        if product_hints < pages_per_site and high_conf_hints < pages_per_site:
            fallback_used = True
            strategy_used = "crawl+sitemap-fallback"
            sitemap_discovered = discover_from_sitemaps(
                fetcher,
                base_url=base_url,
                allowlist_policy=allowlist,
                robots_respect=True,
                rate_limit_rps=rate_limit_rps,
                max_urls=max_urls,
                max_sitemaps=18,
                category_filter=SOFA_KEYWORDS,
                min_matching_urls=min_matching,
            )
            if sitemap_discovered:
                by_key = {dedup_key(d.url): d for d in discovered if getattr(d, "url", "")}
                for d in sitemap_discovered:
                    k = dedup_key(d.url)
                    if k not in by_key:
                        by_key[k] = d
                discovered = list(by_key.values())

        # If keyword-filtered discovery mostly found non-product pages,
        # run a second sitemap pass without category filters and re-rank.
        # This recovers sites where product URLs do not include sofa keywords.
        product_hints = sum(1 for d in discovered if getattr(d, "url_type_hint", "") == "product")
        high_conf_hints = sum(1 for d in discovered if float(getattr(d, "confidence", 0.0) or 0.0) >= 0.7)
        if product_hints == 0 and high_conf_hints == 0:
            fallback_used = True
            strategy_used = f"{strategy_used}+sitemap-unfiltered-fallback"
            unfiltered_max_urls = max(max_urls, 2000)
            sitemap_unfiltered = discover_from_sitemaps(
                fetcher,
                base_url=base_url,
                allowlist_policy=allowlist,
                robots_respect=True,
                rate_limit_rps=rate_limit_rps,
                max_urls=unfiltered_max_urls,
                max_sitemaps=12,
                category_filter=None,
                min_matching_urls=min_matching,
            )
            if sitemap_unfiltered:
                by_key = {dedup_key(d.url): d for d in discovered if getattr(d, "url", "")}
                for d in sitemap_unfiltered:
                    k = dedup_key(d.url)
                    if k not in by_key:
                        by_key[k] = d
                discovered = list(by_key.values())
    except Exception as e:
        discovery_error = str(e)
    finally:
        fetcher.close()

    product_urls = [d.url for d in discovered if getattr(d, "url_type_hint", "") == "product"]
    high_conf_urls = [d.url for d in discovered if float(getattr(d, "confidence", 0.0) or 0.0) >= 0.7]

    def _candidate_rank(d: Any) -> float:
        u = str(getattr(d, "url", "") or "")
        conf = float(getattr(d, "confidence", 0.0) or 0.0)
        hint = str(getattr(d, "url_type_hint", "") or "")
        src = str(getattr(d, "source", "") or "")
        p = urlsplit(u)
        path_l = (p.path or "").lower()
        query_l = (p.query or "").lower()
        segs = [s for s in path_l.split("/") if s]

        score = conf
        if hint == "product":
            score += 0.35
        if src == "crawl":
            score += 0.05
        score += min(len(segs), 6) * 0.03

        # Prefer topic-relevant URLs when possible.
        if any(k in u.lower() for k in SOFA_KEYWORDS):
            score += 0.25

        if "?" in u and hint != "product":
            score -= 0.25
        if any(k in query_l for k in ("page=", "sort=", "filter", "q=", "search=", "brand=")):
            score -= 0.2
        if any(tok in path_l for tok in ("/kampanj", "/campaign", "/kundservice", "/butiker", "/inspiration")):
            score -= 0.35
        if path_l.endswith("/index.html"):
            score -= 0.25
        if "/sida.html" in path_l:
            score -= 0.7

        # /products/{handle} can be category pages on non-Shopify setups.
        if len(segs) == 2 and segs[0] == "products" and segs[1] in NON_PRODUCT_PRODUCT_HANDLES:
            score -= 0.5

        # Listing/article-like paths are lower priority unless explicitly product-marked.
        looks_listing = any(
            tok in path_l
            for tok in ("/article/", "/articles/", "/inspiration", "/blog", "/guide", "/info/")
        )
        if looks_listing and hint != "product":
            score -= 0.3

        if path_l.endswith(".html") and not path_l.endswith("/index.html") and len(segs) >= 4:
            score += 0.3
        return score

    ranked = [d.url for d in sorted(discovered, key=_candidate_rank, reverse=True)] if discovered else []
    deduped: list[str] = []
    seen: set[str] = set()
    for u in ranked:
        k = dedup_key(u)
        if not u or k in seen:
            continue
        seen.add(k)
        deduped.append(u)

    if not deduped and normalized_seed:
        deduped = [normalized_seed]

    return {
        "discovery": {
            "inputUrl": seed_url,
            "normalizedUrl": normalized["normalized"],
            "baseUrl": base_url,
            "seedUrl": normalized_seed,
            "seedPathPattern": seed_pattern,
            "suggestedStrategy": "crawl-first-bounded",
            "strategyReason": "bounded category crawl with sitemap fallback when candidates are insufficient",
            "strategyUsed": strategy_used,
            "fallbackUsed": fallback_used,
            "sitemapCount": 0,
            "warnings": [],
            "errors": [],
            "discoveryError": discovery_error,
            "discoveredCount": len(discovered),
            "productHintCount": len(product_urls),
            "highConfidenceCount": len(high_conf_urls),
        },
        "allowlistPolicy": allowlist,
        "candidates": deduped[:pages_per_site],
    }


async def validate_images_async(urls: list[str], timeout_s: float, max_concurrent: int) -> dict[str, ImageMetadata]:
    sem = asyncio.Semaphore(max_concurrent)

    async def _one(u: str) -> ImageMetadata:
        async with sem:
            return await validate_image_url(u, timeout=timeout_s)

    results = await asyncio.gather(*[_one(u) for u in urls], return_exceptions=False)
    return {md.url: md for md in results}


def evaluate_site(
    index: int,
    total: int,
    site_url: str,
    pages_per_site: int,
    rate_limit_rps: float,
    extract_workers: int,
    image_timeout_s: float,
    max_images_per_product: int,
) -> dict[str, Any]:
    started = time.time()
    print(f"\n[site {index}/{total}] {site_url}", flush=True)

    result: dict[str, Any] = {
        "siteUrl": site_url,
        "status": "failed",
        "fatalError": None,
        "discovery": {},
        "pages": {},
        "images": {},
        "methods": {"extractor": {}, "fetch": {}},
        "non100Reasons": [],
        "durationSec": 0.0,
    }

    try:
        discovered = discover_candidates_for_site(site_url, pages_per_site, rate_limit_rps)
        discovery_meta = discovered["discovery"]
        candidates: list[str] = discovered["candidates"]
        allowlist_policy = discovered["allowlistPolicy"]
        result["discovery"] = discovery_meta

        if not candidates:
            result["status"] = "failed"
            result["non100Reasons"] = ["no-candidate-urls-discovered"]
            result["pages"] = {
                "tested": 0,
                "accepted": 0,
                "completionRate": 0.0,
                "failures": {
                    "fetchBlocked": 0,
                    "fetchError": 0,
                    "parse": 0,
                    "invalidPrice": 0,
                    "currencyMismatch": 0,
                    "currencyUnknown": 0,
                },
                "fetchErrorBreakdown": {},
                "parseErrorSamples": [],
            }
            result["images"] = {
                "productsAccepted": 0,
                "productsWithImages": 0,
                "productsWithWorkingPrimaryImage": 0,
                "primaryImageCoverageRate": 0.0,
                "urlsChecked": 0,
                "urlsValid": 0,
                "urlsInvalid": 0,
                "urlValidRate": 0.0,
                "issueBreakdown": {},
                "invalidSamples": [],
            }
            return result

        fetcher = PoliteFetcher(
            user_agent=DEFAULT_UA,
            timeout_s=14.0,
            max_retries=1,
            browser_fallback=False,
        )
        fetcher._should_refetch_with_browser = lambda _html: False  # type: ignore[attr-defined]

        extracted_at_iso = now_utc_iso()
        fail_fetch_blocked = 0
        fail_fetch_error = 0
        fail_parse = 0
        fail_invalid_price = 0
        fail_currency = 0
        fail_currency_unknown = 0
        accepted = 0
        extractor_methods: Counter[str] = Counter()
        fetch_methods: Counter[str] = Counter()
        fetch_error_breakdown: Counter[str] = Counter()
        parse_error_breakdown: Counter[str] = Counter()
        parse_error_samples: list[str] = []
        product_records: list[dict[str, Any]] = []

        try:
            with ThreadPoolExecutor(max_workers=max(1, extract_workers)) as pool:
                futures = {
                    pool.submit(
                        _fetch_and_extract_one,
                        url,
                        fetcher,
                        discovery_meta.get("baseUrl") or site_url,
                        allowlist_policy,
                        True,
                        rate_limit_rps,
                        f"eval-{index}",
                        extracted_at_iso,
                        None,
                        None,
                    ): url
                    for url in candidates
                }

                for future in as_completed(futures):
                    er = future.result()
                    if er.error_type == "fetch_blocked":
                        fail_fetch_blocked += 1
                        fetch_error_breakdown[summarize_fetch_error(er.error_msg or "")] += 1
                        continue
                    if er.error_type == "fetch_error":
                        fail_fetch_error += 1
                        fetch_error_breakdown[summarize_fetch_error(er.error_msg or "")] += 1
                        continue
                    if er.error_type == "parse":
                        fail_parse += 1
                        parse_error_breakdown[er.error_msg or "no-product-extracted"] += 1
                        if len(parse_error_samples) < 8:
                            parse_error_samples.append(er.error_msg or "no-product-extracted")
                        continue
                    if not er.product:
                        fail_parse += 1
                        parse_error_breakdown["unknown-parse-failure"] += 1
                        if len(parse_error_samples) < 8:
                            parse_error_samples.append("unknown-parse-failure")
                        continue

                    p = er.product
                    price_amount = _coerce_item_price(p.price_amount, p.price_original, p.price_raw)
                    if price_amount is None or price_amount <= 0:
                        fail_invalid_price += 1
                        continue
                    resolved_currency, currency_reason = _resolve_item_currency(p)
                    if resolved_currency is None:
                        if currency_reason == "mismatch":
                            fail_currency += 1
                        else:
                            fail_currency_unknown += 1
                        continue

                    accepted += 1
                    extractor_methods[p.method] += 1
                    fetch_methods[er.fetch_method] += 1

                    imgs = [u for u in (p.images or []) if isinstance(u, str) and u]
                    if max_images_per_product > 0 and len(imgs) > max_images_per_product:
                        imgs = imgs[:max_images_per_product]
                    product_records.append(
                        {
                            "url": er.url,
                            "title": (p.title or "").strip()[:180],
                            "images": imgs,
                        }
                    )
        finally:
            fetcher.close()

        tested = len(candidates)
        page_completion = pct(accepted, tested)

        unique_image_urls: list[str] = []
        image_seen: set[str] = set()
        for rec in product_records:
            for img_url in rec["images"]:
                if img_url in image_seen:
                    continue
                image_seen.add(img_url)
                unique_image_urls.append(img_url)

        image_issue_counts: Counter[str] = Counter()
        invalid_image_samples: list[dict[str, Any]] = []
        image_meta_by_url: dict[str, ImageMetadata] = {}
        if unique_image_urls:
            image_meta_by_url = asyncio.run(
                validate_images_async(
                    unique_image_urls,
                    timeout_s=image_timeout_s,
                    max_concurrent=10,
                )
            )
            for img_url in unique_image_urls:
                md = image_meta_by_url.get(img_url)
                if not md:
                    image_issue_counts["missing-metadata"] += 1
                    continue
                if not md.valid:
                    issues = md.issues or ["invalid"]
                    for issue in issues:
                        image_issue_counts[issue] += 1
                    if len(invalid_image_samples) < 12:
                        invalid_image_samples.append({"url": img_url, "issues": issues})

        products_with_images = 0
        products_with_working_primary = 0
        for rec in product_records:
            imgs = rec["images"]
            if imgs:
                products_with_images += 1
                primary = imgs[0]
                md = image_meta_by_url.get(primary)
                if md and md.valid:
                    products_with_working_primary += 1

        urls_checked = len(unique_image_urls)
        urls_valid = sum(1 for md in image_meta_by_url.values() if md.valid)
        urls_invalid = max(0, urls_checked - urls_valid)
        primary_coverage = pct(products_with_working_primary, accepted)
        url_valid_rate = pct(urls_valid, urls_checked)

        reasons: list[str] = []
        if tested == 0:
            reasons.append("no-candidates-tested")
        if accepted < tested:
            if fail_fetch_blocked:
                reasons.append(f"fetch-blocked:{fail_fetch_blocked}")
            if fail_fetch_error:
                reasons.append(f"fetch-error:{fail_fetch_error}")
            if fail_parse:
                reasons.append(f"parse-fail:{fail_parse}")
            if fail_invalid_price:
                reasons.append(f"invalid-price:{fail_invalid_price}")
            if fail_currency:
                reasons.append(f"currency-mismatch:{fail_currency}")
            if fail_currency_unknown:
                reasons.append(f"currency-unknown:{fail_currency_unknown}")
        if accepted > 0 and products_with_images < accepted:
            reasons.append(f"missing-images:{accepted - products_with_images}")
        if urls_invalid > 0:
            reasons.append(f"broken-images:{urls_invalid}")

        site_pass = accepted > 0
        site_full = (
            tested > 0
            and accepted == tested
            and products_with_images == accepted
            and urls_invalid == 0
        )

        result["status"] = "passed" if site_pass else "failed"
        result["fullCompletion"] = site_full
        result["pages"] = {
            "tested": tested,
            "accepted": accepted,
            "completionRate": page_completion,
                "failures": {
                    "fetchBlocked": fail_fetch_blocked,
                    "fetchError": fail_fetch_error,
                    "parse": fail_parse,
                    "invalidPrice": fail_invalid_price,
                    "currencyMismatch": fail_currency,
                    "currencyUnknown": fail_currency_unknown,
                },
                "fetchErrorBreakdown": dict(fetch_error_breakdown),
                "parseErrorBreakdown": dict(parse_error_breakdown),
                "parseErrorSamples": parse_error_samples,
            }
        result["images"] = {
            "productsAccepted": accepted,
            "productsWithImages": products_with_images,
            "productsWithWorkingPrimaryImage": products_with_working_primary,
            "primaryImageCoverageRate": primary_coverage,
            "urlsChecked": urls_checked,
            "urlsValid": urls_valid,
            "urlsInvalid": urls_invalid,
            "urlValidRate": url_valid_rate,
            "issueBreakdown": dict(image_issue_counts),
            "invalidSamples": invalid_image_samples,
        }
        result["methods"] = {
            "extractor": dict(extractor_methods),
            "fetch": dict(fetch_methods),
        }
        result["non100Reasons"] = reasons

    except Exception as e:
        result["status"] = "failed"
        result["fatalError"] = str(e)
        if not result["non100Reasons"]:
            result["non100Reasons"] = [f"fatal:{str(e)[:200]}"]
    finally:
        result["durationSec"] = round(time.time() - started, 2)

    return result


def build_markdown_report(payload: dict[str, Any]) -> str:
    summary = payload["summary"]
    inp = payload["input"]
    lines: list[str] = []
    lines.append("# Crawl Batch Evaluation")
    lines.append("")
    lines.append(f"- Generated: {payload['generatedAt']}")
    lines.append(f"- Batch size: {payload['config']['batchSize']} sites")
    lines.append(f"- Pages tested per site: {payload['config']['pagesPerSite']}")
    lines.append("")
    lines.append("## Input normalization")
    lines.append("")
    lines.append(f"- Raw URL tokens parsed: {inp['rawUrlTokenCount']}")
    lines.append(f"- Valid normalized entries: {inp['validEntryCount']}")
    lines.append(f"- Invalid tokens: {inp['invalidTokenCount']}")
    lines.append(f"- Duplicate entries: {inp['duplicateCount']}")
    lines.append(f"- Unique URLs tested: {inp['uniqueUrlCount']}")
    if inp["invalidTokenCount"] > 0:
        lines.append(f"- Invalid token samples: {', '.join(inp['invalidTokenSamples'])}")
    lines.append("")
    lines.append("## Discovery baseline")
    lines.append("")
    lines.append(
        f"- Discovered HTTPS URLs: {summary['discoveredUrls']}"
    )
    lines.append(
        f"- Product-hint URLs: {summary['productHintUrls']} ({pct_str(summary['productHintShareOfDiscovered'])} of discovered)"
    )
    lines.append(
        f"- High-confidence URLs: {summary['highConfidenceUrls']} ({pct_str(summary['highConfidenceShareOfDiscovered'])} of discovered)"
    )
    lines.append(
        f"- Accepted/discovered ratio: {summary['acceptedPages']}/{summary['discoveredUrls']} ({pct_str(summary['acceptedShareOfDiscovered'])})"
    )
    lines.append(
        f"- Accepted/product-hint ratio: {summary['acceptedPages']}/{summary['productHintUrls']} ({pct_str(summary['acceptedShareOfProductHints'])})"
    )
    lines.append(
        f"- Sites with discovered URLs but zero product hints: {summary['sitesDiscoveredNonzeroProductHintZero']}"
    )
    lines.append(
        f"- Sites with product hints but zero accepted pages: {summary['sitesProductHintNonzeroAcceptedZero']}"
    )
    lines.append(
        f"- Sites with product hints and accepted pages: {summary['sitesProductHintNonzeroAcceptedNonzero']}"
    )
    lines.append(
        f"- Sites with zero discovered URLs: {summary['sitesDiscoveredZero']}"
    )
    lines.append("")
    lines.append("## Completion summary")
    lines.append("")
    lines.append(f"- Unique-site pass rate: {summary['uniqueSitePassed']}/{summary['uniqueSiteTotal']} ({pct_str(summary['uniqueSitePassRate'])})")
    lines.append(f"- Unique-site full completion rate: {summary['uniqueSiteFullCompletion']}/{summary['uniqueSiteTotal']} ({pct_str(summary['uniqueSiteFullCompletionRate'])})")
    lines.append(f"- Entry pass rate (including duplicates): {summary['entryPassed']}/{summary['entryTotal']} ({pct_str(summary['entryPassRate'])})")
    lines.append(f"- Page completion: {summary['acceptedPages']}/{summary['testedPages']} ({pct_str(summary['pageCompletionRate'])})")
    lines.append(f"- Image URL validity: {summary['validImageUrls']}/{summary['checkedImageUrls']} ({pct_str(summary['imageUrlValidRate'])})")
    lines.append(f"- Primary-image coverage: {summary['productsWithWorkingPrimaryImage']}/{summary['acceptedProducts']} ({pct_str(summary['primaryImageCoverageRate'])})")
    lines.append("")
    lines.append("## Why not 100%")
    lines.append("")
    if summary["topFailureReasons"]:
        for reason, count in summary["topFailureReasons"]:
            lines.append(f"- {reason}: {count} site(s)")
    else:
        lines.append("- No shortfalls detected.")
    lines.append("")
    lines.append("## Error breakdown")
    lines.append("")
    lines.append(
        f"- Sites with invalid image URLs: {summary['sitesWithInvalidImageUrls']}"
    )
    lines.append(
        f"- Sites with primary-image gaps: {summary['sitesWithPrimaryImageGap']}"
    )
    if summary["fetchErrorBreakdown"]:
        lines.append("- Fetch error breakdown:")
        for reason, count in summary["fetchErrorBreakdown"]:
            lines.append(f"  - {reason}: {count}")
    else:
        lines.append("- Fetch error breakdown: none")
    if summary["parseErrorBreakdown"]:
        lines.append("- Parse error breakdown:")
        for reason, count in summary["parseErrorBreakdown"]:
            lines.append(f"  - {reason}: {count}")
    else:
        lines.append("- Parse error breakdown: none")
    if summary["imageIssueBreakdown"]:
        lines.append("- Image issue breakdown:")
        for reason, count in summary["imageIssueBreakdown"]:
            lines.append(f"  - {reason}: {count}")
    else:
        lines.append("- Image issue breakdown: none")
    lines.append("")
    lines.append("## Batch overview")
    lines.append("")
    lines.append("| Batch | Sites | Passed | Full completion | Duration (s) |")
    lines.append("|---|---:|---:|---:|---:|")
    for b in payload["batches"]:
        lines.append(
            f"| {b['batchIndex']} | {b['siteCount']} | {b['passed']} | {b['fullCompletion']} | {b['durationSec']:.1f} |"
        )
    lines.append("")
    lines.append("## Per-site detail")
    lines.append("")
    lines.append("| Site | Status | Discovery (all/product) | Pages accepted/tested | Page completion | Images valid/checked | Top reasons |")
    lines.append("|---|---|---:|---:|---:|---:|---|")
    for s in payload["sites"]:
        pages = s.get("pages", {})
        images = s.get("images", {})
        discovery = s.get("discovery", {})
        accepted = int(pages.get("accepted", 0))
        tested = int(pages.get("tested", 0))
        valid = int(images.get("urlsValid", 0))
        checked = int(images.get("urlsChecked", 0))
        discovered_total = int(discovery.get("discoveredCount", 0) or 0)
        product_hints = int(discovery.get("productHintCount", 0) or 0)
        reasons = ", ".join(s.get("non100Reasons", [])[:3]) or "none"
        lines.append(
            f"| {s['siteUrl']} | {s['status']} | {discovered_total}/{product_hints} | "
            f"{accepted}/{tested} | {pct_str(float(pages.get('completionRate', 0.0)))} | {valid}/{checked} | {reasons} |"
        )
    lines.append("")
    return "\n".join(lines)


def run(args: argparse.Namespace) -> dict[str, Any]:
    raw_text = Path(args.url_file).read_text(encoding="utf-8")
    parsed = parse_input_urls(raw_text)
    if args.max_sites and args.max_sites > 0:
        unique_urls = parsed.unique_urls[: args.max_sites]
    else:
        unique_urls = parsed.unique_urls

    batches = chunked(unique_urls, args.batch_size)
    print(f"Parsed {len(parsed.raw_url_tokens)} URL tokens, testing {len(unique_urls)} unique URLs.", flush=True)
    print(f"Running in {len(batches)} batches of up to {args.batch_size}.", flush=True)

    site_results: list[dict[str, Any]] = []
    batch_summaries: list[dict[str, Any]] = []

    site_index = 0
    for batch_index, batch_urls in enumerate(batches, start=1):
        batch_start = time.time()
        print(f"\n=== Batch {batch_index}/{len(batches)} ({len(batch_urls)} sites) ===", flush=True)
        batch_results: list[dict[str, Any]] = []
        for u in batch_urls:
            site_index += 1
            sr = evaluate_site(
                index=site_index,
                total=len(unique_urls),
                site_url=u,
                pages_per_site=args.pages_per_site,
                rate_limit_rps=args.rate_limit_rps,
                extract_workers=args.extract_workers,
                image_timeout_s=args.image_timeout_s,
                max_images_per_product=args.max_images_per_product,
            )
            batch_results.append(sr)
            site_results.append(sr)
            pages = sr.get("pages", {})
            images = sr.get("images", {})
            print(
                "  -> status={status} accepted={accepted}/{tested} image_valid={ivalid}/{ichecked}".format(
                    status=sr.get("status", "unknown"),
                    accepted=pages.get("accepted", 0),
                    tested=pages.get("tested", 0),
                    ivalid=images.get("urlsValid", 0),
                    ichecked=images.get("urlsChecked", 0),
                ),
                flush=True,
            )

        duration = time.time() - batch_start
        batch_passed = sum(1 for r in batch_results if r.get("status") == "passed")
        batch_full = sum(1 for r in batch_results if r.get("fullCompletion"))
        batch_summaries.append(
            {
                "batchIndex": batch_index,
                "siteCount": len(batch_results),
                "passed": batch_passed,
                "fullCompletion": batch_full,
                "durationSec": duration,
                "sites": [r["siteUrl"] for r in batch_results],
            }
        )
        print(
            f"=== Batch {batch_index} done: passed {batch_passed}/{len(batch_results)}, full {batch_full}/{len(batch_results)}, duration {duration:.1f}s ===",
            flush=True,
        )

    # Aggregate metrics.
    pass_map = {r["siteUrl"]: r.get("status") == "passed" for r in site_results}
    full_map = {r["siteUrl"]: bool(r.get("fullCompletion")) for r in site_results}

    entry_passed = sum(1 for u in parsed.normalized_urls if pass_map.get(u, False))
    entry_total = len(parsed.normalized_urls)

    unique_site_total = len(site_results)
    unique_site_passed = sum(1 for r in site_results if r.get("status") == "passed")
    unique_site_full = sum(1 for r in site_results if r.get("fullCompletion"))

    tested_pages = sum(int(r.get("pages", {}).get("tested", 0)) for r in site_results)
    accepted_pages = sum(int(r.get("pages", {}).get("accepted", 0)) for r in site_results)
    checked_images = sum(int(r.get("images", {}).get("urlsChecked", 0)) for r in site_results)
    valid_images = sum(int(r.get("images", {}).get("urlsValid", 0)) for r in site_results)
    accepted_products = sum(int(r.get("images", {}).get("productsAccepted", 0)) for r in site_results)
    discovered_urls = sum(int(r.get("discovery", {}).get("discoveredCount", 0) or 0) for r in site_results)
    product_hint_urls = sum(int(r.get("discovery", {}).get("productHintCount", 0) or 0) for r in site_results)
    high_conf_urls = sum(int(r.get("discovery", {}).get("highConfidenceCount", 0) or 0) for r in site_results)
    products_with_working_primary = sum(
        int(r.get("images", {}).get("productsWithWorkingPrimaryImage", 0)) for r in site_results
    )
    sites_discovered_zero = sum(
        1 for r in site_results if int(r.get("discovery", {}).get("discoveredCount", 0) or 0) == 0
    )
    sites_discovered_nonzero_producthint_zero = sum(
        1
        for r in site_results
        if int(r.get("discovery", {}).get("discoveredCount", 0) or 0) > 0
        and int(r.get("discovery", {}).get("productHintCount", 0) or 0) == 0
    )
    sites_producthint_nonzero_accepted_zero = sum(
        1
        for r in site_results
        if int(r.get("discovery", {}).get("productHintCount", 0) or 0) > 0
        and int(r.get("pages", {}).get("accepted", 0) or 0) == 0
    )
    sites_producthint_nonzero_accepted_nonzero = sum(
        1
        for r in site_results
        if int(r.get("discovery", {}).get("productHintCount", 0) or 0) > 0
        and int(r.get("pages", {}).get("accepted", 0) or 0) > 0
    )

    reason_counts: Counter[str] = Counter()
    fetch_error_reason_counts: Counter[str] = Counter()
    parse_error_reason_counts: Counter[str] = Counter()
    image_issue_counts: Counter[str] = Counter()
    sites_with_invalid_images = 0
    sites_with_primary_image_gap = 0
    for r in site_results:
        for reason in r.get("non100Reasons", []):
            key = reason.split(":")[0] if ":" in reason else reason
            reason_counts[key] += 1
        for k, v in (r.get("pages", {}).get("fetchErrorBreakdown", {}) or {}).items():
            fetch_error_reason_counts[str(k)] += int(v or 0)
        for k, v in (r.get("pages", {}).get("parseErrorBreakdown", {}) or {}).items():
            parse_error_reason_counts[str(k)] += int(v or 0)
        for k, v in (r.get("images", {}).get("issueBreakdown", {}) or {}).items():
            image_issue_counts[str(k)] += int(v or 0)
        if int(r.get("images", {}).get("urlsInvalid", 0) or 0) > 0:
            sites_with_invalid_images += 1
        if int(r.get("images", {}).get("productsAccepted", 0) or 0) > int(
            r.get("images", {}).get("productsWithWorkingPrimaryImage", 0) or 0
        ):
            sites_with_primary_image_gap += 1

    payload: dict[str, Any] = {
        "generatedAt": now_utc_iso(),
        "config": {
            "batchSize": args.batch_size,
            "pagesPerSite": args.pages_per_site,
            "rateLimitRps": args.rate_limit_rps,
            "extractWorkers": args.extract_workers,
            "imageTimeoutSeconds": args.image_timeout_s,
            "maxImagesPerProduct": args.max_images_per_product,
            "urlFile": str(args.url_file),
        },
        "input": {
            "rawUrlTokenCount": len(parsed.raw_url_tokens),
            "validEntryCount": len(parsed.normalized_urls),
            "invalidTokenCount": len(parsed.invalid_tokens),
            "invalidTokenSamples": parsed.invalid_tokens[:10],
            "duplicateCount": parsed.duplicate_count,
            "uniqueUrlCount": len(unique_urls),
        },
        "summary": {
            "entryTotal": entry_total,
            "entryPassed": entry_passed,
            "entryPassRate": pct(entry_passed, entry_total),
            "uniqueSiteTotal": unique_site_total,
            "uniqueSitePassed": unique_site_passed,
            "uniqueSitePassRate": pct(unique_site_passed, unique_site_total),
            "uniqueSiteFullCompletion": unique_site_full,
            "uniqueSiteFullCompletionRate": pct(unique_site_full, unique_site_total),
            "testedPages": tested_pages,
            "acceptedPages": accepted_pages,
            "pageCompletionRate": pct(accepted_pages, tested_pages),
            "discoveredUrls": discovered_urls,
            "productHintUrls": product_hint_urls,
            "highConfidenceUrls": high_conf_urls,
            "productHintShareOfDiscovered": pct(product_hint_urls, discovered_urls),
            "highConfidenceShareOfDiscovered": pct(high_conf_urls, discovered_urls),
            "acceptedShareOfDiscovered": pct(accepted_pages, discovered_urls),
            "acceptedShareOfProductHints": pct(accepted_pages, product_hint_urls),
            "sitesDiscoveredZero": sites_discovered_zero,
            "sitesDiscoveredNonzeroProductHintZero": sites_discovered_nonzero_producthint_zero,
            "sitesProductHintNonzeroAcceptedZero": sites_producthint_nonzero_accepted_zero,
            "sitesProductHintNonzeroAcceptedNonzero": sites_producthint_nonzero_accepted_nonzero,
            "checkedImageUrls": checked_images,
            "validImageUrls": valid_images,
            "imageUrlValidRate": pct(valid_images, checked_images),
            "acceptedProducts": accepted_products,
            "productsWithWorkingPrimaryImage": products_with_working_primary,
            "primaryImageCoverageRate": pct(products_with_working_primary, accepted_products),
            "sitesWithInvalidImageUrls": sites_with_invalid_images,
            "sitesWithPrimaryImageGap": sites_with_primary_image_gap,
            "fetchErrorBreakdown": fetch_error_reason_counts.most_common(12),
            "parseErrorBreakdown": parse_error_reason_counts.most_common(12),
            "imageIssueBreakdown": image_issue_counts.most_common(12),
            "topFailureReasons": reason_counts.most_common(12),
        },
        "batches": batch_summaries,
        "sites": site_results,
    }

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    json_path = out_dir / f"crawl_eval_{ts}.json"
    md_path = out_dir / f"crawl_eval_{ts}.md"

    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    md_path.write_text(build_markdown_report(payload), encoding="utf-8")

    payload["artifacts"] = {"json": str(json_path), "markdown": str(md_path)}
    print(f"\nWrote JSON: {json_path}", flush=True)
    print(f"Wrote Markdown: {md_path}", flush=True)
    return payload


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Batch crawl evaluator")
    p.add_argument("--url-file", required=True, help="Path to URL list text file")
    p.add_argument("--batch-size", type=int, default=20, help="Sites per batch")
    p.add_argument("--pages-per-site", type=int, default=20, help="Candidate pages to test per site")
    p.add_argument("--rate-limit-rps", type=float, default=1.0, help="Per-site request rate limit")
    p.add_argument("--extract-workers", type=int, default=5, help="Concurrent page extraction workers")
    p.add_argument("--image-timeout-s", type=float, default=8.0, help="Image validation timeout per URL")
    p.add_argument(
        "--max-images-per-product",
        type=int,
        default=5,
        help="Max image URLs to validate per extracted product",
    )
    p.add_argument("--output-dir", default="docs/reports", help="Output directory for reports")
    p.add_argument("--max-sites", type=int, default=0, help="Optional cap for debugging")
    return p


if __name__ == "__main__":
    parser = build_arg_parser()
    args = parser.parse_args()
    run(args)
