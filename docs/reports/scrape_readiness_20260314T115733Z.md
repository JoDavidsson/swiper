# Scrape Readiness Report

- Generated: `2026-03-14T12:13:43.416999Z`
- Sample size per host: `8` pages
- Classification rule: `scrape_first` if at least `75%` of sampled pages extracted with price, currency, and at least one image; otherwise `agent_review`.
- Hosts evaluated: `52`
- Scrape first: `21`
- Agent review: `31`

## Scrape First

| Host | Group | Accepted | Tested | Completion | Primary reason | Seed URL |
|---|---|---:|---:|---:|---|---|
| `chilli.se` | `core` | 8 | 8 | 100% | ok | `https://www.chilli.se/` |
| `ellos.se` | `core` | 8 | 8 | 100% | ok | `https://www.ellos.se/hem-inredning/mobler/soffor-fatoljer/soffor` |
| `furniturebox.se` | `core` | 8 | 8 | 100% | ok | `https://www.furniturebox.se/` |
| `homeroom.se` | `core` | 8 | 8 | 100% | ok | `https://www.homeroom.se/mobler/soffor-fatoljer/soffor` |
| `mio.se` | `core` | 8 | 8 | 100% | ok | `https://www.mio.se/kampanj/soffor` |
| `sleepo.se` | `core` | 8 | 8 | 100% | ok | `https://www.sleepo.se/mobler/soffor-fatoljer/` |
| `soffadirekt.se` | `core` | 8 | 8 | 100% | ok | `https://www.soffadirekt.se/` |
| `svenskahem.se` | `core` | 8 | 8 | 100% | ok | `https://www.svenskahem.se/produkter/soffor` |
| `svenssons.se` | `core` | 8 | 8 | 100% | ok | `https://www.svenssons.se/mobler/soffor/` |
| `sweef.se` | `core` | 8 | 8 | 100% | ok | `https://sweef.se/soffor` |
| `trademax.se` | `core` | 8 | 8 | 100% | ok | `https://www.trademax.se/` |
| `englesson.se` | `eval_only` | 6 | 8 | 75% | fetch-error:2 | `https://englesson.se` |
| `folkhemmet.com` | `eval_only` | 7 | 8 | 88% | parse-fail:1 | `https://folkhemmet.com` |
| `gad.se` | `eval_only` | 8 | 8 | 100% | ok | `https://gad.se` |
| `linefurniture.se` | `eval_only` | 8 | 8 | 100% | ok | `https://linefurniture.se` |
| `melimelihome.se` | `eval_only` | 8 | 8 | 100% | ok | `https://melimelihome.se` |
| `norrgavel.se` | `eval_only` | 8 | 8 | 100% | ok | `https://norrgavel.se` |
| `poshliving.se` | `eval_only` | 8 | 8 | 100% | ok | `https://poshliving.se` |
| `stalands.se` | `eval_only` | 8 | 8 | 100% | ok | `https://stalands.se` |
| `svenskttenn.com` | `eval_only` | 6 | 8 | 75% | parse-fail:2 | `https://svenskttenn.com` |
| `tibergsmobler.se` | `eval_only` | 8 | 8 | 100% | ok | `https://tibergsmobler.se` |

## Agent Review

| Host | Group | Accepted | Tested | Completion | Primary reason | Seed URL |
|---|---|---:|---:|---:|---|---|
| `ikea.com` | `core` | 0 | 8 | 0% | parse-fail:1 | `https://www.ikea.com/se/sv/cat/soffor-fatoljer-700640/` |
| `ilva.se` | `core` | 0 | 8 | 0% | currency:8 | `https://ilva.se/vardagsrum/soffor/` |
| `lannamobler.se` | `core` | 0 | 8 | 0% | fetch-error:1 | `https://www.lannamobler.se/soffor` |
| `affariofsweden.com` | `eval_only` | 0 | 1 | 0% | parse-fail:1 | `https://affariofsweden.com` |
| `artilleriet.se` | `eval_only` | 0 | 8 | 0% | currency:8 | `https://artilleriet.se` |
| `beliani.se` | `eval_only` | 0 | 8 | 0% | currency:8 | `https://beliani.se` |
| `bolia.com` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://bolia.com` |
| `brodernaanderssons.se` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://brodernaanderssons.se` |
| `burhens.com` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://burhens.com` |
| `clickonhome.se` | `eval_only` | 0 | 0 | 0% | dns-failure | `https://clickonhome.se` |
| `designhousestockholm.com` | `eval_only` | 0 | 8 | 0% | currency:8 | `https://designhousestockholm.com` |
| `dux.se` | `eval_only` | 0 | 8 | 0% | parse-fail:3 | `https://dux.se` |
| `fogia.com` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://fogia.com` |
| `furninova.com` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://furninova.com` |
| `granit.com` | `eval_only` | 2 | 3 | 67% | currency:1 | `https://granit.com` |
| `hemdesigners.se` | `eval_only` | 5 | 8 | 62% | invalid-price:1 | `https://hemdesigners.se` |
| `ihreborn.se` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://ihreborn.se` |
| `interioronline.se` | `eval_only` | 0 | 0 | 0% | dns-failure | `https://interioronline.se` |
| `iremobel.se` | `eval_only` | 0 | 8 | 0% | invalid-price:8 | `https://iremobel.se` |
| `jysk.se` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://www.jysk.se/vardagsrum/soffor` |
| `mhdesign.se` | `eval_only` | 0 | 0 | 0% | dns-failure | `https://mhdesign.se` |
| `mobelform.se` | `eval_only` | 0 | 1 | 0% | parse-fail:1 | `https://mobelform.se` |
| `nordicdesignhome.se` | `eval_only` | 0 | 0 | 0% | dns-failure | `https://nordicdesignhome.se` |
| `norrgavelsnickeri.se` | `eval_only` | 0 | 0 | 0% | dns-failure | `https://norrgavelsnickeri.se` |
| `room.se` | `eval_only` | 0 | 1 | 0% | fetch-error:1 | `https://room.se` |
| `room21.se` | `eval_only` | 0 | 0 | 0% | dns-failure | `https://room21.se` |
| `roomhome.se` | `eval_only` | 0 | 0 | 0% | dns-failure | `https://roomhome.se` |
| `sofacompany.com` | `eval_only` | 0 | 1 | 0% | parse-fail:1 | `https://sofacompany.com/sv-se` |
| `soffkoncept.se` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://soffkoncept.se` |
| `visionofhome.com.se` | `eval_only` | 0 | 8 | 0% | parse-fail:8 | `https://visionofhome.com.se` |
| `xxxlutz.se` | `eval_only` | 5 | 8 | 62% | parse-fail:3 | `https://xxxlutz.se` |

## Detailed Notes

### `chilli.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.chilli.se/`
- Discovery: strategy `crawl`, discovered `236`, product hints `192`, high-confidence `182`
- Extraction: accepted `8/8`
- Notes: ok

### `ellos.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.ellos.se/hem-inredning/mobler/soffor-fatoljer/soffor`
- Discovery: strategy `crawl`, discovered `328`, product hints `275`, high-confidence `275`
- Extraction: accepted `8/8`
- Notes: ok

### `furniturebox.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.furniturebox.se/`
- Discovery: strategy `crawl`, discovered `189`, product hints `137`, high-confidence `137`
- Extraction: accepted `8/8`
- Notes: ok

### `homeroom.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.homeroom.se/mobler/soffor-fatoljer/soffor`
- Discovery: strategy `crawl`, discovered `315`, product hints `289`, high-confidence `289`
- Extraction: accepted `8/8`
- Notes: ok

### `mio.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.mio.se/kampanj/soffor`
- Discovery: strategy `crawl`, discovered `119`, product hints `101`, high-confidence `101`
- Extraction: accepted `8/8`
- Notes: ok

### `sleepo.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.sleepo.se/mobler/soffor-fatoljer/`
- Discovery: strategy `crawl`, discovered `192`, product hints `148`, high-confidence `139`
- Extraction: accepted `8/8`
- Notes: ok

### `soffadirekt.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.soffadirekt.se/`
- Discovery: strategy `crawl`, discovered `500`, product hints `185`, high-confidence `185`
- Extraction: accepted `8/8`
- Notes: ok

### `svenskahem.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.svenskahem.se/produkter/soffor`
- Discovery: strategy `crawl`, discovered `134`, product hints `18`, high-confidence `18`
- Extraction: accepted `8/8`
- Notes: ok

### `svenssons.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.svenssons.se/mobler/soffor/`
- Discovery: strategy `crawl`, discovered `154`, product hints `141`, high-confidence `141`
- Extraction: accepted `8/8`
- Notes: ok

### `sweef.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://sweef.se/soffor`
- Discovery: strategy `crawl`, discovered `238`, product hints `218`, high-confidence `218`
- Extraction: accepted `8/8`
- Notes: ok

### `trademax.se`
- Group: `core`
- Classification: `scrape_first`
- Seed URL: `https://www.trademax.se/`
- Discovery: strategy `crawl`, discovered `259`, product hints `202`, high-confidence `189`
- Extraction: accepted `8/8`
- Notes: ok

### `englesson.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://englesson.se`
- Discovery: strategy `crawl`, discovered `126`, product hints `121`, high-confidence `121`
- Extraction: accepted `6/8`
- Notes: fetch-error:2

### `folkhemmet.com`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://folkhemmet.com`
- Discovery: strategy `crawl`, discovered `156`, product hints `130`, high-confidence `130`
- Extraction: accepted `7/8`
- Notes: parse-fail:1
- Parse samples: No product extracted (JSON-LD blocks: 1, og:type: website)

### `gad.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://gad.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `21`, product hints `4`, high-confidence `4`
- Extraction: accepted `8/8`
- Notes: ok

### `linefurniture.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://linefurniture.se`
- Discovery: strategy `crawl`, discovered `111`, product hints `106`, high-confidence `106`
- Extraction: accepted `8/8`
- Notes: ok

### `melimelihome.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://melimelihome.se`
- Discovery: strategy `crawl`, discovered `283`, product hints `231`, high-confidence `231`
- Extraction: accepted `8/8`
- Notes: ok

### `norrgavel.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://norrgavel.se`
- Discovery: strategy `crawl`, discovered `113`, product hints `25`, high-confidence `25`
- Extraction: accepted `8/8`
- Notes: ok

### `poshliving.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://poshliving.se`
- Discovery: strategy `crawl`, discovered `368`, product hints `181`, high-confidence `181`
- Extraction: accepted `8/8`
- Notes: ok

### `stalands.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://stalands.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `129`, product hints `80`, high-confidence `80`
- Extraction: accepted `8/8`
- Notes: ok

### `svenskttenn.com`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://svenskttenn.com`
- Discovery: strategy `crawl`, discovered `18`, product hints `18`, high-confidence `18`
- Extraction: accepted `6/8`
- Notes: parse-fail:2
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: None) | No product extracted (JSON-LD blocks: 0, og:type: None)

### `tibergsmobler.se`
- Group: `eval_only`
- Classification: `scrape_first`
- Seed URL: `https://tibergsmobler.se`
- Discovery: strategy `crawl`, discovered `151`, product hints `53`, high-confidence `53`
- Extraction: accepted `8/8`
- Notes: ok

### `ikea.com`
- Group: `core`
- Classification: `agent_review`
- Seed URL: `https://www.ikea.com/se/sv/cat/soffor-fatoljer-700640/`
- Discovery: strategy `crawl`, discovered `500`, product hints `489`, high-confidence `482`
- Extraction: accepted `0/8`
- Notes: parse-fail:1, invalid-price:6, currency:1
- Parse samples: No product extracted (JSON-LD blocks: 1, og:type: article)

### `ilva.se`
- Group: `core`
- Classification: `agent_review`
- Seed URL: `https://ilva.se/vardagsrum/soffor/`
- Discovery: strategy `crawl`, discovered `149`, product hints `82`, high-confidence `40`
- Extraction: accepted `0/8`
- Notes: currency:8

### `lannamobler.se`
- Group: `core`
- Classification: `agent_review`
- Seed URL: `https://www.lannamobler.se/soffor`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `9`, product hints `1`, high-confidence `1`
- Extraction: accepted `0/8`
- Notes: fetch-error:1, parse-fail:7
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website)

### `affariofsweden.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://affariofsweden.com`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `0`, product hints `0`, high-confidence `0`
- Extraction: accepted `0/1`
- Notes: parse-fail:1
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: website)

### `artilleriet.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://artilleriet.se`
- Discovery: strategy `crawl`, discovered `20`, product hints `20`, high-confidence `20`
- Extraction: accepted `0/8`
- Notes: currency:8

### `beliani.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://beliani.se`
- Discovery: strategy `crawl`, discovered `114`, product hints `23`, high-confidence `23`
- Extraction: accepted `0/8`
- Notes: currency:8

### `bolia.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://bolia.com`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `45`, product hints `20`, high-confidence `20`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 2, og:type: None) | No product extracted (JSON-LD blocks: 2, og:type: None) | No product extracted (JSON-LD blocks: 2, og:type: None) | No product extracted (JSON-LD blocks: 2, og:type: None) | No product extracted (JSON-LD blocks: 2, og:type: None)

### `brodernaanderssons.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://brodernaanderssons.se`
- Discovery: strategy `crawl`, discovered `69`, product hints `66`, high-confidence `66`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article)

### `burhens.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://burhens.com`
- Discovery: strategy `crawl`, discovered `8`, product hints `8`, high-confidence `8`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article)

### `clickonhome.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://clickonhome.se`
- Discovery: strategy `dns-check`, discovered `0`, product hints `0`, high-confidence `0`
- Discovery error: `[Errno 8] nodename nor servname provided, or not known`
- Extraction: accepted `0/0`
- Notes: dns-failure

### `designhousestockholm.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://designhousestockholm.com`
- Discovery: strategy `crawl`, discovered `20`, product hints `20`, high-confidence `20`
- Extraction: accepted `0/8`
- Notes: currency:8

### `dux.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://dux.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `34`, product hints `7`, high-confidence `7`
- Extraction: accepted `0/8`
- Notes: parse-fail:3, invalid-price:5
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website)

### `fogia.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://fogia.com`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `15`, product hints `3`, high-confidence `2`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website)

### `furninova.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://furninova.com`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `117`, product hints `0`, high-confidence `0`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article) | No product extracted (JSON-LD blocks: 1, og:type: article)

### `granit.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://granit.com`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `3`, product hints `3`, high-confidence `3`
- Extraction: accepted `2/3`
- Notes: currency:1

### `hemdesigners.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://hemdesigners.se`
- Discovery: strategy `crawl`, discovered `91`, product hints `49`, high-confidence `49`
- Extraction: accepted `5/8`
- Notes: invalid-price:1, missing-image:2

### `ihreborn.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://ihreborn.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `26`, product hints `7`, high-confidence `7`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: None) | No product extracted (JSON-LD blocks: 0, og:type: None) | No product extracted (JSON-LD blocks: 0, og:type: None) | No product extracted (JSON-LD blocks: 0, og:type: None) | No product extracted (JSON-LD blocks: 0, og:type: None)

### `interioronline.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://interioronline.se`
- Discovery: strategy `dns-check`, discovered `0`, product hints `0`, high-confidence `0`
- Discovery error: `[Errno 8] nodename nor servname provided, or not known`
- Extraction: accepted `0/0`
- Notes: dns-failure

### `iremobel.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://iremobel.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `14`, product hints `10`, high-confidence `10`
- Extraction: accepted `0/8`
- Notes: invalid-price:8

### `jysk.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://www.jysk.se/vardagsrum/soffor`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `10`, product hints `0`, high-confidence `0`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 1, og:type: None) | No product extracted (JSON-LD blocks: 1, og:type: None) | No product extracted (JSON-LD blocks: 1, og:type: None) | No product extracted (JSON-LD blocks: 1, og:type: None) | No product extracted (JSON-LD blocks: 1, og:type: None)

### `mhdesign.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://mhdesign.se`
- Discovery: strategy `dns-check`, discovered `0`, product hints `0`, high-confidence `0`
- Discovery error: `[Errno 8] nodename nor servname provided, or not known`
- Extraction: accepted `0/0`
- Notes: dns-failure

### `mobelform.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://mobelform.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `0`, product hints `0`, high-confidence `0`
- Extraction: accepted `0/1`
- Notes: parse-fail:1
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: None)

### `nordicdesignhome.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://nordicdesignhome.se`
- Discovery: strategy `dns-check`, discovered `0`, product hints `0`, high-confidence `0`
- Discovery error: `[Errno 8] nodename nor servname provided, or not known`
- Extraction: accepted `0/0`
- Notes: dns-failure

### `norrgavelsnickeri.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://norrgavelsnickeri.se`
- Discovery: strategy `dns-check`, discovered `0`, product hints `0`, high-confidence `0`
- Discovery error: `[Errno 8] nodename nor servname provided, or not known`
- Extraction: accepted `0/0`
- Notes: dns-failure

### `room.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://room.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `0`, product hints `0`, high-confidence `0`
- Extraction: accepted `0/1`
- Notes: fetch-error:1

### `room21.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://room21.se`
- Discovery: strategy `dns-check`, discovered `0`, product hints `0`, high-confidence `0`
- Discovery error: `[Errno 8] nodename nor servname provided, or not known`
- Extraction: accepted `0/0`
- Notes: dns-failure

### `roomhome.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://roomhome.se`
- Discovery: strategy `dns-check`, discovered `0`, product hints `0`, high-confidence `0`
- Discovery error: `[Errno 8] nodename nor servname provided, or not known`
- Extraction: accepted `0/0`
- Notes: dns-failure

### `sofacompany.com`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://sofacompany.com/sv-se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `0`, product hints `0`, high-confidence `0`
- Extraction: accepted `0/1`
- Notes: parse-fail:1
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: None)

### `soffkoncept.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://soffkoncept.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `16`, product hints `0`, high-confidence `0`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 1, og:type: website) | No product extracted (JSON-LD blocks: 1, og:type: website) | No product extracted (JSON-LD blocks: 1, og:type: website) | No product extracted (JSON-LD blocks: 1, og:type: website) | No product extracted (JSON-LD blocks: 1, og:type: website)

### `visionofhome.com.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://visionofhome.com.se`
- Discovery: strategy `crawl+sitemap-fallback`, discovered `21`, product hints `5`, high-confidence `5`
- Extraction: accepted `0/8`
- Notes: parse-fail:8
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website) | No product extracted (JSON-LD blocks: 0, og:type: website)

### `xxxlutz.se`
- Group: `eval_only`
- Classification: `agent_review`
- Seed URL: `https://xxxlutz.se`
- Discovery: strategy `crawl`, discovered `16`, product hints `15`, high-confidence `15`
- Extraction: accepted `5/8`
- Notes: parse-fail:3
- Parse samples: No product extracted (JSON-LD blocks: 0, og:type: None) | No product extracted (JSON-LD blocks: 0, og:type: None) | No product extracted (JSON-LD blocks: 0, og:type: None)
