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
