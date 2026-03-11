from app.extractor.cascade import extract_product_from_html


def test_embedded_json_heuristic_extracts_minimum_fields():
    html = """
    <html><head>
      <link rel="canonical" href="https://example.se/produkt/test-soffa" />
    </head>
    <body>
      <script id="__NEXT_DATA__" type="application/json">
        {
          "props": {
            "pageProps": {
              "product": {
                "name": "Testsoffa",
                "price": "12 995 kr",
                "priceCurrency": "SEK",
                "images": [{"url": "/img/a.jpg"}, {"url": "https://cdn.example.se/b.jpg"}]
              }
            }
          }
        }
      </script>
      <h1>Should not be used</h1>
    </body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/produkt/test-soffa?utm_source=x",
        final_url="https://example.se/produkt/test-soffa",
        html=html,
        extracted_at_iso="2026-02-02T00:00:00Z",
    )
    assert out is not None
    assert out.method in ("embedded_json", "jsonld", "dom")
    assert out.title == "Testsoffa"
    assert out.canonical_url == "https://example.se/produkt/test-soffa"
    assert out.price_amount == 12995
    assert out.price_currency == "SEK"
    assert len(out.images) >= 2
    assert all(u.startswith("http") for u in out.images)


def test_jsonld_title_entities_are_decoded():
    html = """
    <html><head>
      <link rel="canonical" href="https://example.se/produkt/are-2-sits-soffa" />
      <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Product",
        "name": "&#xC5;re 2-sits Soffa Beige 177cm",
        "url": "https://example.se/produkt/are-2-sits-soffa",
        "offers": {"price": "14995", "priceCurrency": "SEK"},
        "image": ["https://cdn.example.se/a.jpg"]
      }
      </script>
    </head><body><h1>fallback title</h1></body></html>
    """
    out = extract_product_from_html(
        source_id="retailer_x",
        fetched_url="https://example.se/produkt/are-2-sits-soffa",
        final_url="https://example.se/produkt/are-2-sits-soffa",
        html=html,
        extracted_at_iso="2026-02-13T00:00:00Z",
    )
    assert out is not None
    assert out.method == "jsonld"
    assert out.title == "Åre 2-sits Soffa Beige 177cm"
