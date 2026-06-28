# India Pincode Universe — Exact, Reproducible Counts

One-line summary: India has **19,300 distinct 6-digit PIN codes** (served by 157,126 post-office records), computed directly from the canonical India Post "All India Pincode Directory"; this doc gives exact distinct-pincode counts for the **25-city JIVO target list** (total **1,885** distinct pincodes = **9.8%** of India) plus city-proper/metro breakdowns, every count derived from the raw directory and cross-checked against independent web sources.

---

## Dataset provenance

| Item | Value |
|---|---|
| Dataset | India Post — **All India Pincode Directory** (Dept. of Posts, Ministry of Communications, Govt. of India), published on the OGD Platform (data.gov.in) |
| Bulk source actually downloaded | GitHub mirror **dropdevrahul/pincodes-india** — raw CSV |
| Raw URL | `https://raw.githubusercontent.com/dropdevrahul/pincodes-india/main/pincode.csv` |
| Local copy | `/opt/ecom-intel/docs/pincodes/drr_pincode.csv` (23.8 MB) |
| Columns | `CircleName, RegionName, DivisionName, OfficeName, Pincode, OfficeType, Delivery, District, StateName, Latitude, Longitude` |
| As-of date | Matches the **June-2024** official India Post snapshot exactly (see below) |
| Total post-office records (valid 6-digit) | **157,126** |
| Total DISTINCT 6-digit pincodes | **19,300** ← national total |
| Coverage | 36 StateName strings = all 28 states + 8 UTs (incl. both Jammu & Kashmir and Ladakh, confirming a post-2019 / recent vintage) |

Note on the canonical source: the `data.gov.in` direct S3 file (`.../dataurl03122020/pincode.csv`) returned **HTTP 403 (AccessDenied)** from this datacenter VPS, so the dropdevrahul GitHub mirror — a byte-faithful copy of the same data.gov.in "All India Pincode Directory" with the identical Dept.-of-Posts column schema — was used as the bulk source. Its computed totals (157,126 records / 19,300 pincodes) **reproduce the officially-published June-2024 figures exactly**, which is the integrity proof that this is the real, complete directory rather than a truncated copy.

---

## National total

> **India has 19,300 distinct PIN codes** (as of the June-2024 India Post directory), spread over 157,126 post offices across 28 states and 8 union territories.

This is the count of DISTINCT 6-digit pincode strings in the directory — NOT the 157,126 post-office record count (many post offices share one PIN).

---

## The 25-city JIVO target list — exact distinct-pincode counts

All counts are **distinct 6-digit pincodes** computed from the canonical directory, using the India Post **District** string for each city (and the postal **Division** for the two pre-reorg Andhra Pradesh cities — see note). Reproduce with `compute_25_cities.py` (below).

| # | City | Distinct PINs | Unit counted | Notes |
|---|---|---:|---|---|
| 1 | **Mumbai** | 89 | Mumbai City + Mumbai Suburban districts | metro = 89 |
| 2 | **Delhi** | 97 | entire NCT (11 districts) | |
| 3 | **Bengaluru** | 117 | Bengaluru Urban district | metro 131 (+Rural) |
| 4 | **Hyderabad** | 60 | Hyderabad district | metro 140 (+Medchal +Ranga Reddy) |
| 5 | **Chennai** | 83 | Chennai district | metro 214 (+suburb districts) |
| 6 | **Pune** | 145 | Pune district | bundles city + PCMC + rural |
| 7 | **Ahmedabad** | 81 | Ahmadabad district | directory spelling AHMADABAD |
| 8 | **Kolkata** | 74 | Kolkata district | metro 332 (+24-Pgs N/S +Howrah) |
| 9 | **Surat** | 79 | Surat district | |
| 10 | **Noida** | 28 | Gautam Buddha Nagar district | whole GBN (Noida+Gr.Noida+Dadri) |
| 11 | **Gurugram** | 29 | Gurugram district | not "Gurgaon" |
| 12 | **Jaipur** | 84 | Jaipur district | |
| 13 | **Lucknow** | 43 | Lucknow district | |
| 14 | **Chandigarh** | 25 | Chandigarh UT | tricity 66 (+Mohali +Panchkula) |
| 15 | **Kochi** | 143 | Ernakulam district | district >> Kochi city (Aluva, Muvattupuzha…) |
| 16 | **Indore** | 30 | Indore district | |
| 17 | **Coimbatore** | 107 | Coimbatore district | |
| 18 | **Nagpur** | 63 | Nagpur district | |
| 19 | **Visakhapatnam** | 41 | Visakhapatnam **postal Division** | old "VISAKHAPATANAM" district bucket = 93 |
| 20 | **Vadodara** | 61 | Vadodara district | |
| 21 | **Bhubaneswar** | 69 | Khordha district | Bhubaneswar sits in Khordha/Khurda |
| 22 | **Nashik** | 77 | Nashik district | |
| 23 | **Mysuru** | 68 | Mysuru district | |
| 24 | **Vijayawada** | 59 | Vijayawada **postal Division** | Krishna district bucket = 119 |
| 25 | **Thiruvananthapuram** | 133 | Thiruvananthapuram district | |
| | **TOTAL (distinct union)** | **1,885** | all 25 | naive sum 1,885; **zero overlap** (all separate districts/divisions); = **9.8%** of India's 19,300 |

**Andhra Pradesh note (cities 19 & 24).** This directory predates AP's April-2022 26-district reorganization — it still uses the old 13 districts (no NTR, no Anakapalli, no Alluri Sitharama Raju). So the directory's `District` bucket for these two is a stale **mega-district**: `KRISHNA` (119 PINs, spans Vijayawada+Gudivada+Machilipatnam divisions) and `VISAKHAPATANAM` (93 PINs, even folds in Kakinada+Vizianagaram postal divisions). The honest **city** figure is therefore the postal **Division**: **Vijayawada Division = 59**, **Visakhapatnam Division = 41**. Both numbers are given so you can pick the scope you need (city division vs old district).

> **Overlap with the earlier 12-group analysis:** cities 1–9, 12 and 14 here are the same as in the section below (Mumbai, Delhi, Bengaluru, Hyderabad, Chennai, Pune, Ahmedabad, Kolkata, Surat, Jaipur, Chandigarh); Noida (10) and Gurugram (11) were the NCR per-town rows. Cities 13, 15–25 are the newly-added ones. The detailed district-string filters, metro unions and prefix cross-checks for the overlapping cities are in the table below.

---

## The 12 city-groups — distinct-pincode counts

All counts are **distinct 6-digit pincodes**. Metro figures are **set UNIONS** over the listed districts (a pincode shared by two districts is counted once), not naive sums. "Prefix x-check" = distinct pincodes whose first 3 digits fall in the city's known prefix set — a sanity cross-check only; the reported figure is the district-string one.

| # | City-group | City-proper count | Metro count | Exact district string(s) matched (StateName / District) | Prefix x-check |
|---|---|---|---|---|---|
| 1 | **Bengaluru** | **117** (Bangalore Urban) | **131** (+Rural) | `KARNATAKA / BENGALURU URBAN` (117); +`KARNATAKA / BENGALURU RURAL` (20) | 560 → 109; 560+562 → 147 |
| 2 | **Surat** | **79** | — | `GUJARAT / SURAT` | 394+395 → 101 |
| 3 | **Ahmedabad** | **81** | — | `GUJARAT / AHMADABAD` (note spelling: AHM**A**DABAD) | 380+382 → 115 |
| 4 | **Hyderabad** | **60** (Hyderabad dist.) | **140** (metro) | `TELANGANA / HYDERABAD` (60); metro +`MEDCHAL MALKAJGIRI` (33) +`RANGA REDDY` (55) | 500 → 110; 500+501+502 → 214 |
| 5 | **Chennai** | **83** (Chennai dist.) | **214** (metro) | `TAMIL NADU / CHENNAI` (83); metro +`THIRUVALLUR` (60) +`KANCHIPURAM` (31) +`CHENGALPATTU` (60) | 600 → 119; 600–603 → 185 |
| 6 | **Mumbai** | **89** (City+Suburban) | = 89 | `MAHARASHTRA / MUMBAI` (33, City dist.) + `MAHARASHTRA / MUMBAI SUBURBAN` (57) | 400 → 111 |
| 7 | **Delhi** | **97** (entire NCT) | = 97 | all 11 NCT districts: `DELHI /` CENTRAL, EAST, NEW DELHI, NORTH, NORTH EAST, NORTH WEST, SHAHDARA, SOUTH, SOUTH EAST, SOUTH WEST, WEST | 110 → **97 (exact match)** |
| 8 | **Chandigarh** | **25** (UT) | **66** (tricity) | `CHANDIGARH / CHANDIGARH` (25); tricity +`PUNJAB / S.A.S NAGAR` (Mohali, 22) +`HARYANA / PANCHKULA` (19) | 160 → 31; 160+140+134 → 102 |
| 9 | **Kolkata** | **74** (Kolkata dist.) | **332** (metro) | `WEST BENGAL / KOLKATA` (74); metro +`24 PARAGANAS NORTH` (144) +`24 PARAGANAS SOUTH` (67) +`HOWRAH` (55) | 700 → 162; 700+711+743 → 329 |
| 10 | **NCR four towns** | per-town ↓ | **97** combined | see per-town rows below | 122+121+201+245 → 105 |
| 10a | — Gurugram | **29** | — | `HARYANA / GURUGRAM` (spelling: not "Gurgaon") | 122 → 34 |
| 10b | — Faridabad | **15** | — | `HARYANA / FARIDABAD` | 121 → 20 |
| 10c | — Noida (Gautam Buddh Nagar) | **28** | — | `UTTAR PRADESH / GAUTAM BUDDHA NAGAR` (spelling: GAUTAM BUDDH**A** NAGAR) | 201 → 43 |
| 10d | — Ghaziabad | **26** | — | `UTTAR PRADESH / GHAZIABAD` | 201+245 → 51 |
| 11 | **Pune** | **145** (Pune dist.) | = 145 | `MAHARASHTRA / PUNE` (single district = city + PCMC + rural) | 411+412 → 113 |
| 12 | **Jaipur** | **84** | — | `RAJASTHAN / JAIPUR` (single district; no separate Jaipur-Rural in this vintage) | 302+303 → 105 |

**NCR four-towns combined = 97 distinct** (naive sum 29+15+28+26 = 98; the union is 97 because exactly **one** pincode is shared between Gautam Buddha Nagar and Ghaziabad on the 201xxx boundary — proof that the union method matters).

---

## Methodology

**How "city" was defined.** Each city-group is defined by India Post **District** strings within the correct **StateName**, because PIN prefixes are not 1:1 with cities (e.g. 500xxx covers Hyderabad + Rangareddy + Medchal jointly; 700xxx covers Kolkata + both 24-Parganas + Howrah). The District field is therefore the precise instrument and the prefix is only a sanity check.

**Distinct, union, not sum.** For every group the count is `len(set of distinct 6-digit pincodes)`. Multi-district metros use the **union** of the per-district pincode sets, so a pincode straddling two districts is counted once (this is why Delhi NCT = 97 distinct even though its 11 districts sum to 125 records-with-repeats, and why NCR four towns = 97 not 98).

**District-string spelling variants explicitly matched** (the directory's spelling, in CAPS, is on the right):
- Bengaluru → `BENGALURU URBAN` / `BENGALURU RURAL` (not "Bangalore").
- Ahmedabad → `AHMADABAD` (A-H-M-**A**-D-A-B-A-D).
- Gurugram → `GURUGRAM` (not "Gurgaon").
- Noida → `GAUTAM BUDDHA NAGAR` (GAUTAM BUDDH**A** NAGAR, not "Gautam Buddh Nagar" / "Gautambudh").
- Mohali → `S.A.S NAGAR` (Sahibzada Ajit Singh Nagar) in Punjab.
- Hyderabad metro → `MEDCHAL MALKAJGIRI` and `RANGA REDDY` (two words).
- Kolkata 24-Parganas → `24 PARAGANAS NORTH` / `24 PARAGANAS SOUTH` (directory uses "PARAGANAS", number-first ordering — NOT "North 24 Parganas").
- Chennai metro → `THIRUVALLUR` (TH-, not "Tiruvallur"), `KANCHIPURAM` (not "Kancheepuram"), `CHENGALPATTU`.

**Rows excluded.** Only rows whose Pincode is a clean 6-digit numeric string are counted (0 rows were dropped — every one of the 157,126 records had a valid 6-digit pincode). No OfficeType/Delivery filtering was applied; PO-box and non-delivery offices keep the same pincodes as their parent area, so they do not change the distinct-pincode totals.

---

## Cross-check (independent web sources — sanity only)

| Check | Directory-computed | Independent web source | Verdict |
|---|---|---|---|
| **National total** | 19,300 pincodes / 157,126 post offices | Multiple sources cite **19,300 pincodes and 1,57,126 post offices as of June 2024** (Wikipedia "Postal Index Number"; data.gov.in resource page) | ✅ Exact match — confirms vintage = June 2024 and that the file is complete |
| **Delhi (NCT)** | 97 | "Delhi has a total of **97** pin codes grouped by its 11 districts" (findpincode.net / Delhi NCT references) | ✅ Exact match (97 = 97) |
| **Bengaluru (Urban)** | 117 | Published references cite ~**118** unique pincodes for Bangalore (checkpincodes / pincode aggregators) | ✅ Within 1 — agrees |
| **Mumbai** | 89 (City+Suburban) | "Mumbai (City) district 400001–400104, ~37 unique" for the island-city district only; greater Mumbai spans City + Suburban | ✅ Consistent — my 89 = full City+Suburban municipal area; the ~37 figure is the southern Mumbai-City district alone (directory shows MUMBAI City dist. = 33) |

All four agree. Where a web source quotes a smaller number, it is using a narrower district scope (e.g. Mumbai-City-only, Bangalore-Urban-only) — the directory-computed figure here is the one to use because its scope is stated explicitly.

---

## Caveats

- **PO-count vs PIN-count.** 157,126 is the number of post-office *records*; 19,300 is the number of distinct *pincodes*. Many post offices share a pincode. Do not report 157,126 (or ~155k) as "pincodes" — that is the common error.
- **Pincodes straddle district borders.** A single 6-digit pincode can appear in records tagged to two different districts (e.g. one 201xxx code spans Gautam Buddha Nagar and Ghaziabad). City counts therefore use distinct-set **unions**, and city numbers across adjacent districts will not be additive. This is intrinsic to India's pincode geography, not a data error.
- **Prefix ≠ district.** PIN prefixes are coarser than districts in dense metros (500xxx = all of Hyderabad+Rangareddy+Medchal; 700xxx = Kolkata+both 24-Parganas+Howrah), so the "prefix x-check" column will diverge from the district count — that is expected; the district-string count is authoritative.
- **Single-district cities.** Pune and Jaipur are each a single India Post district that bundles the core city, suburbs (PCMC for Pune) and surrounding rural blocks; there is no separate "city-proper" district to isolate, so the district number (145 / 84) is both the city and metro figure. Jaipur's later (2023) Jaipur/Jaipur-Rural administrative split is **not** reflected in this postal-directory vintage.
- **Dataset staleness.** Vintage ≈ June 2024. India Post adds/retires pincodes occasionally; the absolute national total drifts by a few dozen per year (~19,1xx in earlier years → 19,300 here). Recompute from a fresher directory pull if exactness beyond mid-2024 is needed.
- **Not JIVO coverage.** These are the FULL India PIN universe counts, unrelated to JIVO's serviceable/coverage pincode lists.

---

## Reproducibility

Compute scripts:
- `/opt/ecom-intel/docs/pincodes/compute_25_cities.py` — the **25-city target list** (this is the primary one)
- `/opt/ecom-intel/docs/pincodes/compute_pincodes.py` — national total + original 12 city-groups
Data file: `/opt/ecom-intel/docs/pincodes/drr_pincode.csv`

```bash
# 1. Download the canonical directory mirror
curl -L -o drr_pincode.csv \
  https://raw.githubusercontent.com/dropdevrahul/pincodes-india/main/pincode.csv

# 2a. Recompute the 25-city target list + distinct-union total
python3 /opt/ecom-intel/docs/pincodes/compute_25_cities.py drr_pincode.csv

# 2b. Recompute national total + original 12 city-groups
python3 /opt/ecom-intel/docs/pincodes/compute_pincodes.py drr_pincode.csv
```

The script counts distinct 6-digit pincodes nationally, then per city-group it
unions the distinct-pincode sets over the exact `(StateName, District)` strings
listed in the table above and prints a prefix cross-check for each. No secrets,
no external API keys; uses only the Python standard library (`csv`).
