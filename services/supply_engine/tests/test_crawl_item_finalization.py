from __future__ import annotations

from app.crawl_ingestion import _dedupe_items_by_id, _finalize_item_for_write


def _base_item() -> dict:
    return {
        "sourceId": "source_a",
        "canonicalUrl": "https://example.com/product/sofa-1",
        "sourceUrl": "https://example.com/product/sofa-1?utm_source=test",
        "title": "Modular Scandinavian Sofa",
        "descriptionShort": "Compact modular sofa with FSC-certified wood and recycled fabric.",
        "productType": "sofa",
        "breadcrumbs": ["Furniture", "Sofas", "Scandinavian"],
        "facets": {"style": "modern"},
        "sizeClass": "small",
        "seatCount": 2,
        "shippingCost": 199,
        "styleTags": [],
        "ecoTags": [],
        "smallSpaceFriendly": False,
        "modular": False,
        "deliveryComplexity": "medium",
    }


def test_finalize_item_derives_recommendation_features_and_id() -> None:
    item = _base_item()
    _finalize_item_for_write(item)

    assert item["id"]
    assert item["modular"] is True
    assert item["smallSpaceFriendly"] is True
    assert item["deliveryComplexity"] == "low"
    assert "scandinavian" in item["styleTags"]
    assert "fsc" in item["ecoTags"]
    assert "recycled" in item["ecoTags"]


def test_finalize_item_id_stable_when_title_changes() -> None:
    item_a = _base_item()
    item_b = _base_item()
    item_b["title"] = "Renamed Sofa Title"

    _finalize_item_for_write(item_a)
    _finalize_item_for_write(item_b)

    assert item_a["id"] == item_b["id"]


def test_dedupe_items_by_id_keeps_single_record() -> None:
    item_a = _base_item()
    item_b = _base_item()
    item_b["descriptionShort"] = "Updated description"

    _finalize_item_for_write(item_a)
    _finalize_item_for_write(item_b)
    deduped, removed = _dedupe_items_by_id([item_a, item_b])

    assert removed == 1
    assert len(deduped) == 1
    assert deduped[0]["descriptionShort"] == "Updated description"
