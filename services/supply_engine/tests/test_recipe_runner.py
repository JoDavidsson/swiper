from app.recipes.runner import run_recipe_on_html


def test_recipe_embedded_json_and_transform():
    recipe = {
        "recipeId": "r1",
        "version": 1,
        "strategies": [
            {
                "name": "embedded_next",
                "type": "embedded_json",
                "enabled": True,
                "sources": [{"kind": "scriptTag", "selector": "script#__NEXT_DATA__", "format": "json"}],
                "fieldMap": {
                    "title": ["$.props.pageProps.product.name"],
                    "canonicalUrl": ["$.props.pageProps.product.url"],
                    "images": ["$.props.pageProps.product.images[*].url"],
                    "price.raw": ["$.props.pageProps.product.price"],
                    "price.currency": ["$.props.pageProps.product.priceCurrency"],
                },
                "transforms": {
                    "price.amount": [{"from": "price.raw", "op": "parseMoneyNumber", "locale": "sv-SE"}],
                    "images": [{"op": "ensureAbsoluteUrls"}],
                },
            }
        ],
    }
    html = """
    <html><head></head><body>
      <script id="__NEXT_DATA__" type="application/json">
        {"props":{"pageProps":{"product":{
          "name":"Testsoffa",
          "url":"https://example.se/produkt/testsoffa",
          "images":[{"url":"/img/a.jpg"}],
          "price":"12 995 kr",
          "priceCurrency":"SEK"
        }}}}
      </script>
    </body></html>
    """
    rr = run_recipe_on_html(recipe=recipe, html=html, final_url="https://example.se/produkt/testsoffa")
    assert rr.ok is True
    assert rr.output["title"] == "Testsoffa"
    assert rr.output["canonicalUrl"] == "https://example.se/produkt/testsoffa"
    assert rr.output["price"]["amount"] == 12995
    assert rr.output["price"]["currency"] == "SEK"
    assert rr.output["images"][0].startswith("http")

