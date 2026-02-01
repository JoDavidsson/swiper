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

from app.feed_ingestion import run_feed_ingestion
from app.sources import get_sources_from_config

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


@app.post("/run/{source_id}")
def run_ingestion(source_id: str):
    """Trigger ingestion for a source. Admin-only in production."""
    sources = get_sources_from_config()
    source = next((s for s in sources if s.get("id") == source_id), None)
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    if not source.get("isEnabled", True):
        raise HTTPException(status_code=400, detail="Source is disabled")
    try:
        result = run_feed_ingestion(source_id, source)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
