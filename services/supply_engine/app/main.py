"""
Swiper Supply Engine – content ingestion at scale.
Primary: affiliate/product feeds (CSV/JSON/XML).
Secondary: compliant crawling of allowlisted pages.
Optional: MCP-style AI extraction.
"""
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta
from typing import Optional

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


import asyncio
import uuid


class RunRequest(BaseModel):
    """Optional request body for /run endpoint."""
    run_id: str | None = None  # Correlation ID for logs


class BatchRunRequest(BaseModel):
    """Request body for /run-batch endpoint."""
    source_ids: list[str]  # List of source IDs to run in parallel


def _run_single_source(source_id: str, source: dict, run_id: str) -> dict:
    """Run ingestion for a single source. Used by both /run and /run-batch."""
    def log(msg: str, level: str = "INFO"):
        print(f"[{run_id}] [{level}] {msg}", flush=True)
    
    log(f"Starting ingestion for source: {source_id}")
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
        result["run_id"] = run_id
        result["source_id"] = source_id
        return result
    except Exception as e:
        log(f"Ingestion failed: {e}", "ERROR")
        return {"source_id": source_id, "run_id": run_id, "status": "failed", "error": str(e)}


@app.post("/run/{source_id}")
def run_ingestion(source_id: str, request: RunRequest | None = None):
    """Trigger ingestion for a single source. Admin-only in production."""
    run_id = (request.run_id if request else None) or str(uuid.uuid4())[:8]
    
    sources = get_sources()
    source = next((s for s in sources if s.get("id") == source_id), None)
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    if not source.get("isEnabled", True):
        raise HTTPException(status_code=400, detail="Source is disabled")
    
    result = _run_single_source(source_id, source, run_id)
    if result.get("status") == "failed" and "error" in result:
        raise HTTPException(status_code=500, detail=result["error"])
    return result


@app.post("/stop/{source_id}")
def stop_crawl(source_id: str):
    """Stop an active crawl for a source by setting its run status to 'stopped'."""
    from app.firestore_client import get_firestore_client
    db = get_firestore_client()

    # Find active run for this source
    runs = (
        db.collection("ingestionRuns")
        .where("sourceId", "==", source_id)
        .where("status", "==", "running")
        .limit(1)
        .get()
    )

    if not runs:
        raise HTTPException(status_code=404, detail="No active run found for this source")

    run_doc = runs[0]
    run_id = run_doc.id

    # Set status to "stopped" — the crawl loop checks this periodically
    db.collection("ingestionRuns").document(run_id).update({
        "status": "stopped",
        "errorSummary": "Stopped by user",
    })
    print(f"[stop] Stop signal set for run {run_id} (source {source_id})", flush=True)
    return {"status": "ok", "runId": run_id, "message": "Stop signal sent"}


@app.post("/run-batch")
async def run_batch(request: BatchRunRequest):
    """
    Run ingestion for multiple sources in parallel.
    
    Each source runs in its own thread. All sources execute concurrently,
    so 5 retailers that each take 3 minutes will complete in ~3 minutes total
    instead of ~15 minutes.
    
    Returns results for all sources (successes and failures).
    """
    if not request.source_ids:
        raise HTTPException(status_code=400, detail="source_ids required")
    
    sources = get_sources()
    source_map = {s["id"]: s for s in sources if s.get("id")}
    
    # Validate all source IDs before starting
    missing = [sid for sid in request.source_ids if sid not in source_map]
    if missing:
        raise HTTPException(status_code=404, detail=f"Sources not found: {missing}")
    
    disabled = [sid for sid in request.source_ids if not source_map[sid].get("isEnabled", True)]
    if disabled:
        raise HTTPException(status_code=400, detail=f"Sources disabled: {disabled}")
    
    batch_id = str(uuid.uuid4())[:8]
    print(f"\n[batch-{batch_id}] Starting batch run for {len(request.source_ids)} sources", flush=True)
    print(f"[batch-{batch_id}] Sources: {request.source_ids}", flush=True)
    
    # Run all sources in parallel using asyncio.to_thread (each gets its own thread)
    tasks = [
        asyncio.to_thread(
            _run_single_source,
            sid,
            source_map[sid],
            f"{batch_id}-{i}",
        )
        for i, sid in enumerate(request.source_ids)
    ]
    
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    # Process results
    output = []
    for sid, result in zip(request.source_ids, results):
        if isinstance(result, Exception):
            output.append({"source_id": sid, "status": "failed", "error": str(result)})
        else:
            output.append(result)
    
    succeeded = sum(1 for r in output if r.get("status") == "succeeded")
    failed = len(output) - succeeded
    print(f"[batch-{batch_id}] Batch complete: {succeeded} succeeded, {failed} failed", flush=True)
    
    return {
        "batchId": batch_id,
        "total": len(output),
        "succeeded": succeeded,
        "failed": failed,
        "results": output,
    }


# ============================================================================
# IMAGE RE-EXTRACTION
# ============================================================================


class ReExtractImagesRequest(BaseModel):
    """Request body for /re-extract-images endpoint."""
    source_ids: Optional[list[str]] = None  # None = all sources
    limit: int = 500  # Max items to re-extract per source
    dry_run: bool = False  # If true, don't write to Firestore


def _re_extract_images_for_source(source_id: str, limit: int, dry_run: bool) -> dict:
    """
    Re-fetch and re-extract images for items belonging to a source.

    Only updates the `images` field in Firestore - no other fields are touched.
    """
    import time
    from datetime import datetime, timezone
    from concurrent.futures import ThreadPoolExecutor, as_completed
    from app.firestore_client import get_firestore_client
    from app.http.fetcher import PoliteFetcher, FetchError
    from app.extractor.cascade import extract_product_from_html, _is_likely_image_url

    db = get_firestore_client()
    run_id = f"reimg-{str(uuid.uuid4())[:6]}"
    log_prefix = f"[{run_id}][{source_id}]"

    print(f"\n{log_prefix} Starting image re-extraction (limit={limit}, dry_run={dry_run})", flush=True)

    # Query items for this source
    items_ref = db.collection("items").where("sourceId", "==", source_id).limit(limit)
    docs = list(items_ref.stream())
    print(f"{log_prefix} Found {len(docs)} items", flush=True)

    if not docs:
        return {"source_id": source_id, "total": 0, "updated": 0, "failed": 0, "skipped": 0}

    fetcher = PoliteFetcher(user_agent="SwiperBot/0.1 (contact: johannes@branchandleaf.se)")
    updated = 0
    failed = 0
    skipped = 0
    already_good = 0
    start_time = time.time()

    try:
        for i, doc in enumerate(docs):
            data = doc.to_dict() or {}
            item_id = doc.id
            source_url = data.get("sourceUrl") or data.get("outboundUrl") or ""
            current_images = data.get("images") or []
            title = data.get("title", "unknown")

            # Check if current images are already valid
            has_valid_images = False
            if current_images:
                for img in current_images:
                    img_url = img.get("url", "") if isinstance(img, dict) else str(img)
                    if _is_likely_image_url(img_url):
                        has_valid_images = True
                        break

            if has_valid_images:
                already_good += 1
                continue  # Skip items that already have valid images

            if not source_url:
                skipped += 1
                continue

            # Re-fetch the page
            try:
                r = fetcher.fetch(
                    source_url,
                    base_url=source_url,
                    allowlist_policy=None,
                    robots_respect=True,
                    rate_limit_rps=2.0,
                )
            except FetchError as e:
                failed += 1
                if (i + 1) % 20 == 0:
                    print(f"{log_prefix} [{i+1}/{len(docs)}] Fetch failed: {source_url[:50]}...", flush=True)
                continue

            # Re-extract
            extracted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            product = extract_product_from_html(
                source_id=source_id,
                fetched_url=source_url,
                final_url=r.final_url,
                html=r.text,
                extracted_at_iso=extracted_at,
            )

            if product is None or not product.images:
                failed += 1
                if (i + 1) % 20 == 0:
                    print(f"{log_prefix} [{i+1}/{len(docs)}] No images extracted: {title[:40]}", flush=True)
                continue

            # Build new image objects
            new_img_objs = [
                {"url": u, "alt": (title or "")[:200]}
                for u in product.images
                if isinstance(u, str) and u
            ]

            if not new_img_objs:
                failed += 1
                continue

            # Compare old vs new
            old_urls = sorted([img.get("url", "") if isinstance(img, dict) else str(img) for img in current_images])
            new_urls = sorted([img["url"] for img in new_img_objs])

            if old_urls == new_urls:
                skipped += 1
                continue

            # Update Firestore (images only)
            if not dry_run:
                try:
                    db.collection("items").document(item_id).update({
                        "images": new_img_objs,
                        "imageReExtractedAt": extracted_at,
                    })
                    updated += 1
                except Exception as e:
                    failed += 1
                    print(f"{log_prefix} Firestore update failed for {item_id}: {e}", flush=True)
                    continue
            else:
                updated += 1  # Count as "would update" in dry run

            if (i + 1) % 10 == 0 or (i + 1) == len(docs):
                elapsed = time.time() - start_time
                print(
                    f"{log_prefix} [{i+1}/{len(docs)}] "
                    f"updated={updated} failed={failed} skipped={skipped} already_good={already_good} "
                    f"({elapsed:.1f}s)",
                    flush=True,
                )

    finally:
        try:
            fetcher.close()
        except Exception:
            pass

    elapsed = time.time() - start_time
    print(
        f"{log_prefix} DONE in {elapsed:.1f}s: "
        f"updated={updated}, failed={failed}, skipped={skipped}, already_good={already_good}",
        flush=True,
    )

    return {
        "source_id": source_id,
        "total": len(docs),
        "updated": updated,
        "failed": failed,
        "skipped": skipped,
        "already_good": already_good,
        "duration_sec": round(elapsed, 1),
        "dry_run": dry_run,
    }


@app.post("/re-extract-images")
async def re_extract_images(request: ReExtractImagesRequest):
    """
    Re-fetch pages and re-extract images for items with broken/missing images.

    Only updates the `images` field in Firestore.
    Pass source_ids to target specific retailers, or omit for all sources.
    Use dry_run=true to preview without writing.
    """
    sources = get_sources()
    source_map = {s["id"]: s for s in sources if s.get("id")}

    if request.source_ids:
        target_ids = request.source_ids
        missing = [sid for sid in target_ids if sid not in source_map]
        if missing:
            raise HTTPException(status_code=404, detail=f"Sources not found: {missing}")
    else:
        target_ids = list(source_map.keys())

    print(f"\n{'='*60}", flush=True)
    print(f"  IMAGE RE-EXTRACTION for {len(target_ids)} sources", flush=True)
    print(f"  Sources: {target_ids}", flush=True)
    print(f"  Limit per source: {request.limit}", flush=True)
    print(f"  Dry run: {request.dry_run}", flush=True)
    print(f"{'='*60}", flush=True)

    # Run each source sequentially (to avoid overwhelming retailer servers)
    results = []
    for sid in target_ids:
        try:
            result = await asyncio.to_thread(
                _re_extract_images_for_source,
                sid,
                request.limit,
                request.dry_run,
            )
            results.append(result)
        except Exception as e:
            results.append({
                "source_id": sid,
                "status": "error",
                "error": str(e),
            })

    total_updated = sum(r.get("updated", 0) for r in results)
    total_failed = sum(r.get("failed", 0) for r in results)

    return {
        "sources": len(results),
        "total_updated": total_updated,
        "total_failed": total_failed,
        "dry_run": request.dry_run,
        "results": results,
    }


# ============================================================================
# IMAGE HEALTH STATS
# ============================================================================


@app.get("/image-health")
def image_health(source_id: Optional[str] = None):
    """
    Return image health statistics per retailer.

    Counts items by image status: valid_image, no_image, likely_broken.
    Pass source_id to filter to a single retailer.
    """
    from app.firestore_client import get_firestore_client
    from app.extractor.cascade import _is_likely_image_url

    db = get_firestore_client()

    # Query items
    query = db.collection("items")
    if source_id:
        query = query.where("sourceId", "==", source_id)

    docs = list(query.stream())

    # Aggregate by source
    stats: dict[str, dict] = {}

    for doc in docs:
        data = doc.to_dict() or {}
        sid = data.get("sourceId", "unknown")
        if sid not in stats:
            stats[sid] = {
                "source_id": sid,
                "total_items": 0,
                "valid_image": 0,
                "no_image": 0,
                "likely_broken": 0,
                "sample_broken": [],
            }

        stats[sid]["total_items"] += 1
        images = data.get("images") or []

        if not images:
            stats[sid]["no_image"] += 1
            continue

        # Check if any image URL passes validation
        has_valid = False
        for img in images:
            url = img.get("url", "") if isinstance(img, dict) else str(img)
            if _is_likely_image_url(url):
                has_valid = True
                break

        if has_valid:
            stats[sid]["valid_image"] += 1
        else:
            stats[sid]["likely_broken"] += 1
            # Keep a few samples for debugging
            if len(stats[sid]["sample_broken"]) < 3:
                sample_url = images[0].get("url", "") if isinstance(images[0], dict) else str(images[0])
                stats[sid]["sample_broken"].append({
                    "item_title": (data.get("title") or "")[:50],
                    "image_url": sample_url[:100],
                })

    # Sort by broken count (worst first)
    sorted_stats = sorted(stats.values(), key=lambda x: x["likely_broken"], reverse=True)

    # Summary
    total_items = sum(s["total_items"] for s in sorted_stats)
    total_valid = sum(s["valid_image"] for s in sorted_stats)
    total_broken = sum(s["likely_broken"] for s in sorted_stats)
    total_no_image = sum(s["no_image"] for s in sorted_stats)

    return {
        "summary": {
            "total_items": total_items,
            "valid_image": total_valid,
            "no_image": total_no_image,
            "likely_broken": total_broken,
            "health_pct": round(total_valid / total_items * 100, 1) if total_items else 0,
        },
        "by_source": sorted_stats,
    }


# ============================================================================
# EPIC C: SORTING ENGINE ENDPOINTS
# ============================================================================

class ClassifyRequest(BaseModel):
    """Request body for /classify endpoint."""
    item_id: str | None = None  # Classify a single item by ID
    source_id: str | None = None  # Classify all items from a source
    surface_ids: list[str] | None = None  # Surfaces to evaluate against
    limit: int = 100  # Max items to process


@app.post("/classify")
def classify_items(request: ClassifyRequest):
    """
    Run the sorting engine: classify items and evaluate eligibility.

    C1-C5: Classifies items, evaluates against surface policies,
    writes classification + eligibility to items collection,
    and promotes accepted items to goldItems collection.
    """
    from app.firestore_client import get_firestore_client
    from app.sorting.policy import classify_and_decide

    db = get_firestore_client()
    results = {"processed": 0, "accepted": 0, "rejected": 0, "uncertain": 0, "errors": 0}

    # Build query
    if request.item_id:
        doc = db.collection("items").document(request.item_id).get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail=f"Item {request.item_id} not found")
        items_to_process = [(doc.id, doc.to_dict())]
    elif request.source_id:
        query = db.collection("items").where("sourceId", "==", request.source_id).limit(request.limit)
        items_to_process = [(doc.id, doc.to_dict()) for doc in query.stream()]
    else:
        query = db.collection("items").where("isActive", "==", True).limit(request.limit)
        items_to_process = [(doc.id, doc.to_dict()) for doc in query.stream()]

    for item_id, item_data in items_to_process:
        try:
            result = classify_and_decide(
                item_id=item_id,
                item_data=item_data,
                surface_ids=request.surface_ids,
            )

            # Write classification back to item
            cls = result["classification"]
            update_data: dict = {
                "classification": cls,
                "eligibility": result["decisions"],
            }
            # Promote subCategory and roomTypes to top-level fields for
            # fast Firestore queries and deck filtering
            if cls.get("subCategory"):
                update_data["subCategory"] = cls["subCategory"]
            if cls.get("roomTypes"):
                update_data["roomTypes"] = cls["roomTypes"]
            db.collection("items").document(item_id).update(update_data)

            # Write Gold doc if item was accepted
            if result["goldDoc"]:
                db.collection("goldItems").document(item_id).set(result["goldDoc"], merge=True)
                results["accepted"] += 1
            else:
                # Check if any decision is UNCERTAIN
                has_uncertain = any(
                    d["decision"] == "UNCERTAIN"
                    for d in result["decisions"].values()
                )
                if has_uncertain:
                    results["uncertain"] += 1
                    # Write to review queue
                    db.collection("reviewQueue").document(item_id).set({
                        "itemId": item_id,
                        "classification": result["classification"],
                        "decisions": result["decisions"],
                        "status": "pending",
                        "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                    }, merge=True)
                else:
                    results["rejected"] += 1

            results["processed"] += 1
        except Exception as e:
            results["errors"] += 1
            print(f"[classify] Error processing {item_id}: {e}", flush=True)

    return results


@app.get("/classification-stats")
def classification_stats(source_id: Optional[str] = None):
    """
    Return classification statistics: category distribution, decision breakdown.
    """
    from app.firestore_client import get_firestore_client

    db = get_firestore_client()
    query = db.collection("items").where("isActive", "==", True)
    if source_id:
        query = query.where("sourceId", "==", source_id)

    stats = {
        "total": 0,
        "classified": 0,
        "unclassified": 0,
        "by_category": {},
        "by_decision": {"ACCEPT": 0, "REJECT": 0, "UNCERTAIN": 0, "unprocessed": 0},
        "by_source": {},
    }

    for doc in query.stream():
        data = doc.to_dict() or {}
        stats["total"] += 1
        sid = data.get("sourceId", "unknown")

        if sid not in stats["by_source"]:
            stats["by_source"][sid] = {"total": 0, "classified": 0, "accepted": 0}
        stats["by_source"][sid]["total"] += 1

        classification = data.get("classification")
        if classification:
            stats["classified"] += 1
            stats["by_source"][sid]["classified"] += 1
            cat = classification.get("predictedCategory", "unknown")
            stats["by_category"][cat] = stats["by_category"].get(cat, 0) + 1
        else:
            stats["unclassified"] += 1

        eligibility = data.get("eligibility")
        if eligibility:
            # Use first surface's decision
            first_dec = next(iter(eligibility.values()), {})
            dec = first_dec.get("decision", "unprocessed")
            stats["by_decision"][dec] = stats["by_decision"].get(dec, 0) + 1
            if dec == "ACCEPT":
                stats["by_source"][sid]["accepted"] += 1
        else:
            stats["by_decision"]["unprocessed"] += 1

    return stats


# ============================================================================
# EPIC D: REVIEW QUEUE ENDPOINTS
# ============================================================================

class ReviewActionRequest(BaseModel):
    """D2: Reviewer action on a review queue item."""
    item_id: str
    action: str  # "accept", "reject", "reclassify"
    correct_category: str | None = None  # If reclassifying
    reason: str | None = None
    reviewer_id: str = "admin"


@app.get("/review-queue")
def get_review_queue(status: str = "pending", limit: int = 50):
    """D1: Get items in the review queue."""
    from app.firestore_client import get_firestore_client

    db = get_firestore_client()
    query = (
        db.collection("reviewQueue")
        .where("status", "==", status)
        .limit(limit)
    )

    items = []
    for doc in query.stream():
        data = doc.to_dict() or {}
        data["id"] = doc.id
        # Fetch the full item for context
        item_doc = db.collection("items").document(doc.id).get()
        if item_doc.exists:
            item_data = item_doc.to_dict() or {}
            data["item"] = {
                "title": item_data.get("title"),
                "brand": item_data.get("brand"),
                "images": item_data.get("images", [])[:2],
                "priceAmount": item_data.get("priceAmount"),
                "canonicalUrl": item_data.get("canonicalUrl"),
                "breadcrumbs": item_data.get("breadcrumbs", []),
                "productType": item_data.get("productType"),
                "sourceId": item_data.get("sourceId"),
            }
        items.append(data)

    return {"items": items, "count": len(items)}


@app.post("/review-action")
def review_action(request: ReviewActionRequest):
    """D2: Process a reviewer's action on a review queue item."""
    from app.firestore_client import get_firestore_client
    from app.sorting.policy import SURFACE_POLICIES, evaluate_eligibility, promote_to_gold
    from app.sorting.classifier import ClassificationResult

    db = get_firestore_client()

    # Get the review queue item
    review_doc = db.collection("reviewQueue").document(request.item_id).get()
    if not review_doc.exists:
        raise HTTPException(status_code=404, detail="Review item not found")

    review_data = review_doc.to_dict() or {}
    item_doc = db.collection("items").document(request.item_id).get()
    if not item_doc.exists:
        raise HTTPException(status_code=404, detail="Item not found")

    item_data = item_doc.to_dict() or {}

    if request.action == "accept":
        # Force-accept: write to Gold collection
        classification = review_data.get("classification", {})
        gold_doc = {
            "itemId": request.item_id,
            "eligibleSurfaces": list(SURFACE_POLICIES.keys()),
            "predictedCategory": classification.get("predictedCategory", "unknown"),
            "categoryConfidence": 1.0,  # Human-verified
            "classificationVersion": classification.get("classificationVersion", 1),
            "policyVersion": 1,
            "humanVerified": True,
            "reviewerId": request.reviewer_id,
            "reviewReason": request.reason,
            "promotedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "title": item_data.get("title"),
            "brand": item_data.get("brand"),
            "priceAmount": item_data.get("priceAmount"),
            "priceCurrency": item_data.get("priceCurrency"),
            "images": item_data.get("images"),
            "canonicalUrl": item_data.get("canonicalUrl"),
            "sourceId": item_data.get("sourceId"),
            "outboundUrl": item_data.get("outboundUrl"),
            "material": item_data.get("material"),
            "colorFamily": item_data.get("colorFamily"),
            "sizeClass": item_data.get("sizeClass"),
            "styleTags": item_data.get("styleTags", []),
            "productType": item_data.get("productType"),
            "isActive": True,
        }
        db.collection("goldItems").document(request.item_id).set(gold_doc, merge=True)

    elif request.action == "reject":
        # Mark as rejected; remove from Gold if present
        db.collection("goldItems").document(request.item_id).delete()

    elif request.action == "reclassify" and request.correct_category:
        # Update classification with human-corrected category
        db.collection("items").document(request.item_id).update({
            "classification.predictedCategory": request.correct_category,
            "classification.humanCorrected": True,
            "classification.correctedBy": request.reviewer_id,
        })

    # Update review queue status
    db.collection("reviewQueue").document(request.item_id).update({
        "status": "reviewed",
        "reviewedBy": request.reviewer_id,
        "reviewAction": request.action,
        "reviewReason": request.reason,
        "correctCategory": request.correct_category,
        "reviewedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    })

    # D2: Store reviewer label for training data
    db.collection("reviewerLabels").document().set({
        "itemId": request.item_id,
        "action": request.action,
        "correctCategory": request.correct_category,
        "reason": request.reason,
        "reviewerId": request.reviewer_id,
        "originalClassification": review_data.get("classification"),
        "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    })

    return {"status": "ok", "action": request.action, "itemId": request.item_id}


# ============================================================================
# EPIC D: ACTIVE SAMPLING + EVALUATION
# ============================================================================

@app.get("/sampling-candidates")
def sampling_candidates(limit: int = 20, strategy: str = "diverse"):
    """
    D3: Get items for active labeling.

    Strategies:
    - diverse: Sample across categories and confidence levels
    - uncertain: Sample items near decision boundaries
    - random: Pure random sample
    """
    from app.firestore_client import get_firestore_client
    import random

    db = get_firestore_client()
    items_query = db.collection("items").where("isActive", "==", True).limit(500)
    all_items = [(doc.id, doc.to_dict() or {}) for doc in items_query.stream()]

    if strategy == "uncertain":
        # Sort by confidence ascending (most uncertain first)
        scored = []
        for item_id, data in all_items:
            cls = data.get("classification", {})
            conf = cls.get("top1Confidence", 0.5)
            scored.append((item_id, data, abs(conf - 0.5)))  # Distance from 0.5 = uncertainty
        scored.sort(key=lambda x: x[2])
        candidates = [(i, d) for i, d, _ in scored[:limit]]
    elif strategy == "diverse":
        # Sample from each category
        by_cat: dict[str, list] = {}
        for item_id, data in all_items:
            cls = data.get("classification", {})
            cat = cls.get("predictedCategory", "unclassified")
            by_cat.setdefault(cat, []).append((item_id, data))
        candidates = []
        per_cat = max(1, limit // max(1, len(by_cat)))
        for cat, items in by_cat.items():
            sample = random.sample(items, min(per_cat, len(items)))
            candidates.extend(sample)
        candidates = candidates[:limit]
    else:
        candidates = random.sample(all_items, min(limit, len(all_items)))

    return {
        "items": [
            {
                "id": item_id,
                "title": data.get("title"),
                "brand": data.get("brand"),
                "images": (data.get("images") or [])[:1],
                "priceAmount": data.get("priceAmount"),
                "canonicalUrl": data.get("canonicalUrl"),
                "classification": data.get("classification"),
                "sourceId": data.get("sourceId"),
                "breadcrumbs": data.get("breadcrumbs"),
            }
            for item_id, data in candidates
        ],
        "count": len(candidates),
        "strategy": strategy,
    }


@app.post("/calibrate")
def calibrate():
    """D4: Run weekly calibration – adjusts classification thresholds based on reviewer labels."""
    from app.firestore_client import get_firestore_client
    from app.sorting.calibration import run_calibration

    db = get_firestore_client()
    result = run_calibration(db)

    # Store calibration result for history
    db.collection("calibrationRuns").document().set({
        "totalLabels": result.total_labels,
        "accuracyBefore": result.accuracy_before,
        "accuracyAfter": result.accuracy_after,
        "thresholdAdjustments": result.threshold_adjustments,
        "recommendedAcceptThreshold": result.recommended_accept_threshold,
        "recommendedRejectThreshold": result.recommended_reject_threshold,
        "calibratedAt": result.calibrated_at,
    })

    return {
        "totalLabels": result.total_labels,
        "accuracyBefore": result.accuracy_before,
        "accuracyAfter": result.accuracy_after,
        "thresholdAdjustments": result.threshold_adjustments,
        "recommended": {
            "acceptThreshold": result.recommended_accept_threshold,
            "rejectThreshold": result.recommended_reject_threshold,
        },
    }


@app.get("/evaluation-report")
def evaluation_report():
    """
    D5: Generate a precision/recall evaluation report.

    Uses reviewer labels as ground truth to measure classification quality.
    """
    from app.firestore_client import get_firestore_client

    db = get_firestore_client()

    # Get all reviewer labels
    labels = list(db.collection("reviewerLabels").stream())
    if not labels:
        return {"message": "No reviewer labels found. Label items first via /review-action."}

    total_labels = len(labels)
    correct = 0
    by_category: dict[str, dict] = {}

    for label_doc in labels:
        label = label_doc.to_dict() or {}
        original = label.get("originalClassification", {})
        predicted = original.get("predictedCategory", "unknown")
        action = label.get("action")
        correct_cat = label.get("correctCategory")

        actual = correct_cat if correct_cat else (predicted if action == "accept" else "rejected")

        if actual not in by_category:
            by_category[actual] = {"tp": 0, "fp": 0, "fn": 0}
        if predicted not in by_category:
            by_category[predicted] = {"tp": 0, "fp": 0, "fn": 0}

        if action == "accept" and not correct_cat:
            by_category[predicted]["tp"] += 1
            correct += 1
        elif action == "reject":
            by_category[predicted]["fp"] += 1
        elif correct_cat and correct_cat != predicted:
            by_category[predicted]["fp"] += 1
            by_category[correct_cat]["fn"] += 1
        elif correct_cat and correct_cat == predicted:
            by_category[predicted]["tp"] += 1
            correct += 1

    # Compute per-category precision/recall
    per_cat_metrics = {}
    for cat, counts in by_category.items():
        tp = counts["tp"]
        fp = counts["fp"]
        fn = counts["fn"]
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
        per_cat_metrics[cat] = {
            "precision": round(precision, 3),
            "recall": round(recall, 3),
            "f1": round(f1, 3),
            "tp": tp, "fp": fp, "fn": fn,
        }

    return {
        "total_labels": total_labels,
        "overall_accuracy": round(correct / total_labels, 3) if total_labels > 0 else 0.0,
        "by_category": per_cat_metrics,
    }


# ============================================================================
# EPIC F: DEVOPS + OBSERVABILITY ENDPOINTS
# ============================================================================

@app.post("/retention-cleanup")
def retention_cleanup(
    raw_html_ttl_days: int = 14,
    snapshot_ttl_days: int = 30,
    failure_ttl_days: int = 7,
):
    """F1: Run data retention cleanup – purge old records based on TTL."""
    from app.firestore_client import get_firestore_client

    db = get_firestore_client()
    now = datetime.now(timezone.utc)
    deleted = {"productSnapshots": 0, "extractionFailures": 0}

    # Purge old snapshots
    cutoff_snapshots = (now - timedelta(days=snapshot_ttl_days)).isoformat().replace("+00:00", "Z")
    snap_query = db.collection("productSnapshots").where("extractedAt", "<", cutoff_snapshots).limit(500)
    for doc in snap_query.stream():
        db.collection("productSnapshots").document(doc.id).delete()
        deleted["productSnapshots"] += 1

    # Purge old extraction failures
    cutoff_failures = (now - timedelta(days=failure_ttl_days)).isoformat().replace("+00:00", "Z")
    fail_query = db.collection("extractionFailures").where("createdAt", "<", cutoff_failures).limit(500)
    for doc in fail_query.stream():
        db.collection("extractionFailures").document(doc.id).delete()
        deleted["extractionFailures"] += 1

    return {"deleted": deleted, "ttls": {
        "raw_html_ttl_days": raw_html_ttl_days,
        "snapshot_ttl_days": snapshot_ttl_days,
        "failure_ttl_days": failure_ttl_days,
    }}


@app.get("/domain-dashboard")
def domain_dashboard(source_id: Optional[str] = None):
    """F2: Domain-level quality dashboard data."""
    from app.firestore_client import get_firestore_client

    db = get_firestore_client()

    # Get recent metrics
    query = db.collection("metricsDaily").order_by("date", direction="DESCENDING").limit(100)
    if source_id:
        query = db.collection("metricsDaily").where("sourceId", "==", source_id).order_by("date", direction="DESCENDING").limit(30)

    dashboard: dict[str, dict] = {}
    for doc in query.stream():
        data = doc.to_dict() or {}
        sid = data.get("sourceId", "unknown")
        if sid not in dashboard:
            dashboard[sid] = {
                "sourceId": sid,
                "latestMetrics": data,
                "history": [],
            }
        dashboard[sid]["history"].append({
            "date": data.get("date"),
            "successRate": data.get("successRate"),
            "avgCompleteness": data.get("avgCompleteness"),
            "itemCount": data.get("itemCount"),
        })

    # Add classification stats per source
    for sid in dashboard:
        try:
            items_query = db.collection("items").where("sourceId", "==", sid).where("isActive", "==", True).limit(200)
            classified = 0
            accepted = 0
            total = 0
            for item_doc in items_query.stream():
                total += 1
                item_data = item_doc.to_dict() or {}
                if item_data.get("classification"):
                    classified += 1
                eligibility = item_data.get("eligibility", {})
                for surface_dec in eligibility.values():
                    if isinstance(surface_dec, dict) and surface_dec.get("decision") == "ACCEPT":
                        accepted += 1
                        break
            dashboard[sid]["classificationStats"] = {
                "total": total,
                "classified": classified,
                "accepted": accepted,
            }
        except Exception:
            pass

    return {"sources": list(dashboard.values())}


@app.post("/drift-check")
def drift_check(source_id: Optional[str] = None):
    """
    F3: Run drift detection and optionally auto-disable sources.

    Checks if recent run metrics have degraded compared to baseline.
    If drift is detected and source has autoDisableOnDrift=true, disables the source.
    """
    from app.firestore_client import get_firestore_client
    from app.monitor.drift import check_drift

    db = get_firestore_client()
    results = []

    # Get sources to check
    sources_query = db.collection("sources")
    if source_id:
        sources_query = sources_query.where("__name__", "==", source_id)

    for src_doc in sources_query.stream():
        src_data = src_doc.to_dict() or {}
        sid = src_doc.id

        # Get recent metrics (last 2 runs vs. last 7 days baseline)
        metrics = list(
            db.collection("metricsDaily")
            .where("sourceId", "==", sid)
            .order_by("date", direction="DESCENDING")
            .limit(10)
            .stream()
        )

        if len(metrics) < 2:
            results.append({"sourceId": sid, "status": "insufficient_data"})
            continue

        recent = metrics[0].to_dict() or {}
        baseline_metrics = [m.to_dict() for m in metrics[1:8]]

        baseline_sr = sum(m.get("successRate", 0) for m in baseline_metrics) / len(baseline_metrics) if baseline_metrics else None
        baseline_ac = sum(m.get("avgCompleteness", 0) for m in baseline_metrics) / len(baseline_metrics) if baseline_metrics else None

        drift_result = check_drift(
            current_success_rate=recent.get("successRate", 1.0),
            current_avg_completeness=recent.get("avgCompleteness", 1.0),
            baseline_success_rate=baseline_sr,
            baseline_avg_completeness=baseline_ac,
        )

        result = {
            "sourceId": sid,
            "driftDetected": drift_result.triggered,
            "reasons": drift_result.reasons,
            "currentSuccessRate": recent.get("successRate"),
            "baselineSuccessRate": baseline_sr,
        }

        # F4: Auto-disable on drift if configured
        if drift_result.triggered and src_data.get("autoDisableOnDrift", False):
            db.collection("sources").document(sid).update({
                "isEnabled": False,
                "disabledReason": f"Auto-disabled: drift detected ({', '.join(drift_result.reasons)})",
                "disabledAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            })
            result["autoDisabled"] = True

        results.append(result)

    return {"results": results}


class KillSwitchRequest(BaseModel):
    """Request body for /kill-switch endpoint."""
    source_id: str
    action: str = "disable"


@app.post("/kill-switch")
def kill_switch(request: KillSwitchRequest):
    """F4: Domain kill-switch – immediately enable/disable a source."""
    from app.firestore_client import get_firestore_client

    db = get_firestore_client()
    src_ref = db.collection("sources").document(request.source_id)
    doc = src_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail=f"Source {request.source_id} not found")

    if request.action == "disable":
        src_ref.update({
            "isEnabled": False,
            "disabledReason": "Manual kill-switch",
            "disabledAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        })
        return {"status": "disabled", "sourceId": request.source_id}
    elif request.action == "enable":
        src_ref.update({
            "isEnabled": True,
            "disabledReason": None,
            "disabledAt": None,
        })
        return {"status": "enabled", "sourceId": request.source_id}
    else:
        raise HTTPException(status_code=400, detail=f"Invalid action: {request.action}. Use 'enable' or 'disable'.")


@app.get("/cost-telemetry")
def cost_telemetry(source_id: Optional[str] = None, days: int = 7):
    """F5: Cost telemetry – fetch volume, storage growth, duration stats."""
    from app.firestore_client import get_firestore_client

    db = get_firestore_client()

    # Aggregate from ingestionRuns
    query = db.collection("ingestionRuns").order_by("startedAt", direction="DESCENDING").limit(100)
    if source_id:
        query = db.collection("ingestionRuns").where("sourceId", "==", source_id).order_by("startedAt", direction="DESCENDING").limit(50)

    telemetry: dict[str, dict] = {}
    total_fetched = 0
    total_duration_s = 0.0
    total_items_written = 0

    for doc in query.stream():
        data = doc.to_dict() or {}
        sid = data.get("sourceId", "unknown")
        stats = data.get("stats", {})

        if sid not in telemetry:
            telemetry[sid] = {
                "sourceId": sid,
                "totalRuns": 0,
                "totalFetched": 0,
                "totalItemsWritten": 0,
                "totalDurationSec": 0.0,
                "avgDurationSec": 0.0,
                "avgFetchPerRun": 0.0,
                "lastRunStatus": data.get("status"),
            }

        telemetry[sid]["totalRuns"] += 1
        fetched = stats.get("fetched", 0) or stats.get("candidateUrls", 0)
        telemetry[sid]["totalFetched"] += fetched
        total_fetched += fetched
        written = stats.get("success", 0) or stats.get("upserted", 0)
        telemetry[sid]["totalItemsWritten"] += written
        total_items_written += written
        duration = stats.get("extractionDurationSec", 0) or stats.get("durationSec", 0)
        telemetry[sid]["totalDurationSec"] += duration
        total_duration_s += duration

    # Compute averages
    for sid, t in telemetry.items():
        if t["totalRuns"] > 0:
            t["avgDurationSec"] = round(t["totalDurationSec"] / t["totalRuns"], 1)
            t["avgFetchPerRun"] = round(t["totalFetched"] / t["totalRuns"], 1)

    # Count items and Gold items for storage estimate
    item_count = 0
    gold_count = 0
    try:
        for _ in db.collection("items").where("isActive", "==", True).limit(10000).stream():
            item_count += 1
        for _ in db.collection("goldItems").where("isActive", "==", True).limit(10000).stream():
            gold_count += 1
    except Exception:
        pass

    return {
        "summary": {
            "totalFetchRequests": total_fetched,
            "totalItemsWritten": total_items_written,
            "totalProcessingTimeSec": round(total_duration_s, 1),
            "activeItems": item_count,
            "goldItems": gold_count,
            "estimatedStorageMB": round((item_count * 2 + gold_count * 1.5) / 1000, 1),  # Rough estimate
        },
        "bySource": list(telemetry.values()),
    }
