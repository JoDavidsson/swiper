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


@app.post("/run/{source_id}")
def run_ingestion(source_id: str):
    """Trigger ingestion for a source. Admin-only in production."""
    sources = get_sources()
    source = next((s for s in sources if s.get("id") == source_id), None)
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    if not source.get("isEnabled", True):
        raise HTTPException(status_code=400, detail="Source is disabled")
    try:
        mode = (source.get("mode") or "feed").lower()
        if mode == "feed":
            result = run_feed_ingestion(source_id, source)
        elif mode == "crawl":
            result = run_crawl_ingestion(source_id, source)
        else:
            raise ValueError(f"Unsupported source mode: {mode}")
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
