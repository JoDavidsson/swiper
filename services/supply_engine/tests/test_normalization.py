"""Tests for normalization (color, material, size, canonical URL, domain equivalence)."""
import pytest
from app.normalization import (
    normalize_material,
    normalize_color_family,
    normalize_size_class,
    normalize_new_used,
    canonical_url,
    size_class_from_width_cm,
    infer_color_from_title,
    infer_size_from_title,
    canonical_domain,
    domains_equivalent,
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


def test_normalize_size_class_from_title():
    """Size should be inferred from title when no width data is available."""
    assert normalize_size_class(None, title="Bertha Soffa 2-sits") == "small"
    assert normalize_size_class(None, title="3-sits Bäddsoffa Masin") == "medium"
    assert normalize_size_class(None, title="4-sits Hörnbäddsoffa Staffin") == "large"
    assert normalize_size_class(None, title="5-sits U-formad Modulsoffa") == "large"
    assert normalize_size_class(None, title="Schäslong Lilly Antracit") == "small"
    assert normalize_size_class(None, title="Unknown Soffa") == "medium"  # fallback


def test_infer_size_from_title():
    """Direct title inference tests."""
    assert infer_size_from_title("Bertha Soffa 2-sits") == "small"
    assert infer_size_from_title("3-sits Bäddsoffa Masin") == "medium"
    assert infer_size_from_title("4-sits Hörnbäddsoffa Staffin") == "large"
    assert infer_size_from_title("Cubo 5-sits U-formad Djup Modulsoffa") == "large"
    assert infer_size_from_title("Arken 6-sits U-formad Modulsoffa") == "large"
    assert infer_size_from_title("Schäslong Lilly Antracit") == "small"
    assert infer_size_from_title("Fåtölj Klassisk Röd") == "small"
    assert infer_size_from_title("U-Bäddsoffa Sagardelos Höger") == "large"
    assert infer_size_from_title("Hörnsoffa Comfy") == "large"
    assert infer_size_from_title("") is None
    assert infer_size_from_title(None) is None
    assert infer_size_from_title("Random Item No Size Info") is None


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


# =============================================================================
# DOMAIN EQUIVALENCE TESTS
# =============================================================================

def test_canonical_domain_strips_www():
    """canonical_domain should strip www. prefix for comparison."""
    assert canonical_domain("www.example.com") == "example.com"
    assert canonical_domain("example.com") == "example.com"
    assert canonical_domain("WWW.EXAMPLE.COM") == "example.com"
    assert canonical_domain("www.mio.se") == "mio.se"


def test_canonical_domain_preserves_other_subdomains():
    """Non-www subdomains should be preserved."""
    assert canonical_domain("sub.example.com") == "sub.example.com"
    assert canonical_domain("api.example.com") == "api.example.com"
    assert canonical_domain("www2.example.com") == "www2.example.com"


def test_canonical_domain_handles_edge_cases():
    """Handle empty strings and whitespace."""
    assert canonical_domain("") == ""
    assert canonical_domain("  www.example.com  ") == "example.com"


def test_domains_equivalent_www_and_apex():
    """www.x.com and x.com should be equivalent."""
    assert domains_equivalent("www.example.com", "example.com") is True
    assert domains_equivalent("example.com", "www.example.com") is True
    assert domains_equivalent("www.mio.se", "mio.se") is True
    assert domains_equivalent("mio.se", "www.mio.se") is True


def test_domains_equivalent_same_domain():
    """Identical domains should be equivalent."""
    assert domains_equivalent("example.com", "example.com") is True
    assert domains_equivalent("www.example.com", "www.example.com") is True


def test_domains_equivalent_different_domains():
    """Different domains should not be equivalent."""
    assert domains_equivalent("example.com", "other.com") is False
    assert domains_equivalent("www.example.com", "www.other.com") is False
    assert domains_equivalent("mio.se", "ikea.se") is False


def test_domains_equivalent_subdomains_not_equivalent():
    """Non-www subdomains should not be equivalent to apex."""
    assert domains_equivalent("sub.example.com", "example.com") is False
    assert domains_equivalent("api.example.com", "www.example.com") is False
    assert domains_equivalent("shop.mio.se", "mio.se") is False
