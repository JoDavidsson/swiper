from app.recipes.promotion import evaluate_recipe_on_pages, passes_promotion_gate


def test_promotion_gate_passes_on_good_pages():
    recipe = {
        "recipeId": "r1",
        "version": 1,
        "strategies": [
            {
                "name": "dom",
                "type": "dom",
                "enabled": True,
                "fieldMap": {
                    "title": [{"selector": "h1", "attr": "text"}],
                    "canonicalUrl": [{"selector": "link[rel='canonical']", "attr": "href"}],
                    "images": [{"selector": "meta[property='og:image']", "attr": "content"}],
                    "price.raw": [{"selector": "meta[property='product:price:amount']", "attr": "content"}],
                    "price.currency": [{"selector": "meta[property='product:price:currency']", "attr": "content"}],
                },
                "transforms": {"price.amount": [{"from": "price.raw", "op": "parseMoneyNumber", "locale": "sv-SE"}]},
            }
        ],
    }
    pages = [
        {
            "finalUrl": "https://example.se/p/1",
            "html": "<html><head><link rel='canonical' href='https://example.se/p/1' />"
            "<meta property='og:image' content='https://example.se/a.jpg' />"
            "<meta property='product:price:amount' content='12 995 kr' />"
            "<meta property='product:price:currency' content='SEK' /></head>"
            "<body><h1>Test</h1></body></html>",
        },
        {
            "finalUrl": "https://example.se/p/2",
            "html": "<html><head><link rel='canonical' href='https://example.se/p/2' />"
            "<meta property='og:image' content='https://example.se/b.jpg' />"
            "<meta property='product:price:amount' content='9 990 kr' />"
            "<meta property='product:price:currency' content='SEK' /></head>"
            "<body><h1>Test 2</h1></body></html>",
        },
    ]
    ev = evaluate_recipe_on_pages(recipe=recipe, pages=pages)
    assert passes_promotion_gate(ev, min_success_rate=0.85, min_avg_completeness=0.6) is True


def test_promotion_gate_fails_on_hard_failure():
    recipe = {"recipeId": "r1", "version": 1, "strategies": [{"type": "dom", "enabled": True, "fieldMap": {}}]}
    ev = evaluate_recipe_on_pages(recipe=recipe, pages=[{"finalUrl": "https://x", "html": "<html></html>"}])
    assert passes_promotion_gate(ev) is False

