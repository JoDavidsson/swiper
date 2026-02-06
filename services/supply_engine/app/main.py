"""
Swiper Supply Engine – content ingestion at scale.
Primary: affiliate/product feeds (CSV/JSON/XML).
Secondary: compliant crawling of allowlisted pages.
Optional: MCP-style AI extraction.
"""
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.crawl_ingestion import run_crawl_ingestion
from app.feed_ingestion import run_feed_ingestion
from app.sources import get_sources
from app.discovery import discover_from_url, derive_source_config

USER_AGENT = os.environ.get("USER_AGENT", "SwiperBot/0.1 (contact: johannes@branchandleaf.se)")


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(title="Swiper Supply Engine", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


class DiscoverRequest(BaseModel):
    """Request body for /discover endpoint."""
    url: str
    rate_limit_rps: float = 1.0


@app.post("/discover")
def discover_source(request: DiscoverRequest):
    """
    Auto-discover crawl configuration from a URL.
    
    This endpoint:
    1. Normalizes the input URL (adds https://, extracts domain)
    2. Fetches robots.txt to discover sitemaps
    3. Samples sitemaps to estimate URL counts
    4. Recommends a crawl strategy (sitemap vs crawl)
    
    Returns a preview with derived configuration without saving anything.
    Use this to validate a URL before creating a source.
    """
    if not request.url or not request.url.strip():
        raise HTTPException(status_code=400, detail="URL is required")
    
    try:
        result = discover_from_url(
            request.url.strip(),
            rate_limit_rps=request.rate_limit_rps,
        )
        
        # Add derived config for convenience
        derived_config = derive_source_config(result)
        
        return {
            "discovery": result.to_dict(),
            "derivedConfig": derived_config,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Discovery failed: {e}")


import uuid


class RunRequest(BaseModel):
    """Optional request body for /run endpoint."""
    run_id: str | None = None  # Correlation ID for logs


@app.post("/run/{source_id}")
def run_ingestion(source_id: str, request: RunRequest | None = None):
    """Trigger ingestion for a source. Admin-only in production."""
    # Generate or use provided run_id for log correlation
    run_id = (request.run_id if request else None) or str(uuid.uuid4())[:8]
    
    def log(msg: str, level: str = "INFO"):
        """Log with run correlation prefix."""
        print(f"[{run_id}] [{level}] {msg}", flush=True)
    
    log(f"Starting ingestion for source: {source_id}")
    
    sources = get_sources()
    source = next((s for s in sources if s.get("id") == source_id), None)
    if not source:
        log("Source not found", "ERROR")
        raise HTTPException(status_code=404, detail="Source not found")
    if not source.get("isEnabled", True):
        log("Source is disabled", "WARN")
        raise HTTPException(status_code=400, detail="Source is disabled")
    
    source_name = source.get("name", source_id)
    log(f"Source: {source_name}, mode: {source.get('mode', 'feed')}")
    
    try:
        mode = (source.get("mode") or "feed").lower()
        if mode == "feed":
            log("Running feed ingestion...")
            result = run_feed_ingestion(source_id, source, run_id=run_id)
        elif mode == "crawl":
            log("Running crawl ingestion...")
            result = run_crawl_ingestion(source_id, source, run_id=run_id)
        else:
            raise ValueError(f"Unsupported source mode: {mode}")
        
        log(f"Ingestion complete: {result.get('status', 'unknown')}")
        # Add run_id to result for correlation
        result["run_id"] = run_id
        return result
    except Exception as e:
        log(f"Ingestion failed: {e}", "ERROR")
        raise HTTPException(status_code=500, detail=str(e))
