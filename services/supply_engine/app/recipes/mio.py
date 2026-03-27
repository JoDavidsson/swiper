"""
Mio (Swedish furniture retailer) - Extraction Recipe

Mio uses clean JSON-LD Schema.org Product markup with:
- Product name, brand, description
- Price in offers.price (SEK)
- Width/height/depth in additionalProperty (Swedish labels: Bredd/Höjd/Djup)
- Material in additionalProperty ("Material")
- Color in additionalProperty ("Färg")
- Images as single URL or list of URLs
- Canonical URL in @id or url field

Note: The cascade extractor (app.extractor.cascade) handles additionalProperty
extraction automatically for Swedish labels. This recipe focuses on the JSON-LD
field mapping that the cascade uses directly.

Strategy: JSON-LD via cascade (which handles additionalProperty parsing),
DOM fallback for images via the cascade image extraction.
"""
from app.recipes.schema import validate_recipe_json

MIO_RECIPE = {
    "recipeId": "mio-se",
    "version": 1,
    "validators": [
        {"field": "title", "op": "required"},
        {"field": "canonicalUrl", "op": "required"},
    ],
    "strategies": [
        {
            "name": "mio-jsonld",
            "type": "jsonld",
            "enabled": True,
            "fieldMap": {
                # Core required fields
                "title": ["$.name"],
                "canonicalUrl": ["$.url", "$.@id"],
                # Images: single URL, list, or list of ImageObjects
                "images": ["$.image"],
                # Price (SEK)
                "price.raw": ["$.offers.price"],
                "price.currency": ["$.offers.priceCurrency"],
                # Brand
                "brand": ["$.brand.name", "$.brand"],
                # Description
                "description": ["$.description"],
                # Dimensions (direct fields, cascade handles additionalProperty too)
                "dimensions.w": ["$.width"],
                "dimensions.h": ["$.height"],
                "dimensions.d": ["$.depth"],
            },
            "transforms": {
                "price.amount": [
                    {"op": "parseMoneyNumber", "from": "price.raw"}
                ],
                "images": [
                    {"op": "ensureAbsoluteUrls"}
                ]
            }
        },
        # Fallback: DOM extraction for images if JSON-LD images fail
        {
            "name": "mio-dom-images",
            "type": "dom",
            "enabled": True,
            "fieldMap": {
                "images": [
                    {"selector": "meta[property='og:image']", "attr": "content"},
                    {"selector": "[itemprop='image']", "attr": "content"},
                    {"selector": "[itemprop='image']", "attr": "src"},
                    {"selector": ".product-image img", "attr": "src"},
                    {"selector": ".product-image img", "attr": "data-src"},
                ]
            },
            "transforms": {
                "images": [
                    {"op": "ensureAbsoluteUrls"}
                ]
            }
        }
    ]
}


def get_mio_recipe() -> dict:
    """Return the Mio extraction recipe."""
    validate_recipe_json(MIO_RECIPE)
    return MIO_RECIPE


if __name__ == "__main__":
    recipe = get_mio_recipe()
    print(f"Mio recipe: {recipe['recipeId']} v{recipe['version']}")
    print(f"Strategies: {[s['name'] for s in recipe['strategies']]}")
