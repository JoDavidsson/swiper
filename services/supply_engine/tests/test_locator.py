from app.locator.classifier import classify_url
from app.locator.sitemap import _parse_sitemap_xml


def test_classify_url_product_vs_category():
    assert classify_url("https://example.se/produkt/soffa-123").url_type_hint == "product"
    assert classify_url("https://example.se/soffor/soffa-123").confidence >= 0.6
    assert classify_url("https://example.se/kategori/soffor?page=2").url_type_hint in ("category", "unknown")


def test_parse_sitemap_urlset_and_index():
    urlset = """<?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url><loc>https://example.se/produkt/a</loc></url>
      <url><loc>https://example.se/produkt/b</loc></url>
    </urlset>
    """
    urls, nested = _parse_sitemap_xml(urlset)
    assert urls == ["https://example.se/produkt/a", "https://example.se/produkt/b"]
    assert nested == []

    index = """<?xml version="1.0" encoding="UTF-8"?>
    <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <sitemap><loc>https://example.se/sitemap_products.xml</loc></sitemap>
      <sitemap><loc>https://example.se/sitemap_categories.xml</loc></sitemap>
    </sitemapindex>
    """
    urls2, nested2 = _parse_sitemap_xml(index)
    assert urls2 == []
    assert "https://example.se/sitemap_products.xml" in nested2

