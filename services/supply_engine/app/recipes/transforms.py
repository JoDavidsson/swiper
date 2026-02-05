from __future__ import annotations

from typing import Any
from urllib.parse import urljoin

from app.extractor.money import parse_money_sv


def ensure_absolute_urls(urls: list[str], *, base_url: str) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for u in urls or []:
        if not u:
            continue
        u = str(u).strip()
        if not u:
            continue
        if u.startswith("//"):
            u = "https:" + u
        elif u.startswith("/"):
            u = urljoin(base_url.rstrip("/") + "/", u.lstrip("/"))
        elif not u.startswith(("http://", "https://")):
            u = urljoin(base_url.rstrip("/") + "/", u)
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def parse_money_number_sv(raw: Any) -> tuple[float | None, str | None, list[str], str]:
    m = parse_money_sv(str(raw) if raw is not None else None)
    return m.amount, m.currency, m.warnings, m.raw

