# Crawl Evaluation (Merged)

- Source reports: docs/reports/crawl_eval_20260208T213355Z.json, docs/reports/crawl_eval_20260208T213813Z.json
- Replaced bug-affected sites: 12

## Completion

- Entry pass rate: 18/80 (22.5%)
- Unique site pass rate: 14/65 (21.5%)
- Unique site full completion rate: 0/65 (0.0%)
- Page completion: 100/1014 (9.9%)
- Image URL validity: 193/252 (76.6%)
- Primary image coverage: 61/100 (61.0%)

## Error Totals

- Top failure reasons: [['parse-fail', 40], ['fetch-error', 31], ['fetch-blocked', 7], ['broken-images', 7], ['invalid-price', 4]]
- Page failure totals: {'fetchBlocked': 7, 'fetchError': 234, 'parse': 631, 'invalidPrice': 42, 'currencyMismatch': 0}
- Fetch error breakdown totals: {'http-404': 220, 'robots-blocked': 7, 'HTTP 406': 2, 'dns-failure': 9, 'tls-certificate': 2, 'http-403': 1}
- Image issue totals: {'http-404': 52, 'http-502': 7}

## Passed Sites

| Site | Accepted/Tested | Page % | Valid Images/Checked | Primary % | Reasons |
|---|---:|---:|---:|---:|---|
| https://www.ikea.com/ | 19/20 | 95.0% | 63/63 | 100.0% | parse-fail:1 |
| https://www.gad.se/ | 12/20 | 60.0% | 34/34 | 100.0% | parse-fail:8 |
| https://www.svenskttenn.com/ | 11/15 | 73.3% | 10/10 | 100.0% | fetch-error:4 |
| https://www.lannamobler.se/ | 1/20 | 5.0% | 5/5 | 100.0% | parse-fail:19 |
| https://www.ellos.se/ | 4/20 | 20.0% | 19/19 | 100.0% | fetch-error:16 |
| https://www.chilli.se/ | 2/20 | 10.0% | 0/10 | 0.0% | fetch-error:18, broken-images:10 |
| https://www.trademax.se/ | 3/20 | 15.0% | 0/10 | 0.0% | fetch-error:17, broken-images:10 |
| https://soffkoncept.se/ | 20/20 | 100.0% | 1/3 | 0.0% | broken-images:2 |
| https://trademax.se/ | 3/20 | 15.0% | 0/10 | 0.0% | fetch-error:17, broken-images:10 |
| https://ellos.se/ | 4/20 | 20.0% | 19/19 | 100.0% | fetch-error:16 |
| https://chilli.se/ | 2/20 | 10.0% | 0/10 | 0.0% | fetch-error:18, broken-images:10 |
| https://artilleriet.se/ | 13/20 | 65.0% | 23/30 | 46.2% | parse-fail:7, broken-images:7 |
| https://www.furniturebox.se/ | 2/20 | 10.0% | 0/10 | 0.0% | fetch-error:18, broken-images:10 |
| https://www.homeroom.se/ | 4/20 | 20.0% | 19/19 | 100.0% | fetch-error:16 |

## Failed Sites

| Site | Accepted/Tested | Reasons |
|---|---:|---|
| https://brodernaanderssons.se/ | 0/20 | parse-fail:20 |
| https://www.hemdesigners.se/ | 0/20 | parse-fail:20 |
| https://www.svenskahem.se/ | 0/20 | fetch-error:2, parse-fail:18 |
| https://www.svenssons.se/ | 0/20 | parse-fail:20 |
| https://www.furninova.com/ | 0/20 | parse-fail:20 |
| https://www.sweef.se/ | 0/20 | fetch-error:19, parse-fail:1 |
| https://www.iremobel.se/ | 0/9 | invalid-price:9 |
| https://www.tibergsmobler.se/ | 0/20 | parse-fail:20 |
| https://www.burhens.com/ | 0/20 | parse-fail:20 |
| https://www.mobelform.se/ | 0/20 | fetch-error:20 |
| https://www.stalands.se/ | 0/20 | parse-fail:20 |
| https://www.englesson.se/ | 0/20 | fetch-blocked:1, parse-fail:19 |
| https://www.mio.se/ | 0/20 | fetch-error:20 |
| https://www.dux.se/ | 0/20 | parse-fail:20 |
| https://www.bolia.com/ | 0/20 | parse-fail:20 |
| https://linefurniture.se/ | 0/20 | fetch-blocked:1, fetch-error:1, parse-fail:18 |
| https://ilva.se/ | 0/3 | parse-fail:3 |
| https://www.visionofhome.com.se/ | 0/20 | parse-fail:20 |
| https://www.norrgavel.se/ | 0/20 | parse-fail:20 |
| https://www.melimelihome.se/ | 0/20 | parse-fail:20 |
| https://www.sleepo.se/ | 0/20 | parse-fail:20 |
| https://www.affariofsweden.com/ | 0/17 | parse-fail:17 |
| https://www.linefurniture.se/ | 0/20 | fetch-blocked:1, fetch-error:1, parse-fail:18 |
| https://www.ilva.se/ | 0/3 | parse-fail:3 |
| https://www.beliani.se/ | 0/20 | fetch-error:1, parse-fail:19 |
| https://www.mhdesign.se/ | 0/1 | fetch-error:1 |
| https://www.room.se/ | 0/1 | fetch-error:1 |
| https://www.folkhemmet.com/ | 0/20 | fetch-blocked:1, parse-fail:3, invalid-price:16 |
| https://www.ihreborn.se/ | 0/20 | parse-fail:20 |
| https://designhousestockholm.com/ | 0/20 | parse-fail:19, invalid-price:1 |
| https://sofacompany.com/sv-se | 0/20 | parse-fail:20 |
| https://beliani.se/ | 0/20 | fetch-error:1, parse-fail:19 |
| https://poshliving.se/ | 0/20 | fetch-blocked:1, parse-fail:19 |
| https://folkhemmet.com/ | 0/20 | fetch-blocked:1, parse-fail:3, invalid-price:16 |
| https://ihreborn.se/ | 0/20 | parse-fail:20 |
| https://fogia.com/ | 0/15 | fetch-error:14, parse-fail:1 |
| https://bolia.com/ | 0/20 | parse-fail:20 |
| https://mhdesign.se/ | 0/1 | fetch-error:1 |
| https://room.se/ | 0/1 | fetch-error:1 |
| https://xn--trbolaget-w2a.se/ | 0/1 | fetch-error:1 |
| https://norrgavelsnickeri.se/ | 0/1 | fetch-error:1 |
| https://granit.com/ | 0/20 | fetch-error:3, parse-fail:17 |
| https://www.jysk.se/ | 0/20 | parse-fail:20 |
| https://www.soffadirekt.se/ | 0/20 | fetch-blocked:1, parse-fail:19 |
| https://www.xxxlutz.se/ | 0/1 | fetch-error:1 |
| https://www.jysk.se/vardagsrum/soffor | 0/20 | parse-fail:20 |
| https://www.clickonhome.se/ | 0/1 | fetch-error:1 |
| https://www.room21.se/ | 0/1 | fetch-error:1 |
| https://www.roomhome.se/ | 0/1 | fetch-error:1 |
| https://www.interioronline.se/ | 0/1 | fetch-error:1 |
| https://www.nordicdesignhome.se/ | 0/1 | fetch-error:1 |