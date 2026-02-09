# Crawl Eval Analysis (2026-02-09T10:38:04Z)

## Run scope
- Input entries: 80 URL tokens
- Unique URLs tested: 65
- Pages per site target: 20

## Completion summary
- Unique-site pass rate: 14/65 (21.5%)
- Full-completion rate: 0/65 (0.0%)
- Page completion: 100/947 (10.6%)
- Image URL validity: 193/252 (76.6%)
- Primary-image coverage: 61/100 (61.0%)

## Discovery funnel baseline
- Discovered HTTPS URLs: 14,754
- Product-hint URLs: 1,625 (11.0% of discovered)
- Accepted pages: 100
- Accepted/discovered ratio: 0.68%
- Accepted/product-hint ratio: 6.15%

### Site-level funnel buckets
- `discovered = 0`: 16 sites
- `discovered > 0, productHint = 0`: 31 sites
- `productHint > 0, accepted = 0`: 7 sites
- `productHint > 0, accepted > 0`: 11 sites

## Top failure categories
- `parse-fail`: 39 sites
- `fetch-error`: 33 sites
- `broken-images`: 7 sites
- `fetch-blocked`: 5 sites
- `invalid-price`: 3 sites

## Fetch error breakdown (aggregate)
- `http-404`: 200
- `http-429`: 12
- `dns-failure`: 9
- `robots-blocked`: 5
- `HTTP 406`: 2
- `tls-certificate`: 2
- `http-403`: 1

## Parse-fail signature pattern
Most parse failures are pages that are not product detail pages from extractor perspective:
- `No product extracted (JSON-LD blocks: 0, og:type: website)`
- `No product extracted (JSON-LD blocks: 0, og:type: None)`
- `No product extracted (JSON-LD blocks: 1, og:type: website/article)`

This indicates candidate selection is often routing to non-product content, and in other cases product pages lack extraction signals currently required by cascade extractors.

## Image consistency findings
Sites with accepted pages but image issues:
- `https://www.chilli.se/` and `https://chilli.se/`: 0/10 valid image URLs
- `https://www.trademax.se/` and `https://trademax.se/`: 0/10 valid image URLs
- `https://www.furniturebox.se/`: 0/10 valid image URLs
- `https://soffkoncept.se/`: 1/3 valid image URLs, 0/20 working primary images
- `https://artilleriet.se/`: 23/30 valid image URLs, but primary-image gap remains

Sites with good image consistency among accepted pages include:
- `https://www.ikea.com/` (63/63 valid)
- `https://www.gad.se/` (34/34 valid)
- `https://www.svenskttenn.com/` (10/10 valid)
- `https://www.ellos.se/` + `https://ellos.se/` (19/19 valid)
- `https://www.homeroom.se/` (19/19 valid)

## Why not 100%
1. Network/access blockers on a non-trivial subset (DNS/TLS/403/429/robots/404).
2. Candidate routing mismatch: very high `discovered` with zero product hints on many sites.
3. Extractor mismatch on selected pages: parse fails dominate even when pages are reachable.
4. Price normalization rejection on a few domains (`invalid-price`), causing zero acceptance despite hints.
5. Image URL instability on several otherwise-accepted domains.

## Immediate prioritization
1. Domain-level fetch policy fixes (429/403/TLS/DNS handling, browser fallback, rate-limit profiles).
2. Candidate classification upgrade for product URL detection to reduce non-product page testing.
3. Extractor recipe expansion for recurring parse signatures (`og:type=website/article` with weak JSON-LD).
4. Image normalization/validation hardening for domains with `broken-images`.
5. Currency+price strictness retained (SEK-only), with explicit unknown/mismatch counters from ingestion pipeline.
