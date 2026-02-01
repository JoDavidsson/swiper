"""Firestore client for Supply Engine. Uses firebase_admin or emulator."""
import os
import uuid
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
    if status in ("succeeded", "failed"):
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


def write_items(db, items: list[dict], source_id: str) -> tuple[int, int]:
    """Batch write items to Firestore. Returns (upserted, failed)."""
    from firebase_admin import firestore as fs
    upserted = 0
    failed = 0
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
        except Exception:
            failed += 1
    return upserted, failed
