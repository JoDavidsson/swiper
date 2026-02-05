import hashlib
import time
from dataclasses import dataclass
from typing import Iterable
from urllib.parse import urlparse, urljoin
from urllib.robotparser import RobotFileParser

import httpx

from app.normalization import extract_domain_root


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

    @property
    def html_hash(self) -> str:
        return hashlib.sha256(self.text.encode("utf-8", errors="ignore")).hexdigest()


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


class PoliteFetcher:
    """
    Sync HTTP fetcher with:
    - per-domain delay (based on rateLimitRps)
    - retries with exponential backoff for transient failures
    - optional robots.txt checks (cache per domain)

    This is intentionally simple and deterministic; concurrency can be added later.
    """

    def __init__(
        self,
        *,
        user_agent: str,
        timeout_s: float = 20.0,
        max_retries: int = 2,
    ):
        self._client = httpx.Client(
            headers={"User-Agent": user_agent},
            timeout=httpx.Timeout(timeout_s),
            follow_redirects=True,
        )
        self._max_retries = max_retries
        self._last_request_ms_by_domain: dict[str, int] = {}
        self._robots_by_domain: dict[str, RobotFileParser | None] = {}

    def close(self) -> None:
        self._client.close()

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
        """
        domain = _get_domain(base_url)
        if not domain:
            return None
        if domain in self._robots_by_domain:
            return self._robots_by_domain[domain]
        try:
            # Always use domain root for robots.txt (RFC requirement)
            domain_root = extract_domain_root(base_url)
            if not domain_root:
                self._robots_by_domain[domain] = None
                return None
            
            robots_url = f"{domain_root}/robots.txt"
            r = self._client.get(robots_url)
            if r.status_code >= 400:
                self._robots_by_domain[domain] = None
                return None
            rp = RobotFileParser()
            rp.set_url(robots_url)
            rp.parse((r.text or "").splitlines())
            self._robots_by_domain[domain] = rp
            return rp
        except Exception:
            self._robots_by_domain[domain] = None
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
        attempt = 0
        last_exc: Exception | None = None
        while attempt <= self._max_retries:
            attempt += 1
            try:
                self._sleep_for_rate_limit(domain=domain, rate_limit_rps=rate_limit_rps)
                started = _now_ms()
                r = self._client.get(url)
                elapsed_ms = _now_ms() - started
                self._last_request_ms_by_domain[domain] = _now_ms()

                # Retry on 429 and 5xx.
                if r.status_code == 429 or 500 <= r.status_code <= 599:
                    if attempt <= self._max_retries:
                        backoff_s = 0.5 * (2 ** (attempt - 1))
                        time.sleep(backoff_s)
                        continue
                    raise FetchError(f"HTTP {r.status_code}")

                if r.status_code >= 400:
                    raise FetchError(f"HTTP {r.status_code}")

                return FetchResult(
                    url=url,
                    final_url=str(r.url),
                    status_code=r.status_code,
                    text=r.text or "",
                    headers={k: v for k, v in r.headers.items()},
                    elapsed_ms=elapsed_ms,
                )
            except Exception as e:
                last_exc = e
                if attempt <= self._max_retries:
                    backoff_s = 0.5 * (2 ** (attempt - 1))
                    time.sleep(backoff_s)
                    continue
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
