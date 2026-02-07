"""Tests for P1: dimensions, material, color extraction in cascade."""
from app.extractor.cascade import extract_product_from_html


def test_jsonld_extracts_dimensions_material_color():
    html = """
    <html><head>
      <link rel="canonical" href="https://example.se/sofa-1" />
    </head>
    <body>
      <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Testsoffa",
          "url": "https://example.se/sofa-1",
          "image": "https://example.se/img.jpg",
          "offers": {"@type": "Offer", "price": 12995, "priceCurrency": "SEK"},
          "width": {"@type": "QuantitativeValue", "value": 220, "unitCode": "CMT"},
          "height": 85,
          "depth": 95,
          "color": "svart",
          "material": "fabric"
        }
      </script>
    </body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/sofa-1",
        final_url="https://example.se/sofa-1",
        html=html,
        extracted_at_iso="2026-02-02T00:00:00Z",
    )
    assert out is not None
    assert out.method == "jsonld"
    assert out.dimensions_raw == {"w": 220.0, "h": 85.0, "d": 95.0}
    assert out.material_raw == "fabric"
    assert out.color_raw == "svart"


def test_jsonld_additional_property_dimensions_color():
    html = """
    <html><head>
      <link rel="canonical" href="https://example.se/sofa-2" />
    </head>
    <body>
      <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Bolero soffa",
          "url": "https://example.se/sofa-2",
          "image": "https://example.se/img.jpg",
          "offers": {"@type": "Offer", "price": 14995, "priceCurrency": "SEK"},
          "additionalProperty": [
            {"name": "Bredd", "value": "210"},
            {"name": "Höjd", "value": 90},
            {"name": "Djup", "value": "95"},
            {"name": "Färg", "value": "Grå"},
            {"name": "Material", "value": "Velvet"}
          ]
        }
      </script>
    </body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/sofa-2",
        final_url="https://example.se/sofa-2",
        html=html,
        extracted_at_iso="2026-02-02T00:00:00Z",
    )
    assert out is not None
    assert out.method == "jsonld"
    assert out.dimensions_raw == {"w": 210.0, "h": 90.0, "d": 95.0}
    assert out.color_raw == "Grå"
    assert out.material_raw == "Velvet"


def test_embedded_json_extracts_dimensions_material_color():
    html = """
    <html><head>
      <link rel="canonical" href="https://example.se/sofa-3" />
    </head>
    <body>
      <script id="__NEXT_DATA__" type="application/json">
        {
          "props": {
            "pageProps": {
              "product": {
                "name": "Embedded Sofa",
                "price": "9 990 kr",
                "priceCurrency": "SEK",
                "images": ["/img/a.jpg"],
                "width": 200,
                "height": 80,
                "depth": 92,
                "material": "leather",
                "colorFamily": "brown"
              }
            }
          }
        }
      </script>
    </body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/sofa-3",
        final_url="https://example.se/sofa-3",
        html=html,
        extracted_at_iso="2026-02-02T00:00:00Z",
    )
    assert out is not None
    assert out.method == "embedded_json"
    assert out.dimensions_raw == {"w": 200.0, "h": 80.0, "d": 92.0}
    assert out.material_raw == "leather"
    assert out.color_raw == "brown"


def test_dom_fallback_infers_color_from_title():
    html = """
    <html><head>
      <meta property="og:type" content="product" />
      <meta property="og:image" content="https://example.se/img.jpg" />
      <meta property="product:price:amount" content="9990" />
    </head>
    <body>
      <h1>Bolero 3-sits soffa svart</h1>
    </body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/sofa-svart",
        final_url="https://example.se/sofa-svart",
        html=html,
        extracted_at_iso="2026-02-02T00:00:00Z",
    )
    assert out is not None
    assert out.method == "dom"
    assert out.color_raw == "black"
    assert out.dimensions_raw is None
    assert out.material_raw is None


def test_dom_fallback_extracts_description_dimensions_material_brand():
    html = """
    <html><head>
      <meta property="og:type" content="product" />
      <meta property="og:description" content="Elegant 3-seat sofa with oak legs." />
      <meta property="product:price:amount" content="14990" />
      <meta property="product:brand" content="Nordic Living" />
    </head>
    <body>
      <h1>Nordic 3-sits soffa beige</h1>
      <section class="product-specs">
        <table>
          <tr><th>Bredd</th><td>220 cm</td></tr>
          <tr><th>Höjd</th><td>88 cm</td></tr>
          <tr><th>Djup</th><td>95 cm</td></tr>
          <tr><th>Material</th><td>Velvet</td></tr>
        </table>
      </section>
    </body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/sofa-dom-1",
        final_url="https://example.se/sofa-dom-1",
        html=html,
        extracted_at_iso="2026-02-07T00:00:00Z",
    )
    assert out is not None
    assert out.method == "dom"
    assert out.description == "Elegant 3-seat sofa with oak legs."
    assert out.brand == "Nordic Living"
    assert out.dimensions_raw == {"w": 220.0, "h": 88.0, "d": 95.0}
    assert out.material_raw == "velvet"


def test_dimensions_promoted_from_enrichment_facets():
    html = """
    <html><head>
      <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Facet Sofa",
          "url": "https://example.se/facet-sofa",
          "image": "https://example.se/facet.jpg",
          "offers": {"@type": "Offer", "price": 9990, "priceCurrency": "SEK"}
        }
      </script>
    </head>
    <body>
      <ul class="product-info">
        <li>Bredd: 210 cm</li>
        <li>Höjd: 82 cm</li>
        <li>Djup: 93 cm</li>
      </ul>
    </body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/facet-sofa",
        final_url="https://example.se/facet-sofa",
        html=html,
        extracted_at_iso="2026-02-07T00:00:00Z",
    )
    assert out is not None
    assert out.method == "jsonld"
    assert out.dimensions_raw == {"w": 210.0, "h": 82.0, "d": 93.0}
