# Swiper Retailer Scrape Targets

Last updated: 2026-03-13

This file separates the scrape universe into three buckets:

1. Core targets: the 20 retailers defined in `scripts/seed_retailer_sources.sh`.
2. Extended evaluation targets: the broader 53-host crawl-eval universe from `docs/reports/retailer_crawl_status_latest.csv`.
3. Excluded hosts: sites explicitly excluded in `docs/reports/failed_sites_active_2026-02-09_notes.md`.

If the question is "what do we actually intend to seed and run as retailer sources?", use the 20 core targets below.

## Core targets (20)

| Retailer | Host | Entry URL | Latest crawl-eval status |
|---|---|---|---|
| IKEA Sverige | `ikea.com` | `https://www.ikea.com/se/sv/cat/soffor-fatoljer-700640/` | `passed` (`19/20`) |
| Mio | `mio.se` | `https://www.mio.se/kampanj/soffor` | `passed` (`20/20`) |
| Trademax | `trademax.se` | `https://www.trademax.se/` | `passed` (`3/20`) |
| Chilli | `chilli.se` | `https://www.chilli.se/` | `passed` (`2/20`) |
| Furniturebox | `furniturebox.se` | `https://www.furniturebox.se/` | `passed` (`2/20`) |
| SoffaDirekt | `soffadirekt.se` | `https://www.soffadirekt.se/` | `passed` (`20/20`) |
| Svenska Hem | `svenskahem.se` | `https://www.svenskahem.se/produkter/soffor` | `passed` (`20/20`) |
| Svenssons | `svenssons.se` | `https://www.svenssons.se/mobler/soffor/` | `passed` (`20/20`) |
| Lanna Mobler | `lannamobler.se` | `https://www.lannamobler.se/soffor` | `passed` (`1/20`) |
| Nordiska Galleriet | `nordiskagalleriet.se` | `https://www.nordiskagalleriet.se/no-ga/soffor` | `not_in_latest_report` |
| RoyalDesign | `royaldesign.se` | `https://royaldesign.se/mobler/soffor` | `not_in_latest_report` |
| Rum21 | `rum21.se` | `https://www.rum21.se/` | `not_in_latest_report` |
| EM Home | `emhome.se` | `https://www.emhome.se/soffor` | `not_in_latest_report` |
| Jotex | `jotex.se` | `https://www.jotex.se/mobler/soffor` | `not_in_latest_report` |
| Ellos | `ellos.se` | `https://www.ellos.se/hem-inredning/mobler/soffor-fatoljer/soffor` | `passed` (`4/20`) |
| Homeroom | `homeroom.se` | `https://www.homeroom.se/mobler/soffor-fatoljer/soffor` | `passed` (`4/20`) |
| Sweef | `sweef.se` | `https://sweef.se/soffor` | `passed` (`20/20`) |
| Sleepo | `sleepo.se` | `https://www.sleepo.se/mobler/soffor-fatoljer/` | `passed` (`20/20`) |
| Newport | `newport.se` | `https://www.newport.se/shop/mobler/soffor` | `not_in_latest_report` |
| ILVA | `ilva.se` | `https://ilva.se/vardagsrum/soffor/` | `passed` (`6/20`) |

## Extended evaluation targets (53 total hosts)

These are the hosts present in `docs/reports/retailer_crawl_status_latest.csv`.

### In both core targets and latest crawl eval (14)

- `chilli.se`
- `ellos.se`
- `furniturebox.se`
- `homeroom.se`
- `ikea.com`
- `ilva.se`
- `lannamobler.se`
- `mio.se`
- `sleepo.se`
- `soffadirekt.se`
- `svenskahem.se`
- `svenssons.se`
- `sweef.se`
- `trademax.se`

### Eval-only hosts (39)

- `affariofsweden.com`
- `artilleriet.se`
- `beliani.se`
- `bolia.com`
- `brodernaanderssons.se`
- `burhens.com`
- `clickonhome.se`
- `designhousestockholm.com`
- `dux.se`
- `englesson.se`
- `fogia.com`
- `folkhemmet.com`
- `furninova.com`
- `gad.se`
- `granit.com`
- `hemdesigners.se`
- `ihreborn.se`
- `interioronline.se`
- `iremobel.se`
- `jysk.se`
- `linefurniture.se`
- `melimelihome.se`
- `mhdesign.se`
- `mobelform.se`
- `nordicdesignhome.se`
- `norrgavel.se`
- `norrgavelsnickeri.se`
- `poshliving.se`
- `room.se`
- `room21.se`
- `roomhome.se`
- `sofacompany.com`
- `soffkoncept.se`
- `stalands.se`
- `svenskttenn.com`
- `tibergsmobler.se`
- `visionofhome.com.se`
- `xxxlutz.se`

## Excluded from active failed-site scope

These were explicitly excluded in `docs/reports/failed_sites_active_2026-02-09_notes.md`.

- `brodernaanderssons.se`
- `clickonhome.se`
- `interioronline.se`
- `mhdesign.se`
- `nordicdesignhome.se`
- `norrgavelsnickeri.se`
- `room.se`
- `room21.se`
- `roomhome.se`
- `xn--trbolaget-w2a.se`

## Practical recommendation

For actual source seeding and family-test readiness, treat the following as the primary scrape list:

- the 20 core targets in `scripts/seed_retailer_sources.sh`

For crawl R&D and reliability work, treat the following as the broader scrape universe:

- the full 53-host set in `docs/reports/retailer_crawl_status_latest.csv`
