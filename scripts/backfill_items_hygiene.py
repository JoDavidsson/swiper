#!/usr/bin/env python3
"""
One-time catalog hygiene backfill for `items`.

What it does:
1. Cleans `title` by decoding entities and normalizing whitespace.
2. Cleans `descriptionShort` by decoding entities, stripping tags, and normalizing whitespace.
3. Repairs invalid `priceAmount` values using fallback fields when possible.
4. Normalizes non-numeric but recoverable prices into numeric `priceAmount`.
5. Ensures `priceCurrency` defaults to `SEK` when price is valid but currency is missing.

Default mode is dry-run. Use `--apply` to write changes.

Examples:
  # Dry-run against emulator (default fallback)
  python scripts/backfill_items_hygiene.py

  # Apply fixes against emulator
  python scripts/backfill_items_hygiene.py --apply

  # Apply to one source only
  python scripts/backfill_items_hygiene.py --apply --source-id abc123
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from dataclasses import dataclass
from typing import Any


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SUPPLY_ENGINE_ROOT = os.path.join(REPO_ROOT, "services", "supply_engine")
if SUPPLY_ENGINE_ROOT not in sys.path:
    sys.path.insert(0, SUPPLY_ENGINE_ROOT)

from app.firestore_client import get_firestore_client
from app.normalization import clean_description_text, clean_title_text, normalize_price_amount


@dataclass(frozen=True)
class PriceResolution:
    value: float | None
    source: str | None


def _fallback_candidate_values(item: dict[str, Any]) -> list[tuple[str, Any]]:
    nested_price = item.get("price")
    nested_amount = None
    nested_raw = None
    if isinstance(nested_price, dict):
        nested_amount = nested_price.get("amount")
        nested_raw = nested_price.get("raw")

    return [
        ("priceAmount", item.get("priceAmount")),
        ("priceOriginal", item.get("priceOriginal")),
        ("price.amount", nested_amount),
        ("price.raw", nested_raw),
        ("priceRaw", item.get("priceRaw")),
        ("price", nested_price if not isinstance(nested_price, dict) else None),
    ]


def _resolve_price(item: dict[str, Any]) -> PriceResolution:
    for source, raw in _fallback_candidate_values(item):
        value = normalize_price_amount(raw)
        if value is not None:
            return PriceResolution(value=value, source=source)
    return PriceResolution(value=None, source=None)


def _should_update_description(old: Any, new: str | None) -> bool:
    if old is None and new is None:
        return False
    if isinstance(old, str):
        old_norm = old.strip()
    else:
        old_norm = old
    return old_norm != new


def _should_update_title(old: Any, new: str) -> bool:
    if isinstance(old, str):
        old_norm = old.strip()
    else:
        old_norm = old
    return old_norm != new


def _is_numeric(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _setup_env(project_id: str, emulator_host: str | None) -> None:
    # Default to local emulator if no explicit credentials are provided.
    if emulator_host:
        os.environ["FIRESTORE_EMULATOR_HOST"] = emulator_host
    elif (
        not os.environ.get("FIRESTORE_EMULATOR_HOST")
        and not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    ):
        os.environ["FIRESTORE_EMULATOR_HOST"] = "127.0.0.1:8180"

    if os.environ.get("FIRESTORE_EMULATOR_HOST"):
        os.environ.setdefault("GCLOUD_PROJECT", project_id)


def run_backfill(args: argparse.Namespace) -> dict[str, Any]:
    _setup_env(project_id=args.project_id, emulator_host=args.emulator_host)
    db = get_firestore_client()

    query = db.collection("items")
    if args.source_id:
        query = query.where("sourceId", "==", args.source_id)
    if args.limit and args.limit > 0:
        query = query.limit(args.limit)

    dry_run = not args.apply
    batch = db.batch()
    pending_writes = 0

    stats: dict[str, Any] = {
        "dry_run": dry_run,
        "source_id": args.source_id,
        "scanned": 0,
        "updated_docs": 0,
        "write_commits": 0,
        "title_cleaned": 0,
        "description_cleaned": 0,
        "price_repaired": 0,
        "price_normalized": 0,
        "currency_defaulted": 0,
        "unresolved_invalid_price": 0,
        "failed_updates": 0,
        "examples": [],
    }

    for doc in query.stream():
        stats["scanned"] += 1
        item = doc.to_dict() or {}
        update: dict[str, Any] = {}
        reasons: list[str] = []

        old_title = item.get("title")
        cleaned_title = clean_title_text(old_title) or "Untitled"
        if _should_update_title(old_title, cleaned_title):
            update["title"] = cleaned_title
            stats["title_cleaned"] += 1
            reasons.append("title")

        old_desc = item.get("descriptionShort")
        cleaned_desc = clean_description_text(old_desc)
        if _should_update_description(old_desc, cleaned_desc):
            update["descriptionShort"] = cleaned_desc
            stats["description_cleaned"] += 1
            reasons.append("description")

        current_price_raw = item.get("priceAmount")
        current_price_norm = normalize_price_amount(current_price_raw)
        resolution = _resolve_price(item)

        if resolution.value is not None:
            if current_price_norm is None:
                update["priceAmount"] = float(resolution.value)
                stats["price_repaired"] += 1
                reasons.append(f"price_repaired:{resolution.source}")
            else:
                price_changed = math.fabs(current_price_norm - resolution.value) > 1e-6
                if price_changed or not _is_numeric(current_price_raw):
                    update["priceAmount"] = float(resolution.value)
                    stats["price_normalized"] += 1
                    reasons.append(f"price_normalized:{resolution.source}")

            currency = item.get("priceCurrency")
            if not isinstance(currency, str) or not currency.strip():
                update["priceCurrency"] = "SEK"
                stats["currency_defaulted"] += 1
                reasons.append("currency_defaulted")
        else:
            if current_price_norm is None:
                stats["unresolved_invalid_price"] += 1
                if len(stats["examples"]) < args.examples:
                    stats["examples"].append(
                        {
                            "id": doc.id,
                            "sourceId": item.get("sourceId"),
                            "title": item.get("title"),
                            "issue": "unresolved_invalid_price",
                            "candidates": {
                                key: value for key, value in _fallback_candidate_values(item)
                            },
                        }
                    )

        if not update:
            continue

        if len(stats["examples"]) < args.examples:
            stats["examples"].append(
                {
                    "id": doc.id,
                    "sourceId": item.get("sourceId"),
                    "title": item.get("title"),
                    "reasons": reasons,
                    "update": update,
                }
            )

        stats["updated_docs"] += 1
        if dry_run:
            continue

        try:
            batch.update(doc.reference, update)
            pending_writes += 1
            if pending_writes >= args.batch_size:
                batch.commit()
                stats["write_commits"] += 1
                batch = db.batch()
                pending_writes = 0
        except Exception:
            stats["failed_updates"] += 1

    if not dry_run and pending_writes > 0:
        batch.commit()
        stats["write_commits"] += 1

    return stats


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="One-time data hygiene backfill for Firestore `items`."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply writes. If omitted, runs in dry-run mode.",
    )
    parser.add_argument(
        "--source-id",
        type=str,
        default=None,
        help="Optional source ID filter.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Optional limit of documents to scan (0 = no explicit limit).",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=200,
        help="Firestore batch commit size when --apply is used (max 500).",
    )
    parser.add_argument(
        "--examples",
        type=int,
        default=8,
        help="How many example updates/issues to include in output.",
    )
    parser.add_argument(
        "--project-id",
        type=str,
        default="swiper-95482",
        help="Project ID used when targeting emulator.",
    )
    parser.add_argument(
        "--emulator-host",
        type=str,
        default=None,
        help="Optional emulator host override, e.g. 127.0.0.1:8180.",
    )
    args = parser.parse_args()
    if args.batch_size <= 0 or args.batch_size > 500:
        parser.error("--batch-size must be between 1 and 500.")
    if args.examples < 0:
        parser.error("--examples must be >= 0.")
    return args


def main() -> int:
    args = parse_args()
    stats = run_backfill(args)
    print(json.dumps(stats, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
