"""Tests for normalization (color, material, size, canonical URL)."""
import pytest
from app.normalization import (
    normalize_material,
    normalize_color_family,
    normalize_size_class,
    normalize_new_used,
    canonical_url,
    size_class_from_width_cm,
    infer_color_from_title,
)


def test_normalize_material():
    assert normalize_material("fabric") == "fabric"
    assert normalize_material("leather") == "leather"
    assert normalize_material("Velvet") == "velvet"
    assert normalize_material("") is None
    assert normalize_material(None) is None


def test_normalize_color_family():
    assert normalize_color_family("gray") == "gray"
    assert normalize_color_family("white") == "white"
    assert normalize_color_family("multi") == "multi"
    assert normalize_color_family(None) is None


def test_normalize_size_class():
    assert normalize_size_class(None) == "medium"
    assert normalize_size_class("small") == "small"
    assert normalize_size_class("large") == "large"
    assert normalize_size_class(None, 170) == "small"
    assert normalize_size_class(None, 200) == "medium"
    assert normalize_size_class(None, 250) == "large"


def test_normalize_new_used():
    assert normalize_new_used(None) == "new"
    assert normalize_new_used("used") == "used"
    assert normalize_new_used("begagnad") == "used"
    assert normalize_new_used("new") == "new"


def test_canonical_url():
    assert canonical_url("https://example.com/p?utm_source=x") == "https://example.com/p"
    assert "example.com" in canonical_url("https://Example.COM/path")
    assert canonical_url("https://a.com/p#frag").endswith("/p")


def test_infer_color_from_title():
    assert infer_color_from_title("Bolero 3-sits soffa svart") == "black"
    assert infer_color_from_title("Sofa Grå modern") == "gray"
    assert infer_color_from_title("Beige fabric sofa") == "beige"
    assert infer_color_from_title("STOCKHOLM 2025 3-seat sofa") is None
    assert infer_color_from_title("Red Edition Fifties Sofa 210") == "red"
    assert infer_color_from_title("") is None
    assert infer_color_from_title(None) is None
