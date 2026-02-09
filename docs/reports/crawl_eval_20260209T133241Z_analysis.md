# Crawl Evaluation Analysis (Failed-Only Rerun)

- Baseline report: `docs/reports/crawl_eval_20260209T103804Z.json`
- Rerun report: `docs/reports/crawl_eval_20260209T133241Z.json`
- URL set: `scripts/url_lists/failed_sites_2026-02-09.txt` (51 entries)

## Before vs after (same 51 failed entries)

- Site pass rate: 0/51 -> 14/51
- Full completion: 0/51 -> 6/51
- Page completion: 0/672 -> 207/676
- Image URL validity: 0/0 -> 184/204
- Primary image coverage: 0/0 -> 170/207

## Newly fixed entries (status=passed)

- https://beliani.se/ (accepted 18/20, image valid 1/11, primary 1/18)
- https://designhousestockholm.com/ (accepted 20/20, image valid 20/20, primary 20/20)
- https://ilva.se/ (accepted 6/20, image valid 6/6, primary 6/6)
- https://linefurniture.se/ (accepted 20/20, image valid 20/20, primary 20/20)
- https://www.beliani.se/ (accepted 18/20, image valid 1/11, primary 1/18)
- https://www.englesson.se/ (accepted 20/20, image valid 20/20, primary 20/20)
- https://www.folkhemmet.com/ (accepted 7/20, image valid 7/7, primary 7/7)
- https://www.hemdesigners.se/ (accepted 8/20, image valid 8/8, primary 8/8)
- https://www.ilva.se/ (accepted 6/20, image valid 6/6, primary 6/6)
- https://www.linefurniture.se/ (accepted 20/20, image valid 20/20, primary 20/20)
- https://www.melimelihome.se/ (accepted 20/20, image valid 19/19, primary 20/20)
- https://www.norrgavel.se/ (accepted 20/20, image valid 32/32, primary 17/20)
- https://www.svenskahem.se/ (accepted 20/20, image valid 20/20, primary 20/20)
- https://www.xxxlutz.se/ (accepted 4/16, image valid 4/4, primary 4/4)

## Remaining failure classes (unique host+path, www collapsed)

### candidate-urls-unfetchable (3)

- fogia.com: accepted 0/20, discovered 30, product hints 2, reasons fetch-error:3, parse-fail:17
- mio.se: accepted 0/20, discovered 214, product hints 63, reasons fetch-error:20
- sweef.se: accepted 0/20, discovered 480, product hints 403, reasons fetch-error:20

### candidate-urls-unfetchable+price (1)

- iremobel.se: accepted 0/20, discovered 138, product hints 9, reasons fetch-error:9, parse-fail:2, invalid-price:9

### external-unreachable-or-blocked (10)

- clickonhome.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- interioronline.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- mhdesign.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- nordicdesignhome.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- norrgavelsnickeri.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- poshliving.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- room.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- room21.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- roomhome.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1
- xn--trbolaget-w2a.se: accepted 0/1, discovered 0, product hints 0, reasons fetch-error:1

### extractor-miss-on-product-pages (3)

- brodernaanderssons.se: accepted 0/20, discovered 67, product hints 64, reasons parse-fail:20
- burhens.com: accepted 0/15, discovered 15, product hints 10, reasons parse-fail:15
- furninova.com: accepted 0/20, discovered 130, product hints 6, reasons parse-fail:20

### mixed (1)

- stalands.se: accepted 0/20, discovered 480, product hints 0, reasons fetch-error:20

### no-product-hints-or-wrong-pages (13)

- affariofsweden.com: accepted 0/1, discovered 0, product hints 0, reasons parse-fail:1
- bolia.com: accepted 0/20, discovered 45, product hints 0, reasons parse-fail:20
- granit.com: accepted 0/1, discovered 0, product hints 0, reasons parse-fail:1
- ihreborn.se: accepted 0/20, discovered 23, product hints 0, reasons fetch-error:16, parse-fail:4
- jysk.se: accepted 0/8, discovered 8, product hints 0, reasons parse-fail:8
- jysk.se/vardagsrum/soffor: accepted 0/20, discovered 46, product hints 0, reasons parse-fail:20
- mobelform.se: accepted 0/1, discovered 0, product hints 0, reasons parse-fail:1
- sleepo.se: accepted 0/20, discovered 535, product hints 0, reasons parse-fail:20
- sofacompany.com/sv-se: accepted 0/1, discovered 0, product hints 0, reasons parse-fail:1
- soffadirekt.se: accepted 0/20, discovered 769, product hints 0, reasons parse-fail:20
- svenssons.se: accepted 0/20, discovered 195, product hints 0, reasons fetch-error:9, parse-fail:11
- tibergsmobler.se: accepted 0/20, discovered 263, product hints 0, reasons parse-fail:20
- visionofhome.com.se: accepted 0/20, discovered 20, product hints 0, reasons parse-fail:20

### no-product-hints-or-wrong-pages+price (1)

- dux.se: accepted 0/20, discovered 228, product hints 0, reasons parse-fail:2, invalid-price:18

## Image issues still present

- https://www.norrgavel.se/: urlsInvalid=0, issueBreakdown={}, primary=17/20
- https://www.beliani.se/: urlsInvalid=10, issueBreakdown={'low-resolution': 10, 'tiny-file-size': 5}, primary=1/18
- https://beliani.se/: urlsInvalid=10, issueBreakdown={'low-resolution': 10, 'tiny-file-size': 5}, primary=1/18
