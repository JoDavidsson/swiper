"""
Auto-discovery module for crawler configuration.

This module handles automatic discovery of crawl configuration from a URL:
1. Normalizes user input URL
2. Fetches robots.txt from domain root
3. Discovers sitemaps and counts relevant URLs
4. Suggests a crawl strategy (sitemap vs crawl)
5. Returns a preview before committing the source

The goal is to reduce cognitive overhead for users by deriving most
configuration automatically from a single URL input.
"""
from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, asdict
from typing import Literal
from urllib.parse import urlparse

from app.normalization import normalize_source_url, extract_domain_root
from app.http.fetcher import PoliteFetcher, FetchError
from app.locator.classifier import classify_url


@dataclass
class DiscoveryResult:
    """Result of auto-discovery for a URL."""
    
    # User input and normalized values
    input_url: str
    normalized_url: str
    domain: str
    base_url: str
    seed_url: str
    seed_path: str
    seed_path_pattern: str
    
    # Discovery results
    robots_found: bool
    sitemaps_found: list[str]
    sitemap_count: int
    
    # URL counts (sampled, not exhaustive)
    total_urls_sampled: int
    product_urls_estimated: int
    category_urls_estimated: int
    matching_path_urls: int
    
    # Strategy recommendation
    suggested_strategy: Literal["sitemap", "crawl"]
    strategy_reason: str
    
    # Errors/warnings
    errors: list[str]
    warnings: list[str]
    
    def to_dict(self) -> dict:
        return asdict(self)


_SITEMAP_LINE_RE = re.compile(r"^sitemap:\s*(\S+)\s*$", re.IGNORECASE)


def _extract_sitemaps_from_robots(robots_txt: str) -> list[str]:
    """Extract Sitemap: directives from robots.txt content."""
    sitemaps: list[str] = []
    for line in (robots_txt or "").splitlines():
        m = _SITEMAP_LINE_RE.match(line.strip())
        if m:
            sitemaps.append(m.group(1))
    return sitemaps


def _parse_sitemap_xml(xml_text: str) -> tuple[list[str], list[str]]:
    """
    Parse sitemap XML and return (urls, nested_sitemaps).
    Supports both urlset and sitemapindex formats.
    """
    urls: list[str] = []
    sitemaps: list[str] = []
    try:
        root = ET.fromstring(xml_text.encode("utf-8", errors="ignore"))
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


def _url_matches_pattern(url: str, pattern: str) -> bool:
    """Check if URL path contains the pattern."""
    if not pattern:
        return True
    try:
        path = urlparse(url).path.lower()
        return pattern.lower() in path
    except Exception:
        return False


def _count_sitemap_urls(
    fetcher: PoliteFetcher,
    sitemap_urls: list[str],
    path_pattern: str,
    domain: str,
    rate_limit_rps: float | None = 1.0,
    max_sitemaps_to_sample: int = 10,
    max_urls_per_sitemap: int = 500,
) -> tuple[int, int, int, int]:
    """
    Sample sitemaps to estimate URL counts without fetching everything.
    
    Returns: (total_sampled, product_estimated, category_estimated, matching_pattern)
    """
    total_urls = 0
    product_urls = 0
    category_urls = 0
    matching_urls = 0
    
    sitemaps_processed = 0
    queue = list(sitemap_urls)
    seen = set()
    
    while queue and sitemaps_processed < max_sitemaps_to_sample:
        sm_url = queue.pop(0)
        if sm_url in seen:
            continue
        seen.add(sm_url)
        sitemaps_processed += 1
        
        try:
            r = fetcher.fetch(
                sm_url,
                base_url=f"https://{domain}",
                robots_respect=False,
                rate_limit_rps=rate_limit_rps,
            )
            urls, nested = _parse_sitemap_xml(r.text)
            
            # Process URLs (sample if too many)
            sample_urls = urls[:max_urls_per_sitemap]
            for url in sample_urls:
                # Skip if different domain
                try:
                    url_domain = urlparse(url).netloc.lower()
                    if url_domain and url_domain != domain:
                        continue
                except Exception:
                    continue
                
                total_urls += 1
                
                # Classify URL
                classification = classify_url(url)
                if classification.url_type_hint == "product":
                    product_urls += 1
                elif classification.url_type_hint == "category":
                    category_urls += 1
                
                # Check pattern match
                if _url_matches_pattern(url, path_pattern):
                    matching_urls += 1
            
            # Add nested sitemaps to queue
            for nested_sm in nested:
                if nested_sm not in seen:
                    queue.append(nested_sm)
                    
        except FetchError:
            continue
        except Exception:
            continue
    
    return total_urls, product_urls, category_urls, matching_urls


def discover_from_url(
    user_input: str,
    fetcher: PoliteFetcher | None = None,
    rate_limit_rps: float = 1.0,
) -> DiscoveryResult:
    """
    Auto-discover crawl configuration from a user-provided URL.
    
    This function:
    1. Normalizes the URL (adds https://, extracts domain)
    2. Fetches robots.txt to discover sitemaps
    3. Samples sitemaps to estimate URL counts
    4. Recommends a crawl strategy
    
    Args:
        user_input: Raw URL from user (e.g., "mio.se/soffor")
        fetcher: Optional PoliteFetcher instance
        rate_limit_rps: Rate limit for discovery requests
        
    Returns:
        DiscoveryResult with all derived configuration and preview data
    """
    errors: list[str] = []
    warnings: list[str] = []
    
    # Step 1: Normalize URL
    try:
        normalized = normalize_source_url(user_input)
    except ValueError as e:
        return DiscoveryResult(
            input_url=user_input,
            normalized_url="",
            domain="",
            base_url="",
            seed_url="",
            seed_path="",
            seed_path_pattern="",
            robots_found=False,
            sitemaps_found=[],
            sitemap_count=0,
            total_urls_sampled=0,
            product_urls_estimated=0,
            category_urls_estimated=0,
            matching_path_urls=0,
            suggested_strategy="crawl",
            strategy_reason=f"URL normalization failed: {e}",
            errors=[str(e)],
            warnings=[],
        )
    
    domain = normalized["domain"]
    base_url = normalized["baseUrl"]
    seed_url = normalized["seedUrl"]
    seed_path = normalized["seedPath"]
    seed_path_pattern = normalized["seedPathPattern"]
    
    # Create fetcher if not provided
    own_fetcher = fetcher is None
    if own_fetcher:
        fetcher = PoliteFetcher(user_agent="Swiper-Discovery/1.0")
    
    try:
        # Step 2: Fetch robots.txt
        robots_found = False
        sitemaps: list[str] = []
        
        try:
            robots_url = f"{base_url}/robots.txt"
            r = fetcher.fetch(
                robots_url,
                base_url=base_url,
                robots_respect=False,
                rate_limit_rps=rate_limit_rps,
            )
            robots_found = True
            sitemaps = _extract_sitemaps_from_robots(r.text)
        except FetchError as e:
            warnings.append(f"Could not fetch robots.txt: {e}")
        except Exception as e:
            warnings.append(f"Error reading robots.txt: {e}")
        
        # Fallback sitemap locations if none found in robots.txt
        if not sitemaps:
            sitemaps = [
                f"{base_url}/sitemap.xml",
                f"{base_url}/sitemap_index.xml",
            ]
            warnings.append("No sitemaps in robots.txt, trying default locations")
        
        # Step 3: Sample sitemaps to estimate counts
        total_sampled = 0
        product_estimated = 0
        category_estimated = 0
        matching_count = 0
        valid_sitemaps: list[str] = []
        
        for sm_url in sitemaps[:20]:  # Limit initial sitemap check
            try:
                r = fetcher.fetch(
                    sm_url,
                    base_url=base_url,
                    robots_respect=False,
                    rate_limit_rps=rate_limit_rps,
                )
                # Verify it's valid XML
                urls, nested = _parse_sitemap_xml(r.text)
                if urls or nested:
                    valid_sitemaps.append(sm_url)
                    # Count nested sitemaps
                    valid_sitemaps.extend(nested[:50])  # Cap nested
            except Exception:
                continue
        
        # Remove duplicates
        valid_sitemaps = list(dict.fromkeys(valid_sitemaps))
        
        if valid_sitemaps:
            total_sampled, product_estimated, category_estimated, matching_count = \
                _count_sitemap_urls(
                    fetcher,
                    valid_sitemaps,
                    seed_path_pattern,
                    domain,
                    rate_limit_rps=rate_limit_rps,
                )
        
        # Step 4: Determine strategy
        strategy: Literal["sitemap", "crawl"]
        strategy_reason: str
        
        if len(valid_sitemaps) > 0 and total_sampled > 0:
            if matching_count > 50:
                strategy = "sitemap"
                strategy_reason = f"Found {len(valid_sitemaps)} sitemaps with ~{matching_count} URLs matching path pattern"
            elif product_estimated > 100:
                strategy = "sitemap"
                strategy_reason = f"Found {product_estimated} product URLs in sitemaps"
            else:
                strategy = "crawl"
                strategy_reason = "Few matching URLs in sitemaps, category crawl recommended"
        else:
            strategy = "crawl"
            strategy_reason = "No sitemaps found or accessible, using category crawl"
            if not valid_sitemaps:
                warnings.append("No valid sitemaps found")
        
        return DiscoveryResult(
            input_url=user_input,
            normalized_url=normalized["normalized"],
            domain=domain,
            base_url=base_url,
            seed_url=seed_url,
            seed_path=seed_path,
            seed_path_pattern=seed_path_pattern,
            robots_found=robots_found,
            sitemaps_found=valid_sitemaps[:20],  # Cap for response size
            sitemap_count=len(valid_sitemaps),
            total_urls_sampled=total_sampled,
            product_urls_estimated=product_estimated,
            category_urls_estimated=category_estimated,
            matching_path_urls=matching_count,
            suggested_strategy=strategy,
            strategy_reason=strategy_reason,
            errors=errors,
            warnings=warnings,
        )
        
    finally:
        if own_fetcher and fetcher:
            fetcher.close()


def derive_source_config(discovery: DiscoveryResult) -> dict:
    """
    Derive the full source configuration from discovery results.
    
    This generates the 'derived' object that will be stored alongside
    the user's original input in the source document.
    """
    return {
        "domain": discovery.domain,
        "baseUrl": discovery.base_url,
        "seedUrl": discovery.seed_url,
        "seedPath": discovery.seed_path,
        "seedPathPattern": discovery.seed_path_pattern,
        "strategy": discovery.suggested_strategy,
        "sitemapUrls": discovery.sitemaps_found[:50],  # Cap storage
        "discoveredAt": None,  # Will be set by caller
    }
