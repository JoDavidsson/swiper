"""Tests for URL classifier to ensure category vs product distinction."""

import pytest
from app.locator.classifier import classify_url, UrlClassification


class TestCategoryDetection:
    """Test that category/listing URLs are correctly identified."""

    def test_soffor_is_category(self):
        """Swedish plural /soffor should be a category listing."""
        result = classify_url("https://www.mio.se/soffor")
        assert result.url_type_hint == "category"
        assert result.confidence < 0.3

    def test_soffor_subpath_is_category(self):
        """Category subpaths should also be categories."""
        result = classify_url("https://www.mio.se/soffor-och-fatoljer/soffor")
        assert result.url_type_hint == "category"
        assert result.confidence < 0.3

    def test_sits_soffor_is_category(self):
        """X-sits soffor (X-seat sofas) is a category."""
        result = classify_url("https://www.rum21.se/mobler/soffor/3-sits-soffor")
        assert result.url_type_hint == "category"
        assert result.confidence < 0.3

    def test_produkter_plural_is_category(self):
        """/produkter (plural) is a listing."""
        result = classify_url("https://example.com/produkter")
        assert result.url_type_hint == "category"

    def test_collections_is_category(self):
        """Shopify-style /collections is a listing."""
        result = classify_url("https://example.com/collections/sofas")
        assert result.url_type_hint == "category"

    def test_pagination_is_category(self):
        """Pages with pagination params are listings."""
        result = classify_url("https://example.com/soffor?page=2")
        assert result.url_type_hint == "category"

    def test_mobler_is_category(self):
        """/mobler (furniture) is a category."""
        result = classify_url("https://www.rum21.se/mobler")
        assert result.url_type_hint == "category"


class TestProductDetection:
    """Test that product URLs are correctly identified."""

    def test_p_slash_product_slug(self):
        """/p/product-name is a product."""
        result = classify_url("https://www.mio.se/p/rossi-3-sits-soffa-beige")
        assert result.url_type_hint == "product"
        assert result.confidence >= 0.65

    def test_produkt_slash_product_slug(self):
        """/produkt/product-name is a product."""
        result = classify_url("https://example.com/produkt/my-sofa-grey")
        assert result.url_type_hint == "product"
        assert result.confidence >= 0.65

    def test_product_id_pattern(self):
        """Product IDs like -p12345 indicate products."""
        result = classify_url("https://www.chilli.se/soffa-grey-p12345")
        assert result.url_type_hint == "product"
        assert result.confidence >= 0.65

    def test_product_id_with_variant(self):
        """Product IDs with variants -p12345-v1 indicate products."""
        result = classify_url("https://www.chilli.se/soffa-grey-p12345-v2")
        assert result.url_type_hint == "product"
        assert result.confidence >= 0.65

    def test_item_slug_is_product(self):
        """/item/slug is a product."""
        result = classify_url("https://example.com/item/my-product-123")
        assert result.url_type_hint == "product"


class TestNonProductDetection:
    """Test that utility pages are correctly excluded."""

    def test_varukorg_is_non_product(self):
        """Shopping cart is not a product."""
        result = classify_url("https://example.com/varukorg")
        assert result.url_type_hint == "category"  # Low confidence = category
        assert result.confidence < 0.3

    def test_kundservice_is_non_product(self):
        """Customer service is not a product."""
        result = classify_url("https://example.com/kundservice")
        assert result.confidence < 0.3

    def test_login_is_non_product(self):
        """Login page is not a product."""
        result = classify_url("https://example.com/login")
        assert result.confidence < 0.3

    def test_pdf_is_non_product(self):
        """PDF files are not products."""
        result = classify_url("https://example.com/catalog.pdf")
        assert result.url_type_hint == "non_product"
        assert result.confidence == 0.0

    def test_image_is_non_product(self):
        """Image files are not products."""
        result = classify_url("https://example.com/product-image.jpg")
        assert result.url_type_hint == "non_product"
        assert result.confidence == 0.0

    def test_homepage_is_non_product(self):
        """Homepage is not a product."""
        result = classify_url("https://example.com/")
        assert result.url_type_hint == "homepage"
        assert result.confidence == 0.0


class TestEdgeCases:
    """Test edge cases and ambiguous URLs."""

    def test_invalid_url(self):
        """Invalid URLs should return unknown."""
        result = classify_url("not-a-url")
        # Should not crash, returns low confidence
        assert result.confidence <= 0.5

    def test_empty_string(self):
        """Empty string should return unknown."""
        result = classify_url("")
        assert result.confidence <= 0.3

    def test_deep_product_path(self):
        """Deep paths without category markers lean towards product."""
        result = classify_url("https://example.com/se/living/sofas/item/grey-sofa-xl")
        # Has /item/ which is a product marker
        assert result.confidence >= 0.5

    def test_ambiguous_shallow_path(self):
        """Shallow paths without markers are ambiguous/category."""
        result = classify_url("https://example.com/sofas")
        # Shallow path, no clear product marker
        assert result.confidence < 0.5
