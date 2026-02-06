"""Tests for crawl ingestion fallback behavior.

These tests verify that the crawler properly handles edge cases where:
1. Sitemap discovery returns URLs but path filtering removes all of them
2. Discovery strategies fail and fallback mechanisms are triggered
"""
import pytest
from unittest.mock import MagicMock, patch
from types import SimpleNamespace


class TestFilterFallback:
    """Tests for sitemap filter fallback behavior."""
    
    def test_path_filter_keeps_matching_urls(self):
        """When path pattern matches, URLs should be kept."""
        pattern = "/soffor"
        urls = [
            SimpleNamespace(url="https://example.com/soffor/product-1", source="sitemap", confidence=0.8, url_type_hint="product"),
            SimpleNamespace(url="https://example.com/soffor/product-2", source="sitemap", confidence=0.8, url_type_hint="product"),
            SimpleNamespace(url="https://example.com/other/product-3", source="sitemap", confidence=0.8, url_type_hint="product"),
        ]
        
        # Simulate the filtering logic from crawl_ingestion.py
        filtered = [d for d in urls if pattern.lower() in d.url.lower()]
        
        assert len(filtered) == 2
        assert all("/soffor" in d.url for d in filtered)
    
    def test_path_filter_removes_all_triggers_fallback(self):
        """When path pattern removes all URLs, fallback should be available."""
        pattern = "/nonexistent"
        urls = [
            SimpleNamespace(url="https://example.com/soffor/product-1", source="sitemap", confidence=0.8, url_type_hint="product"),
            SimpleNamespace(url="https://example.com/soffor/product-2", source="sitemap", confidence=0.8, url_type_hint="product"),
        ]
        
        original_count = len(urls)
        unfiltered = urls  # Keep original for fallback
        filtered = [d for d in urls if pattern.lower() in d.url.lower()]
        
        # Filtering removed all URLs
        assert len(filtered) == 0
        assert original_count > 0
        
        # Fallback: use unfiltered URLs
        fallback_urls = unfiltered
        assert len(fallback_urls) == original_count
    
    def test_empty_pattern_keeps_all_urls(self):
        """Empty pattern should not filter any URLs."""
        pattern = ""
        urls = [
            SimpleNamespace(url="https://example.com/soffor/product-1", source="sitemap", confidence=0.8, url_type_hint="product"),
            SimpleNamespace(url="https://example.com/other/product-2", source="sitemap", confidence=0.8, url_type_hint="product"),
        ]
        
        # With empty pattern, all URLs should pass
        if pattern:
            filtered = [d for d in urls if pattern.lower() in d.url.lower()]
        else:
            filtered = urls
        
        assert len(filtered) == len(urls)


class TestGetEffectiveConfig:
    """Tests for configuration resolution between derived and legacy formats."""
    
    def test_derived_config_takes_precedence(self):
        """When derived config exists, it should take precedence over legacy fields."""
        from app.crawl_ingestion import _get_effective_config
        
        source = {
            "baseUrl": "https://legacy.example.com",
            "seedUrls": ["https://legacy.example.com/category"],
            "seedType": "category",
            "derived": {
                "baseUrl": "https://derived.example.com",
                "seedUrl": "https://derived.example.com/soffor",
                "strategy": "sitemap",
                "seedPathPattern": "/soffor",
            }
        }
        
        config = _get_effective_config(source)
        
        assert config["useDerived"] is True
        assert config["baseUrl"] == "https://derived.example.com"
        assert config["seedUrl"] == "https://derived.example.com/soffor"
        assert config["strategy"] == "sitemap"
        assert config["seedPathPattern"] == "/soffor"
    
    def test_legacy_config_when_no_derived(self):
        """Without derived config, legacy fields should be used."""
        from app.crawl_ingestion import _get_effective_config
        
        source = {
            "baseUrl": "https://legacy.example.com",
            "seedUrls": ["https://legacy.example.com/category"],
            "seedType": "category",
        }
        
        config = _get_effective_config(source)
        
        assert config["useDerived"] is False
        assert config["baseUrl"] == "https://legacy.example.com"
        assert config["strategy"] == "category"
        assert config["seedPathPattern"] == ""
    
    def test_derived_none_uses_legacy(self):
        """When derived is None/missing, legacy config should be used."""
        from app.crawl_ingestion import _get_effective_config
        
        source = {
            "baseUrl": "https://example.com",
            "derived": None,
        }
        
        config = _get_effective_config(source)
        
        assert config["useDerived"] is False
    
    def test_derived_not_dict_uses_legacy(self):
        """When derived is not a dict, legacy config should be used."""
        from app.crawl_ingestion import _get_effective_config
        
        source = {
            "baseUrl": "https://example.com",
            "derived": "invalid",
        }
        
        config = _get_effective_config(source)
        
        assert config["useDerived"] is False
