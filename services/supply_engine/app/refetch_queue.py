from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any


def _to_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    # Firestore Timestamp has to_datetime().
    if hasattr(value, "to_datetime"):
        try:
            dt = value.to_datetime()
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except Exception:
            return None
    return None


def get_refetch_candidates(db, source_id: str, limit: int = 100) -> list[dict]:
    """
    Return low-quality item docs eligible for a browser refetch pass.

    Eligibility:
    - extractionMeta.completeness < 0.6
    - extractionMeta.fetchMethod == "http"
    - lastUpdatedAt older than 24h
    """
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    out: list[dict] = []

    # Preferred server-side query.
    try:
        query = (
            db.collection("items")
            .where("sourceId", "==", source_id)
            .where("extractionMeta.completeness", "<", 0.6)
            .where("extractionMeta.fetchMethod", "==", "http")
            .where("lastUpdatedAt", "<=", cutoff)
            .limit(int(limit))
        )
        docs = query.stream()
    except Exception:
        # Fallback when composite indexes are missing: broader query + in-process filter.
        docs = (
            db.collection("items")
            .where("sourceId", "==", source_id)
            .limit(max(int(limit) * 5, 200))
            .stream()
        )

    for doc in docs:
        data = doc.to_dict() or {}
        meta = data.get("extractionMeta") if isinstance(data.get("extractionMeta"), dict) else {}
        completeness = float(meta.get("completeness") or 0.0)
        fetch_method = str(meta.get("fetchMethod") or "").lower()
        updated_at = _to_datetime(data.get("lastUpdatedAt"))
        if completeness >= 0.6:
            continue
        if fetch_method != "http":
            continue
        if updated_at and updated_at > cutoff:
            continue
        out.append(
            {
                "id": doc.id,
                "sourceUrl": data.get("sourceUrl"),
                "outboundUrl": data.get("outboundUrl"),
                "canonicalUrl": data.get("canonicalUrl"),
                "extractionMeta": meta,
            }
        )
        if len(out) >= int(limit):
            break

    return out
