"""Crawl ingestion: allowlisted URLs only, robots.txt respected, rate limited. MVP: stub."""
from typing import Any


def run_crawl_ingestion(source_id: str, source: dict) -> dict:
    """Run crawl for a source. MVP: not implemented."""
    return {
        "runId": None,
        "status": "failed",
        "stats": {"fetched": 0, "parsed": 0, "normalized": 0, "upserted": 0, "failed": 0},
        "errorSummary": "Crawl ingestion not implemented in MVP. Use feed ingestion.",
    }
