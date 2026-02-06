from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import Iterable
from urllib.parse import urljoin, urlparse

from app.http.fetcher import PoliteFetcher, FetchError
from app.locator.classifier import classify_url
from app.normalization import extract_domain_root, domains_equivalent


@dataclass(frozen=True)
class DiscoveredUrl:
    url: str
    source: str  # sitemap|crawl|manual
    confidence: float
    url_type_hint: str = "unknown"  # product|category|unknown


_SITEMAP_LINE_RE = re.compile(r"^sitemap:\s*(\S+)\s*$", re.IGNORECASE)


def _domain(url: str) -> str:
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return ""


def _domain_root(url: str) -> str:
    """
    Extract domain root (scheme + netloc) from a URL.
    Always use this for robots.txt and sitemap fallback URLs.
    """
    return extract_domain_root(url)


def _candidate_sitemap_urls(domain_root: str) -> list[str]:
    """Generate candidate sitemap URLs from domain root."""
    base = domain_root.rstrip("/")
    return [
        f"{base}/sitemap.xml",
        f"{base}/sitemap_index.xml",
        f"{base}/sitemap-index.xml",
    ]


def _extract_sitemaps_from_robots(robots_txt: str) -> list[str]:
    out: list[str] = []
    for line in (robots_txt or "").splitlines():
        m = _SITEMAP_LINE_RE.match(line.strip())
        if m:
            out.append(m.group(1))
    return out


def _parse_sitemap_content(content: str, url: str = "") -> tuple[list[str], list[str]]:
    """
    Parse sitemap content (XML or plain text) and return (urls, nested_sitemaps).
    
    Supports:
    - XML urlset format (standard sitemap)
    - XML sitemapindex format (sitemap of sitemaps)
    - Plain text format (.txt sitemaps with one URL per line)
    """
    urls: list[str] = []
    sitemaps: list[str] = []
    
    # First, try to detect if it's plain text (one URL per line)
    # Text sitemaps typically don't start with '<' and contain http URLs
    stripped = content.strip()
    if stripped and not stripped.startswith('<'):
        # Likely plain text sitemap - parse as URL list
        for line in stripped.splitlines():
            line = line.strip()
            if line.startswith('http://') or line.startswith('https://'):
                urls.append(line)
        if urls:
            return urls, sitemaps
    
    # Try XML parsing
    try:
        root = ET.fromstring(content.encode("utf-8", errors="ignore"))
    except Exception:
        return urls, sitemaps

    tag = (root.tag or "").lower()
    if tag.endswith("sitemapindex"):
        for sm in root.findall(".//{*}sitemap"):
            loc = sm.findtext("{*}loc")
            if loc:
                sitemaps.append(loc.strip())
        return urls, sitemaps

    if tag.endswith("urlset"):
        for u in root.findall(".//{*}url"):
            loc = u.findtext("{*}loc")
            if loc:
                urls.append(loc.strip())
        return urls, sitemaps

    # Fallback: try loc tags anywhere
    for loc in root.findall(".//{*}loc"):
        if loc.text:
            urls.append(loc.text.strip())
    return urls, sitemaps


# Keep old name for compatibility
def _parse_sitemap_xml(xml_text: str) -> tuple[list[str], list[str]]:
    """Alias for _parse_sitemap_content for backward compatibility."""
    return _parse_sitemap_content(xml_text)


def discover_from_sitemaps(
    fetcher: PoliteFetcher,
    *,
    base_url: str,
    allowlist_policy: dict | None,
    robots_respect: bool,
    rate_limit_rps: float | None,
    max_urls: int = 50_000,
    max_sitemaps: int = 200,  # Increased to allow reading more sitemaps when filtering
    category_filter: list[str] | None = None,  # Optional filter patterns
    min_matching_urls: int = 500,  # Keep reading until we have this many matching URLs
) -> list[DiscoveredUrl]:
    """
    Discover URLs via robots.txt + sitemap indexes.
    
    IMPORTANT: robots.txt is ALWAYS fetched from the domain root, regardless
    of what path is in base_url. This is the correct behavior per RFC.
    """
    print(f"         [sitemap] Starting sitemap discovery for {base_url}", flush=True)
    
    # Extract domain root for robots.txt and fallback sitemaps
    # This is critical - robots.txt must be at the domain root, not at a subpath
    domain_root = _domain_root(base_url)
    base_domain = _domain(base_url)
    
    if not domain_root:
        print(f"         [sitemap] ERROR: Could not extract domain from {base_url}", flush=True)
        return []
    
    print(f"         [sitemap] Domain root: {domain_root}", flush=True)
    sitemaps: list[str] = []

    # robots.txt first - ALWAYS from domain root
    try:
        robots_url = f"{domain_root}/robots.txt"
        print(f"         [sitemap] Fetching robots.txt: {robots_url}", flush=True)
        r = fetcher.fetch(
            robots_url,
            base_url=domain_root,  # Use domain root for robots check
            allowlist_policy=allowlist_policy,
            robots_respect=False,  # always allowed to fetch robots.txt
            rate_limit_rps=rate_limit_rps,
        )
        found_sitemaps = _extract_sitemaps_from_robots(r.text)
        if found_sitemaps:
            print(f"         [sitemap] Found {len(found_sitemaps)} sitemap(s) in robots.txt", flush=True)
            for sm in found_sitemaps[:3]:
                print(f"                   - {sm}", flush=True)
        else:
            print(f"         [sitemap] No sitemaps found in robots.txt", flush=True)
        sitemaps.extend(found_sitemaps)
    except Exception as e:
        print(f"         [sitemap] Failed to fetch robots.txt: {e}", flush=True)

    # Fallback candidates - also from domain root
    if not sitemaps:
        sitemaps = _candidate_sitemap_urls(domain_root)
        print(f"         [sitemap] Trying fallback sitemap URLs: {sitemaps}", flush=True)

    # BFS over sitemap index(s) with early stopping for zero-yield runs
    discovered_urls: list[str] = []
    matching_urls: list[str] = []  # URLs that match category filter (if any)
    seen_sitemaps: set[str] = set()
    queue: list[str] = []
    consecutive_zero_yields = 0
    # Early stopping only applies when NOT filtering.
    # When filtering, matching URLs may be scattered - we scan all sitemaps until min_matching_urls reached.
    max_consecutive_zero_yields = 5
    
    # Normalize category filter patterns
    filter_patterns = [p.lower() for p in (category_filter or [])] if category_filter else []
    has_filter = bool(filter_patterns)
    
    if has_filter:
        print(f"         [sitemap] Category filter active: {filter_patterns[:5]}{'...' if len(filter_patterns) > 5 else ''}", flush=True)
        print(f"         [sitemap] Will continue until {min_matching_urls} matching URLs found", flush=True)
    
    for sm in sitemaps:
        if sm and sm not in seen_sitemaps:
            queue.append(sm)

    # When filtering: continue until we have enough MATCHING urls (not just any urls)
    # When not filtering: use the traditional max_urls limit
    def should_continue():
        if len(seen_sitemaps) >= max_sitemaps:
            return False
        if not queue:
            return False
        if has_filter:
            # With filter: continue until we have enough matching URLs
            return len(matching_urls) < min_matching_urls and len(discovered_urls) < max_urls
        else:
            # Without filter: use traditional limit
            return len(discovered_urls) < max_urls

    while should_continue():
        # Early stop: if we've seen too many consecutive zero-yield sitemaps
        # BUT: skip early stopping when filtering - we need to scan all sitemaps to find scattered matches
        if not has_filter and consecutive_zero_yields >= max_consecutive_zero_yields:
            print(f"         [sitemap] Early stopping: {consecutive_zero_yields} consecutive zero-yield sitemaps", flush=True)
            break
            
        sm_url = queue.pop(0)
        if sm_url in seen_sitemaps:
            continue
        seen_sitemaps.add(sm_url)
        print(f"         [sitemap] Fetching: {sm_url}", flush=True)
        try:
            r = fetcher.fetch(
                sm_url,
                base_url=base_url,
                allowlist_policy=allowlist_policy,
                robots_respect=robots_respect,
                rate_limit_rps=rate_limit_rps,
            )
        except FetchError as e:
            print(f"         [sitemap] Failed to fetch {sm_url}: {e}", flush=True)
            consecutive_zero_yields += 1
            continue

        urls, nested = _parse_sitemap_content(r.text, sm_url)
        print(f"         [sitemap] Parsed: {len(urls)} URLs, {len(nested)} nested sitemaps", flush=True)
        
        urls_added = 0
        urls_matched = 0
        for u in urls:
            if len(discovered_urls) >= max_urls:
                break
            # Only keep same-domain URLs by default (treats www.x.com and x.com as equivalent).
            url_domain = _domain(u)
            if base_domain and url_domain and not domains_equivalent(url_domain, base_domain):
                continue
            discovered_urls.append(u)
            urls_added += 1
            
            # Track matching URLs separately
            if has_filter:
                u_lower = u.lower()
                if any(pattern in u_lower for pattern in filter_patterns):
                    matching_urls.append(u)
                    urls_matched += 1
        
        # Track consecutive zero-yields for early stopping
        # With filter: zero-yield means no matching URLs
        zero_yield = (urls_matched == 0 if has_filter else urls_added == 0) and not nested
        if zero_yield:
            consecutive_zero_yields += 1
        else:
            consecutive_zero_yields = 0  # Reset on any yield
        
        if urls_added > 0:
            if has_filter:
                print(f"         [sitemap] Added {urls_added} URLs, {urls_matched} matched filter (total matching: {len(matching_urls)})", flush=True)
            else:
                print(f"         [sitemap] Added {urls_added} URLs (total: {len(discovered_urls)})", flush=True)
        
        for n in nested:
            if n and n not in seen_sitemaps and len(queue) < max_sitemaps:
                queue.append(n)

    if has_filter:
        print(f"         [sitemap] Discovery complete: {len(matching_urls)} matching URLs from {len(seen_sitemaps)} sitemaps (scanned {len(discovered_urls)} total)", flush=True)
        # When filtering, only return matching URLs
        urls_to_classify = matching_urls
    else:
        print(f"         [sitemap] Discovery complete: {len(discovered_urls)} URLs from {len(seen_sitemaps)} sitemaps", flush=True)
        urls_to_classify = discovered_urls

    out: list[DiscoveredUrl] = []
    product_count = 0
    for u in urls_to_classify:
        c = classify_url(u)
        # Sitemap URLs are high coverage but weakly classified; keep a modest baseline confidence.
        conf = max(0.4, c.confidence)
        if c.url_type_hint == "product":
            product_count += 1
        out.append(DiscoveredUrl(url=u, source="sitemap", confidence=conf, url_type_hint=c.url_type_hint))
    
    print(f"         [sitemap] Classified: {product_count} product URLs, {len(out) - product_count} other", flush=True)
    return out

