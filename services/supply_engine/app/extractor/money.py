from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Money:
    amount: float | None
    currency: str | None
    raw: str
    warnings: list[str]


_CURRENCY_RE = re.compile(r"(?i)\\b(sek|kr|kronor|eur|usd)\\b")


def parse_money_sv(raw: str | None) -> Money:
    """
    Parse Swedish price strings into a numeric amount.

    Handles:
    - 12 995 kr
    - 12.995 kr (dot thousand grouping)
    - 12 995:- (suffix)
    - 12 995 SEK
    - 12 995,00 kr (comma decimals)
    """
    s = (raw or "").strip()
    warnings: list[str] = []
    if not s:
        return Money(amount=None, currency=None, raw="", warnings=["missing"])

    s_norm = s.replace("\u00a0", " ").strip()  # nbsp -> space
    cur = None
    m = _CURRENCY_RE.search(s_norm)
    if m:
        tok = m.group(1).lower()
        if tok in ("sek", "kr", "kronor"):
            cur = "SEK"
        elif tok == "eur":
            cur = "EUR"
        elif tok == "usd":
            cur = "USD"

    # Remove currency markers and common suffixes/prefixes
    cleaned = re.sub(_CURRENCY_RE, "", s_norm)
    cleaned = cleaned.replace(":-", "").replace(":", "").strip()
    cleaned = cleaned.replace(" ", "")

    # Keep only digits, separators, and minus
    cleaned = re.sub(r"[^0-9,\\.\\-]", "", cleaned)
    if not cleaned or cleaned in ("-", ",", "."):
        return Money(amount=None, currency=cur, raw=s, warnings=["unparseable"])

    # Swedish heuristic for dot: often thousand separator if exactly 3 digits after dot
    try:
        amount: float | None
        if "," in cleaned and "." in cleaned:
            # If both appear, assume dot thousand sep and comma decimal: 12.995,00
            cleaned2 = cleaned.replace(".", "").replace(",", ".")
            amount = float(cleaned2)
        elif "," in cleaned:
            # comma as decimal separator
            amount = float(cleaned.replace(".", "").replace(",", "."))
        elif "." in cleaned:
            parts = cleaned.split(".")
            if len(parts) == 2 and len(parts[1]) == 3 and parts[0].isdigit() and parts[1].isdigit():
                amount = float(parts[0] + parts[1])  # thousand grouping
            else:
                amount = float(cleaned)
        else:
            amount = float(cleaned)
    except Exception:
        return Money(amount=None, currency=cur, raw=s, warnings=["unparseable"])

    if amount is None:
        return Money(amount=None, currency=cur, raw=s, warnings=["unparseable"])

    if amount <= 0:
        warnings.append("non_positive_amount")
    # Extremely loose sanity band for sofas; keep as warning, not fail.
    if amount < 100:
        warnings.append("suspiciously_low")
    if amount > 500_000:
        warnings.append("suspiciously_high")

    return Money(amount=amount, currency=cur or "SEK", raw=s, warnings=warnings)

