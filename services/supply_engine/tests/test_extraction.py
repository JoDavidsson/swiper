"""Tests for JSON-LD and heuristic extraction."""
import os
import pytest
from app.extraction.default import extract_product_detail, extract_product_list


def test_extract_product_detail_jsonld():
    path = os.path.join(os.path.dirname(__file__), "..", "..", "..", "sample_data", "html_fixtures", "product_with_jsonld.html")
    if not os.path.isfile(path):
        pytest.skip("fixture not found")
    with open(path, encoding="utf-8") as f:
        html = f.read()
    out = extract_product_detail(html)
    assert out is not None
    assert out.get("title") == "Test Sofa"
    assert out.get("price") == 9990
    assert out.get("currency") == "SEK"
    assert "img" in (out.get("image_url") or "")
