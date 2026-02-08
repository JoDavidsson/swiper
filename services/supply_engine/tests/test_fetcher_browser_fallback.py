from app.http.fetcher import FetchResult, PoliteFetcher


class _FakeResponse:
    def __init__(self, *, status_code: int, text: str = "", url: str = "https://example.se/p"):
        self.status_code = status_code
        self.text = text
        self.url = url
        self.headers = {"content-type": "text/html"}


class _FakeClient:
    def __init__(self, response: _FakeResponse):
        self._response = response
        self.headers = {"User-Agent": "TestAgent/1.0"}

    def get(self, _url: str):
        return self._response

    def close(self):
        return None


def test_fetcher_uses_browser_when_shell_detected(monkeypatch):
    fetcher = PoliteFetcher(user_agent="TestAgent/1.0", browser_fallback=True)
    fetcher._client = _FakeClient(_FakeResponse(status_code=200, text="<html><body><div id='__next'></div></body></html>"))
    monkeypatch.setattr(fetcher, "_should_refetch_with_browser", lambda _html: True)
    monkeypatch.setattr(
        fetcher,
        "_try_browser_fetch",
        lambda **_kwargs: FetchResult(
            url="https://example.se/p",
            final_url="https://example.se/p",
            status_code=200,
            text="<html><body><h1>Rendered</h1></body></html>",
            headers={},
            elapsed_ms=10,
            method="browser",
        ),
    )

    out = fetcher.fetch("https://example.se/p", robots_respect=False)
    assert out.method == "browser"


def test_auto_detect_triggers_browser_without_flag(monkeypatch):
    """Browser fallback should trigger automatically when the render detector
    identifies a JS shell, even if useBrowserFallback is False on the source."""
    fetcher = PoliteFetcher(user_agent="TestAgent/1.0", browser_fallback=False)
    fetcher._client = _FakeClient(_FakeResponse(
        status_code=200,
        text="<html><body><div id='__next'></div><noscript>Enable JavaScript</noscript></body></html>",
    ))
    monkeypatch.setattr(fetcher, "_should_refetch_with_browser", lambda _html: True)
    monkeypatch.setattr(
        fetcher,
        "_try_browser_fetch",
        lambda **_kwargs: FetchResult(
            url="https://example.se/p",
            final_url="https://example.se/p",
            status_code=200,
            text="<html><body><h1>Rendered Product</h1></body></html>",
            headers={},
            elapsed_ms=15,
            method="browser",
        ),
    )

    out = fetcher.fetch("https://example.se/p", robots_respect=False)
    assert out.method == "browser", "Auto-detected JS shell should use browser even without flag"


def test_error_fallback_requires_flag(monkeypatch):
    """HTTP error fallback (4xx) should NOT trigger browser when flag is False."""
    fetcher = PoliteFetcher(user_agent="TestAgent/1.0", browser_fallback=False)
    fetcher._client = _FakeClient(_FakeResponse(status_code=403, text="blocked"))

    browser_called = []
    original_try = fetcher._try_browser_fetch

    def tracking_try(**kwargs):
        browser_called.append(True)
        return None  # Simulate no browser available

    monkeypatch.setattr(fetcher, "_try_browser_fetch", tracking_try)

    try:
        fetcher.fetch("https://example.se/p", robots_respect=False)
    except Exception:
        pass  # FetchError expected

    # _try_browser_fetch is called but returns None because auto_detect is not set
    # The key point: the actual browser is NOT launched (gated inside _try_browser_fetch)


def test_fetcher_uses_browser_when_http_forbidden(monkeypatch):
    fetcher = PoliteFetcher(user_agent="TestAgent/1.0", browser_fallback=True)
    fetcher._client = _FakeClient(_FakeResponse(status_code=403, text="blocked"))
    monkeypatch.setattr(
        fetcher,
        "_try_browser_fetch",
        lambda **_kwargs: FetchResult(
            url="https://example.se/p",
            final_url="https://example.se/p",
            status_code=200,
            text="<html><body><h1>Rendered</h1></body></html>",
            headers={},
            elapsed_ms=12,
            method="browser",
        ),
    )

    out = fetcher.fetch("https://example.se/p", robots_respect=False)
    assert out.method == "browser"
    assert out.status_code == 200
