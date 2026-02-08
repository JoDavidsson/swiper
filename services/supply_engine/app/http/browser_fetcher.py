from __future__ import annotations

import threading
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class BrowserFetchResult:
    url: str
    final_url: str
    status_code: int
    text: str
    headers: dict[str, str]
    elapsed_ms: int


class BrowserFetcher:
    """
    Playwright-backed HTML fetcher for JS-rendered pages.

    - Lazy-initializes and reuses a browser process.
    - Creates a fresh context per request (cookie/session isolation).
    - Provides explicit close() for graceful shutdown.
    """

    def __init__(
        self,
        *,
        user_agent: str,
        viewport: tuple[int, int] = (1280, 800),
        headless: bool = True,
    ):
        self._user_agent = user_agent
        self._viewport = {"width": int(viewport[0]), "height": int(viewport[1])}
        self._headless = headless
        self._lock = threading.Lock()
        self._playwright = None
        self._browser = None

    def _ensure_browser(self) -> None:
        if self._browser is not None:
            return
        try:
            from playwright.sync_api import sync_playwright
        except Exception as exc:
            raise RuntimeError(
                "Playwright is not installed. Add playwright and run browser install."
            ) from exc

        self._playwright = sync_playwright().start()
        self._browser = self._playwright.chromium.launch(headless=self._headless)

    def _scroll_for_lazy_content(self, page, *, max_scrolls: int = 15) -> None:
        """
        Scroll the page to trigger lazy-loaded / infinite-scroll content.

        Many SPA category pages (Sleepo, Homeroom, etc.) only render products
        that are in or near the viewport.  By scrolling down in increments and
        waiting for the DOM to settle we capture the full product grid.

        Strategy:
          1. Record the current document height.
          2. Scroll down by one viewport height (800 px).
          3. Wait up to 1.5 s for network activity to finish.
          4. If the document height grew, repeat (up to *max_scrolls*).
          5. Stop early after 3 consecutive scrolls with no new content.
        """
        no_growth_streak = 0
        prev_height = page.evaluate("() => document.body.scrollHeight")

        for _ in range(max_scrolls):
            page.evaluate("() => window.scrollBy(0, 800)")
            try:
                page.wait_for_load_state("networkidle", timeout=1_500)
            except Exception:
                # networkidle may not fire if the page has persistent connections
                # (analytics, websockets).  A short sleep is an acceptable fallback.
                page.wait_for_timeout(500)

            new_height = page.evaluate("() => document.body.scrollHeight")
            if new_height <= prev_height:
                no_growth_streak += 1
                if no_growth_streak >= 3:
                    break
            else:
                no_growth_streak = 0
            prev_height = new_height

        # Scroll back to top so the captured HTML starts from the beginning.
        page.evaluate("() => window.scrollTo(0, 0)")

    def fetch(
        self,
        url: str,
        *,
        timeout_ms: int = 15_000,
        scroll_for_content: bool = False,
        max_scrolls: int = 15,
    ) -> BrowserFetchResult:
        started = int(time.time() * 1000)
        with self._lock:
            self._ensure_browser()
            context = None
            try:
                context = self._browser.new_context(
                    user_agent=self._user_agent,
                    viewport=self._viewport,
                )
                page = context.new_page()
                response = page.goto(url, wait_until="networkidle", timeout=int(timeout_ms))

                # Optionally scroll the page to reveal lazy-loaded content
                # (critical for SPA category pages with infinite scroll).
                if scroll_for_content:
                    try:
                        self._scroll_for_lazy_content(page, max_scrolls=max_scrolls)
                    except Exception:
                        pass  # Best-effort; don't fail the whole fetch

                html = page.content() or ""
                final_url = page.url or url
                status_code = int(response.status) if response is not None else 200
                headers = {}
                if response is not None:
                    try:
                        headers = dict(response.all_headers() or {})
                    except Exception:
                        headers = {}
                elapsed = int(time.time() * 1000) - started
                return BrowserFetchResult(
                    url=url,
                    final_url=final_url,
                    status_code=status_code,
                    text=html,
                    headers=headers,
                    elapsed_ms=elapsed,
                )
            finally:
                if context is not None:
                    try:
                        context.close()
                    except Exception:
                        pass

    def close(self) -> None:
        with self._lock:
            if self._browser is not None:
                try:
                    self._browser.close()
                except Exception:
                    pass
                self._browser = None
            if self._playwright is not None:
                try:
                    self._playwright.stop()
                except Exception:
                    pass
                self._playwright = None
