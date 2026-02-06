from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from urllib.parse import urlparse, urljoin, urlunparse

from bs4 import BeautifulSoup

from app.http.fetcher import PoliteFetcher, FetchError, absolute_url, filter_allowlisted
from app.locator.classifier import classify_url
from app.normalization import domains_equivalent


@dataclass(frozen=True)
class DiscoveredUrl:
    url: str
    source: str  # crawl|manual
    confidence: float
    url_type_hint: str = "unknown"  # product|category|unknown

def _domain(url: str) -> str:
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return ""


def _strip_fragment(url: str) -> str:
    try:
        p = urlparse(url)
        if not p.fragment:
            return url
        return urlunparse((p.scheme, p.netloc, p.path, p.params, p.query, ""))
    except Exception:
        return url


def _extract_links(base_url: str, html: str) -> list[str]:
    soup = BeautifulSoup(html, "lxml")
    links: list[str] = []
    for a in soup.find_all("a"):
        href = a.get("href")
        if not href:
            continue
        u = absolute_url(base_url, href)
        if not u:
            continue
        links.append(_strip_fragment(u))
    return links


def _extract_pagination_links(base_url: str, html: str) -> list[str]:
    soup = BeautifulSoup(html, "lxml")
    links: list[str] = []
    # rel=next is the most robust
    ln = soup.find("link", rel=lambda x: x and "next" in x.lower())
    if ln and ln.get("href"):
        u = absolute_url(base_url, ln.get("href"))
        if u:
            links.append(_strip_fragment(u))

    # common pagination anchors
    for a in soup.select("a[aria-label*='Next'], a[rel='next'], a[href*='page='], a[href*='?p='], a[href*='/page/']"):
        href = a.get("href")
        u = absolute_url(base_url, href) if href else None
        if u:
            links.append(_strip_fragment(u))

    # de-dupe while preserving order
    out: list[str] = []
    seen: set[str] = set()
    for u in links:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def discover_from_category_crawl(
    fetcher: PoliteFetcher,
    *,
    base_url: str,
    seed_urls: list[str],
    allowlist_policy: dict | None,
    robots_respect: bool,
    rate_limit_rps: float | None,
    include_keywords: list[str] | None = None,
    max_depth: int = 2,
    max_pages: int = 50,
    max_out_urls: int = 2000,
) -> list[DiscoveredUrl]:
    """
    Bounded BFS crawl starting from seed category URLs.

    Output is a mix of product and category candidates with heuristic confidence.
    """
    print(f"         [crawler] Starting category crawl from {len(seed_urls)} seed(s)", flush=True)
    for s in seed_urls[:3]:
        print(f"                   - {s}", flush=True)
    
    seeds = [u for u in seed_urls if u]
    seeds = filter_allowlisted(seeds, allowlist_policy=allowlist_policy)
    if not seeds:
        print(f"         [crawler] No seeds passed allowlist filter!", flush=True)
        return []

    print(f"         [crawler] {len(seeds)} seeds after allowlist filter", flush=True)
    
    base_domain = _domain(base_url)
    q: deque[tuple[str, int]] = deque((u, 0) for u in seeds)
    seen_pages: set[str] = set()

    out: list[DiscoveredUrl] = []
    out_seen: set[str] = set()

    while q and len(seen_pages) < max_pages and len(out) < max_out_urls:
        url, depth = q.popleft()
        if url in seen_pages:
            continue
        # Same-site check (treats www.x.com and x.com as equivalent)
        url_domain = _domain(url)
        if base_domain and url_domain and not domains_equivalent(url_domain, base_domain):
            continue
        seen_pages.add(url)
        
        print(f"         [crawler] Crawling (depth={depth}): {url[:70]}...", flush=True)
        
        try:
            r = fetcher.fetch(
                url,
                base_url=base_url,
                allowlist_policy=allowlist_policy,
                robots_respect=robots_respect,
                rate_limit_rps=rate_limit_rps,
            )
        except FetchError as e:
            print(f"         [crawler] Fetch failed: {e}", flush=True)
            continue

        links = filter_allowlisted(_extract_links(r.final_url, r.text), allowlist_policy=allowlist_policy)
        pag_links = filter_allowlisted(_extract_pagination_links(r.final_url, r.text), allowlist_policy=allowlist_policy)
        links = links + [u for u in pag_links if u not in links]
        
        print(f"         [crawler] Found {len(links)} links on page", flush=True)

        # Emit candidates
        added_this_page = 0
        for u in links:
            if len(out) >= max_out_urls:
                break
            # Same-site check (treats www.x.com and x.com as equivalent)
            link_domain = _domain(u)
            if base_domain and link_domain and not domains_equivalent(link_domain, base_domain):
                continue
            if u in out_seen:
                continue
            c = classify_url(u)
            out.append(DiscoveredUrl(url=u, source="crawl", confidence=c.confidence, url_type_hint=c.url_type_hint))
            out_seen.add(u)
            added_this_page += 1

        if added_this_page > 0:
            print(f"         [crawler] Added {added_this_page} new URLs (total: {len(out)})", flush=True)

        # Enqueue follow links (bounded)
        if depth < max_depth:
            queued = 0
            for u in links:
                if u in seen_pages:
                    continue
                c = classify_url(u)
                # Only follow category-ish links to keep crawl narrow.
                if c.url_type_hint == "product":
                    continue
                if include_keywords:
                    lowered = u.lower()
                    if not any(k.lower() in lowered for k in include_keywords):
                        # If keyword filter is set, only follow keyword-relevant links.
                        continue
                q.append((u, depth + 1))
                queued += 1
            if queued > 0:
                print(f"         [crawler] Queued {queued} category links to follow", flush=True)

    product_count = sum(1 for d in out if d.url_type_hint == "product")
    print(f"         [crawler] Discovery complete: {len(out)} URLs ({product_count} products) from {len(seen_pages)} pages", flush=True)
    
    return out

