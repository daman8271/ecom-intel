# Blinkit candidate pincode coverage

Generated from `/root/ingest/file_0.xlsx` (PinCode-blinkit.xlsx, 16 city sheets).

**Total unique pincodes geocoded: 798** (of 798 parsed candidates).

## Per-city counts

| City | Pincodes | Tier |
| --- | ---: | :---: |
| Bengaluru | 99 | 1 |
| Bhopal | 5 | 2 |
| Chandigarh | 24 | 2 |
| Delhi | 92 | 1 |
| Faridabad | 17 | 2 |
| Ghaziabad | 26 | 2 |
| Gurgaon | 27 | 2 |
| Indore | 1 | 2 |
| Jaipur | 77 | 1 |
| Kolkata | 62 | 1 |
| Ludhiana | 70 | 2 |
| Mumbai | 110 | 1 |
| Mysuru | 28 | 2 |
| Noida | 10 | 2 |
| Pune | 136 | 1 |
| Surat | 14 | 2 |

## Geocoding sources

- GeoNames postal dump (`https://download.geonames.org/export/zip/IN.zip`): **760**
- sanand0/pincode CSV (`https://raw.githubusercontent.com/sanand0/pincode/master/data/IN.csv`): **16**
- OpenStreetMap Nominatim (`https://nominatim.openstreetmap.org/search`, 1 req/sec, cached; postalcode + locality-name queries): **21**
- Manual locality coordinate (last resort, India-bounds-validated): **1**
- FAILED to geocode: **0**

**Success rate: 798/798 = 100.0%**

Coordinates validated within India bounds (lat 6..37, lon 68..98).

No coordinates fell outside India bounds.

## Pincodes that could NOT be geocoded
- None — all pincodes geocoded successfully.

## Accuracy caveat: dataset coordinate clustering

The free open datasets used here (GeoNames, sanand0) provide **region/post-office level**
coordinates, not pincode-precise centroids. As a result many pincodes inside the same
postal region share one approximate coordinate. The largest clusters:

| City | Shared coordinate | # pincodes |
| --- | --- | ---: |
| Bengaluru | (13.2257, 77.575) | 85 |
| Mumbai | (18.9808, 72.8338) | 54 |
| Pune | (18.5716, 74.07) | 51 |
| Kolkata | (22.5553, 88.3558) | 46 |
| Ludhiana | (30.8047, 75.8361) | 20 |
| Ghaziabad | (28.7643, 77.4856) | 18 |

These coordinates land within the correct metro area (validated inside India bounds and,
spot-checked, inside the right city), which is sufficient for the Blinkit scraper's purpose
of selecting a serviceable store location, but they are NOT street-accurate. The
GeoNames-first ordering was chosen deliberately: sanand0 clusters even harder and even
mis-assigns some Bengaluru pincodes (560001-560009) to Mysuru coordinates. For street-level
accuracy a paid/precise pincode-centroid dataset or a per-pincode forward geocode of the
representative locality would be required.
