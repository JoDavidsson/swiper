import hashlib
import threading
import time
from dataclasses import dataclass
from typing import Iterable
from urllib.parse import urlparse, urljoin
from urllib.robotparser import RobotFileParser

import httpx

from app.normalization import extract_domain_root, canonical_domain


class FetchError(RuntimeError):
    pass


@dataclass(frozen=True)
class FetchResult:
    url: str
    final_url: str
    status_code: int
    text: str
    headers: dict[str, str]
    elapsed_ms: int
    method: str = "http"

    @property
    def html_hash(self) -> str:
        return hashlib.sha256(self.text.encode("utf-8", errors="ignore")).hexdigest()

    @property
    def html(self) -> str:
        # Backward-compatible alias used by older call sites.
        return self.text


def _now_ms() -> int:
    return int(time.time() * 1000)


def _get_domain(url: str) -> str:
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return ""


def _is_https_url(url: str) -> bool:
    try:
        return urlparse(url).scheme in ("http", "https")
    except Exception:
        return False


def _allowlisted(url: str, *, allowlist_policy: dict | None) -> bool:
    if not allowlist_policy:
        return True
    if not _is_https_url(url):
        return False
    p = urlparse(url)
    domain = p.netloc.lower()
    domains = [d.lower() for d in (allowlist_policy.get("domains") or [])]
    prefixes = allowlist_policy.get("pathPrefixes") or []
    if domains and domain not in domains:
        return False
    if prefixes:
        path = p.path or "/"
        # Always allow robots and sitemaps when domain is allowlisted; they live outside
        # typical product/category prefixes and are needed for compliant discovery.
        lower_path = path.lower()
        if lower_path == "/robots.txt" or "sitemap" in lower_path:
            return True
        if not any(path.startswith(pref) for pref in prefixes):
            return False
    return True


# Per-domain retry policy configuration (A5)
# Domains can be configured with different retry/backoff settings
DEFAULT_RETRY_POLICY = {
    "max_retries": 2,
    "base_backoff_s": 0.5,
    "backoff_multiplier": 2.0,
    "retry_on_429": True,
    "retry_on_5xx": True,
    "retry_on_timeout": True,
    "cooldown_after_429_s": 10.0,  # Extra wait after a 429
}


class PoliteFetcher:
    """
    Sync HTTP fetcher with:
    - per-domain delay (based on rateLimitRps)
    - per-domain retry/backoff policies (A5)
    - retries with exponential backoff for transient failures
    - optional robots.txt checks (cache per domain)
    - failure tracking per domain for circuit-breaking

    This is intentionally simple and deterministic; concurrency can be added later.
    """

    def __init__(
        self,
        *,
        user_agent: str,
        timeout_s: float = 20.0,
        max_retries: int = 2,
        domain_retry_policies: dict[str, dict] | None = None,
        browser_fallback: bool = False,
        browser_timeout_s: float = 15.0,
    ):
        self._client = httpx.Client(
            headers={"User-Agent": user_agent},
            timeout=httpx.Timeout(timeout_s),
            follow_redirects=True,
        )
        self._max_retries = max_retries
        self._last_request_ms_by_domain: dict[str, int] = {}
        self._robots_by_domain: dict[str, RobotFileParser | None] = {}
        # Thread-safety: lock protects rate-limit state for concurrent fetching
        self._rate_lock = threading.Lock()
        # A5: Per-domain retry policies
        self._domain_retry_policies = domain_retry_policies or {}
        # A5: Failure counters per domain for observability
        self._domain_failure_counts: dict[str, dict[str, int]] = {}
        self._domain_failure_lock = threading.Lock()
        # Phase 15: Optional browser fallback for JS-rendered pages.
        self._browser_fallback = bool(browser_fallback)
        self._browser_timeout_ms = int(max(browser_timeout_s, 1.0) * 1000)
        self._browser_fetcher = None
        self._browser_lock = threading.Lock()

    def close(self) -> None:
        self._client.close()
        if self._browser_fetcher is not None:
            try:
                self._browser_fetcher.close()
            except Exception:
                pass

    def _sleep_for_rate_limit(self, *, domain: str, rate_limit_rps: float | None) -> None:
        if not rate_limit_rps or rate_limit_rps <= 0:
            return
        delay_ms = int(1000 / float(rate_limit_rps))
        last = self._last_request_ms_by_domain.get(domain)
        if last is None:
            return
        wait_ms = (last + delay_ms) - _now_ms()
        if wait_ms > 0:
            time.sleep(wait_ms / 1000.0)

    def _get_robots(self, base_url: str) -> RobotFileParser | None:
        """
        Fetch and parse robots.txt for a domain.
        
        IMPORTANT: robots.txt is ALWAYS at the domain root, regardless of
        what path is in base_url. We extract the domain root first.
        
        Cache key uses canonical_domain so www.example.com and example.com
        share the same robots.txt cache entry.
        """
        domain = _get_domain(base_url)
        if not domain:
            return None
        
        # Use canonical domain as cache key so www.x.com and x.com share cache
        cache_key = canonical_domain(domain)
        
        if cache_key in self._robots_by_domain:
            return self._robots_by_domain[cache_key]
        try:
            # Always use domain root for robots.txt (RFC requirement)
            domain_root = extract_domain_root(base_url)
            if not domain_root:
                self._robots_by_domain[cache_key] = None
                return None
            
            robots_url = f"{domain_root}/robots.txt"
            r = self._client.get(robots_url)
            if r.status_code >= 400:
                self._robots_by_domain[cache_key] = None
                return None
            rp = RobotFileParser()
            rp.set_url(robots_url)
            rp.parse((r.text or "").splitlines())
            self._robots_by_domain[cache_key] = rp
            return rp
        except Exception:
            self._robots_by_domain[cache_key] = None
            return None

    def can_fetch(self, *, url: str, base_url: str, robots_respect: bool) -> bool:
        if not robots_respect:
            return True
        rp = self._get_robots(base_url)
        if rp is None:
            return True
        try:
            return bool(rp.can_fetch(self._client.headers.get("User-Agent", "*"), url))
        except Exception:
            return True

    def _get_retry_policy(self, domain: str) -> dict:
        """Get the retry policy for a domain, falling back to defaults."""
        cd = canonical_domain(domain)
        return {**DEFAULT_RETRY_POLICY, **self._domain_retry_policies.get(cd, {})}

    def _record_failure(self, domain: str, failure_type: str) -> None:
        """Track failure counts per domain for observability."""
        cd = canonical_domain(domain)
        with self._domain_failure_lock:
            if cd not in self._domain_failure_counts:
                self._domain_failure_counts[cd] = {}
            self._domain_failure_counts[cd][failure_type] = (
                self._domain_failure_counts[cd].get(failure_type, 0) + 1
            )

    @property
    def domain_failure_stats(self) -> dict[str, dict[str, int]]:
        """Return a copy of per-domain failure counts for telemetry."""
        with self._domain_failure_lock:
            return {d: dict(c) for d, c in self._domain_failure_counts.items()}

    def _get_browser_fetcher(self):
        if self._browser_fetcher is not None:
            return self._browser_fetcher
        from app.http.browser_fetcher import BrowserFetcher

        self._browser_fetcher = BrowserFetcher(
            user_agent=self._client.headers.get("User-Agent", "SwiperBot/0.1"),
            viewport=(1280, 800),
            headless=True,
        )
        return self._browser_fetcher

    def _should_refetch_with_browser(self, html: str) -> bool:
        if not self._browser_fallback or not html:
            return False
        try:
            from app.http.render_detector import needs_browser_render
            return bool(needs_browser_render(html))
        except Exception:
            return False

    def _try_browser_fetch(
        self,
        *,
        url: str,
        domain: str,
        rate_limit_rps: float | None,
        verbose: bool,
    ) -> FetchResult | None:
        if not self._browser_fallback:
            return None
        try:
            # Use same per-domain pacing as HTTP requests.
            with self._rate_lock:
                self._sleep_for_rate_limit(domain=domain, rate_limit_rps=rate_limit_rps)
                self._last_request_ms_by_domain[domain] = _now_ms()
            with self._browser_lock:
                br = self._get_browser_fetcher().fetch(url, timeout_ms=self._browser_timeout_ms)
            if verbose:
                print(f"         [fetch] Browser fallback succeeded: {url[:80]}", flush=True)
            return FetchResult(
                url=br.url,
                final_url=br.final_url,
                status_code=br.status_code,
                text=br.text or "",
                headers=br.headers or {},
                elapsed_ms=br.elapsed_ms,
                method="browser",
            )
        except Exception as e:
            self._record_failure(domain, "browser_error")
            if verbose:
                print(f"         [fetch] Browser fallback failed: {str(e)[:120]}", flush=True)
            return None

    def fetch(
        self,
        url: str,
        *,
        base_url: str = "",
        allowlist_policy: dict | None = None,
        robots_respect: bool = True,
        rate_limit_rps: float | None = None,
        verbose: bool = False,
    ) -> FetchResult:
        if not _allowlisted(url, allowlist_policy=allowlist_policy):
            if verbose:
                print(f"         [fetch] BLOCKED by allowlist: {url[:80]}", flush=True)
            raise FetchError("URL blocked by allowlist policy")
        if base_url and not self.can_fetch(url=url, base_url=base_url, robots_respect=robots_respect):
            if verbose:
                print(f"         [fetch] BLOCKED by robots.txt: {url[:80]}", flush=True)
            raise FetchError("Blocked by robots.txt")

        domain = _get_domain(url)
        policy = self._get_retry_policy(domain)
        max_retries = policy["max_retries"]
        base_backoff = policy["base_backoff_s"]
        backoff_mult = policy["backoff_multiplier"]

        attempt = 0
        last_exc: Exception | None = None
        while attempt <= max_retries:
            attempt += 1
            try:
                # Thread-safe rate limiting: lock around check+sleep+record
                # so concurrent threads properly space out requests.
                # The actual HTTP request happens OUTSIDE the lock for true concurrency.
                with self._rate_lock:
                    self._sleep_for_rate_limit(domain=domain, rate_limit_rps=rate_limit_rps)
                    self._last_request_ms_by_domain[domain] = _now_ms()

                started = _now_ms()
                r = self._client.get(url)
                elapsed_ms = _now_ms() - started

                # Retry on 429 (rate limited)
                if r.status_code == 429 and policy["retry_on_429"]:
                    self._record_failure(domain, "429")
                    if attempt <= max_retries:
                        backoff_s = base_backoff * (backoff_mult ** (attempt - 1))
                        # A5: Extra cooldown on 429 to respect rate limits
                        backoff_s = max(backoff_s, policy["cooldown_after_429_s"])
                        time.sleep(backoff_s)
                        continue
                    browser = self._try_browser_fetch(
                        url=url,
                        domain=domain,
                        rate_limit_rps=rate_limit_rps,
                        verbose=verbose,
                    )
                    if browser is not None:
                        return browser
                    raise FetchError(f"HTTP {r.status_code}")

                # Retry on 5xx (server error)
                if 500 <= r.status_code <= 599 and policy["retry_on_5xx"]:
                    self._record_failure(domain, f"5xx_{r.status_code}")
                    if attempt <= max_retries:
                        backoff_s = base_backoff * (backoff_mult ** (attempt - 1))
                        time.sleep(backoff_s)
                        continue
                    browser = self._try_browser_fetch(
                        url=url,
                        domain=domain,
                        rate_limit_rps=rate_limit_rps,
                        verbose=verbose,
                    )
                    if browser is not None:
                        return browser
                    raise FetchError(f"HTTP {r.status_code}")

                if r.status_code >= 400:
                    self._record_failure(domain, f"4xx_{r.status_code}")
                    browser = self._try_browser_fetch(
                        url=url,
                        domain=domain,
                        rate_limit_rps=rate_limit_rps,
                        verbose=verbose,
                    )
                    if browser is not None:
                        return browser
                    raise FetchError(f"HTTP {r.status_code}")

                http_result = FetchResult(
                    url=url,
                    final_url=str(r.url),
                    status_code=r.status_code,
                    text=r.text or "",
                    headers={k: v for k, v in r.headers.items()},
                    elapsed_ms=elapsed_ms,
                    method="http",
                )
                if self._should_refetch_with_browser(http_result.text):
                    browser = self._try_browser_fetch(
                        url=url,
                        domain=domain,
                        rate_limit_rps=rate_limit_rps,
                        verbose=verbose,
                    )
                    if browser is not None:
                        return browser
                return http_result
            except FetchError:
                raise
            except Exception as e:
                last_exc = e
                failure_type = "timeout" if "timeout" in str(e).lower() else "network"
                self._record_failure(domain, failure_type)
                should_retry = (
                    (failure_type == "timeout" and policy["retry_on_timeout"])
                    or failure_type == "network"
                )
                if should_retry and attempt <= max_retries:
                    backoff_s = base_backoff * (backoff_mult ** (attempt - 1))
                    time.sleep(backoff_s)
                    continue
                browser = self._try_browser_fetch(
                    url=url,
                    domain=domain,
                    rate_limit_rps=rate_limit_rps,
                    verbose=verbose,
                )
                if browser is not None:
                    return browser
                raise FetchError(str(last_exc))


def absolute_url(base_url: str, href: str) -> str | None:
    if not href:
        return None
    href = href.strip()
    if href.startswith("//"):
        return "https:" + href
    if href.startswith("http://") or href.startswith("https://"):
        return href
    if href.startswith("/"):
        return urljoin(base_url.rstrip("/") + "/", href.lstrip("/"))
    return urljoin(base_url.rstrip("/") + "/", href)


def filter_allowlisted(urls: Iterable[str], *, allowlist_policy: dict | None) -> list[str]:
    out: list[str] = []
    for u in urls:
        if _allowlisted(u, allowlist_policy=allowlist_policy):
            out.append(u)
    return out
