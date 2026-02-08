from app.locator.classifier import classify_url
from app.locator.sitemap import _parse_sitemap_xml


def test_classify_url_product_vs_category():
    # /produkt/ is a strong product hint
    assert classify_url("https://example.se/produkt/soffa-123").url_type_hint == "product"
    
    # /soffor/ without any product signal (no article number, no /p/) is a category
    assert classify_url("https://example.se/soffor/soffa-123").url_type_hint == "category"
    
    # Category with pagination is definitely a category
    assert classify_url("https://example.se/kategori/soffor?page=2").url_type_hint in ("category", "unknown")
    
    # /p-b pattern (ILVA bundle) is a product even with /soffor/ in breadcrumb
    assert classify_url("https://ilva.se/vardagsrum/soffor/product-name/p-b0003274-5637177585/").url_type_hint == "product"
    
    # Article number at end of path (Jotex pattern) is a product
    assert classify_url("https://www.jotex.se/kelso-soffa-2-sits-manchester/1737345-02").url_type_hint == "product"
    
    # Article number even with category breadcrumb prefix
    assert classify_url("https://www.jotex.se/mobler/soffor/kelso-soffa/1737345-02").url_type_hint == "product"
    
    # /p/ pattern (Mio) is a product
    assert classify_url("https://www.mio.se/p/bellora-4-sits-soffa/738150").url_type_hint == "product"


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

