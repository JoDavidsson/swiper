"""Firestore client for Supply Engine. Uses firebase_admin or emulator."""
import os
import uuid
import hashlib
from datetime import datetime, timezone
from typing import Any

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    firebase_admin = None
    firestore = None

_db = None


def get_firestore_client():
    global _db
    if _db is not None:
        return _db
    if firestore is None:
        raise RuntimeError("firebase-admin not installed")
    if not firebase_admin._apps:
        # If using the Firestore emulator, we must NOT require ADC/service-account creds.
        # firebase-admin still wants a credential object; AnonymousCredentials works for emulator.
        if os.environ.get("FIRESTORE_EMULATOR_HOST"):
            from google.auth.credentials import AnonymousCredentials

            project_id = os.environ.get("GCLOUD_PROJECT") or os.environ.get("FIREBASE_PROJECT_ID") or "swiper-95482"

            class _EmulatorCredential(credentials.Base):  # type: ignore[attr-defined]
                def get_credential(self):
                    return AnonymousCredentials()

            firebase_admin.initialize_app(_EmulatorCredential(), {"projectId": project_id})
        else:
            cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
            if cred_path and os.path.isfile(cred_path):
                cred = credentials.Certificate(cred_path)
            else:
                cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred)
    _db = firestore.client()
    return _db


def _server_timestamp():
    from firebase_admin import firestore as fs
    return fs.SERVER_TIMESTAMP


def create_run(db, source_id: str, status: str) -> str:
    col = db.collection("ingestionRuns")
    ref = col.document()
    ref.set({
        "sourceId": source_id,
        "startedAt": _server_timestamp(),
        "status": status,
        "stats": {},
    })
    return ref.id


def update_run(db, run_id: str, status: str, stats: dict, error_summary: str | None = None):
    data = {"status": status, "stats": stats, "updatedAt": _server_timestamp()}
    if status in ("succeeded", "failed", "stopped"):
        data["finishedAt"] = _server_timestamp()
    if error_summary is not None:
        data["errorSummary"] = error_summary
    db.collection("ingestionRuns").document(run_id).update(data)


def create_job(db, source_id: str, run_id: str, job_type: str, payload: dict, status: str) -> str:
    col = db.collection("ingestionJobs")
    ref = col.document()
    ref.set({
        "sourceId": source_id,
        "runId": run_id,
        "jobType": job_type,
        "payload": payload,
        "status": status,
        "attempts": 1,
        "createdAt": _server_timestamp(),
        "updatedAt": _server_timestamp(),
    })
    return ref.id


def update_job(db, job_id: str, status: str, error: str | None = None):
    data = {"status": status, "updatedAt": _server_timestamp()}
    if error is not None:
        data["error"] = error
    db.collection("ingestionJobs").document(job_id).update(data)


def write_items(db, items: list[dict], source_id: str) -> tuple[int, int, list[str]]:
    """Batch write items to Firestore. Returns (upserted, failed, item_ids)."""
    from firebase_admin import firestore as fs
    upserted = 0
    failed = 0
    item_ids: list[str] = []
    col = db.collection("items")
    for item in items:
        try:
            data = dict(item)
            for key in ("lastUpdatedAt", "firstSeenAt", "lastSeenAt"):
                if key in data and data[key] is None:
                    data[key] = _server_timestamp()
            item_id = data.pop("id", None) or str(uuid.uuid4()).replace("-", "")[:24]
            col.document(item_id).set(data, merge=True)
            upserted += 1
            item_ids.append(item_id)
        except Exception:
            failed += 1
            item_ids.append("")  # Placeholder to keep alignment with items list
    return upserted, failed, item_ids


# ----------------------------
# Crawl / extraction collections
# ----------------------------
#
# These collections are written by the Supply Engine (Admin SDK, bypassing rules).
# They are intentionally kept separate from the app-facing `items` collection.
#
# Collection names (FireStore top-level):
# - crawlUrls
# - productSnapshots
# - crawlRecipes
# - extractionFailures
# - metricsDaily
#


def _doc_id_for_url(url: str) -> str:
    """Stable, Firestore-friendly document ID derived from a URL."""
    return hashlib.sha256(url.encode("utf-8", errors="ignore")).hexdigest()[:24]


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def upsert_crawl_url(
    db,
    *,
    source_id: str,
    url: str,
    discovered_from: str,
    url_type: str = "unknown",
    confidence: float = 0.5,
    canonical_url: str | None = None,
    status: str = "active",
    extra: dict | None = None,
) -> str:
    """
    Upsert a discovered URL candidate.

    Document ID is stable per URL so repeated runs update `lastSeenAt`.
    """
    doc_id = _doc_id_for_url(url)
    data = {
        "sourceId": source_id,
        "url": url,
        "canonicalUrl": canonical_url,
        "urlType": url_type,  # product|category|unknown
        "discoveredFrom": discovered_from,  # sitemap|crawl|manual
        "confidence": float(confidence),
        "status": status,  # active|gone|blocked
        "firstSeenAt": _server_timestamp(),
        "lastSeenAt": _server_timestamp(),
        "updatedAt": _server_timestamp(),
    }
    if extra:
        data.update(extra)
    db.collection("crawlUrls").document(doc_id).set(data, merge=True)
    return doc_id


def record_extraction_failure(
    db,
    *,
    source_id: str,
    url: str,
    failure_type: str,
    error: str,
    html_hash: str | None = None,
    signals: dict | None = None,
) -> str:
    """
    Record an extraction failure for later diagnosis / healing.

    `signals` should be a small, privacy-safe packet (no full HTML by default).
    """
    ref = db.collection("extractionFailures").document()
    ref.set(
        {
            "sourceId": source_id,
            "url": url,
            "failureType": failure_type,  # fetch|parse|validate
            "error": error[:5000],
            "htmlHash": html_hash,
            "signals": signals,
            "createdAt": _server_timestamp(),
        }
    )
    return ref.id


def write_product_snapshot(
    db,
    *,
    source_id: str,
    canonical_url: str,
    snapshot: dict,
    extracted_at_iso: str | None = None,
    snapshot_hash: str | None = None,
) -> str:
    """
    Persist an extraction snapshot for history and regression testing.
    """
    extracted_at_iso = extracted_at_iso or _utc_now_iso()
    if snapshot_hash is None:
        try:
            import json

            snapshot_hash = hashlib.sha256(
                json.dumps(snapshot, sort_keys=True, ensure_ascii=False).encode("utf-8", errors="ignore")
            ).hexdigest()
        except Exception:
            snapshot_hash = hashlib.sha256(repr(snapshot).encode("utf-8", errors="ignore")).hexdigest()

    ref = db.collection("productSnapshots").document()
    ref.set(
        {
            "sourceId": source_id,
            "canonicalUrl": canonical_url,
            "snapshotJson": snapshot,
            "hash": snapshot_hash,
            "extractedAt": extracted_at_iso,  # ISO string for portability
            "createdAt": _server_timestamp(),  # server timestamp for queries
        }
    )
    return ref.id


def upsert_metrics_daily(db, *, source_id: str, date: str, metrics: dict) -> str:
    """
    Upsert daily metrics.

    `date` should be YYYY-MM-DD in UTC.
    Metrics map may include quality fields such as:
    descriptionRate, dimensionsRate, materialRate, avgCompleteness, browserFetchCount.
    """
    doc_id = f"{source_id}__{date}"
    data = {"sourceId": source_id, "date": date, **metrics, "updatedAt": _server_timestamp()}
    db.collection("metricsDaily").document(doc_id).set(data, merge=True)
    return doc_id


def save_recipe_version(
    db,
    *,
    source_id: str,
    recipe_id: str,
    version: int,
    recipe_json: dict,
    status: str = "draft",  # draft|active|deprecated
    promoted_at: str | None = None,
) -> str:
    doc_id = f"{source_id}__{recipe_id}__v{int(version)}"
    data = {
        "sourceId": source_id,
        "recipeId": recipe_id,
        "version": int(version),
        "recipeJson": recipe_json,
        "status": status,
        "createdAt": _server_timestamp(),
        "promotedAt": promoted_at,
    }
    db.collection("crawlRecipes").document(doc_id).set(data, merge=True)
    return doc_id


def get_active_recipe(db, *, source_id: str) -> dict | None:
    """
    Return the highest-version active recipe for this source, or None.
    """
    q = (
        db.collection("crawlRecipes")
        .where("sourceId", "==", source_id)
        .where("status", "==", "active")
        .order_by("version", direction=firestore.Query.DESCENDING)
        .limit(1)
    )
    snap = q.get()
    if not snap:
        return None
    return {"id": snap[0].id, **snap[0].to_dict()}


def get_known_hashes(db, *, source_id: str, urls: list[str]) -> dict[str, str]:
    """
    Look up previously stored html_hash values for a batch of URLs.

    Returns {url: html_hash} for URLs that have a stored snapshot.
    Used for incremental recrawl: if the hash hasn't changed, skip re-extraction.
    """
    if not urls:
        return {}

    # Use crawlUrls collection which stores htmlHash from previous runs
    known: dict[str, str] = {}
    for url in urls:
        doc_id = _doc_id_for_url(url)
        doc = db.collection("crawlUrls").document(doc_id).get()
        if doc.exists:
            data = doc.to_dict() or {}
            h = data.get("htmlHash")
            if h:
                known[url] = h
    return known


def update_crawl_url_hash(db, *, url: str, html_hash: str, source_id: str) -> None:
    """Store the html_hash for a crawl URL so future runs can skip unchanged pages."""
    doc_id = _doc_id_for_url(url)
    db.collection("crawlUrls").document(doc_id).set(
        {"htmlHash": html_hash, "lastCrawledAt": _server_timestamp(), "sourceId": source_id},
        merge=True,
    )


def deactivate_active_recipes(db, *, source_id: str) -> int:
    """
    Mark all active recipes for a source as deprecated.
    Returns number of updated documents.
    """
    q = db.collection("crawlRecipes").where("sourceId", "==", source_id).where("status", "==", "active")
    snap = q.get()
    count = 0
    for d in snap:
        db.collection("crawlRecipes").document(d.id).update({"status": "deprecated", "updatedAt": _server_timestamp()})
        count += 1
    return count


def set_recipe_status(db, *, recipe_doc_id: str, status: str, promoted_at: str | None = None) -> None:
    data: dict[str, Any] = {"status": status, "updatedAt": _server_timestamp()}
    if promoted_at is not None:
        data["promotedAt"] = promoted_at
    db.collection("crawlRecipes").document(recipe_doc_id).update(data)
