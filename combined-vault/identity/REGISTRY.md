---
type: identity-registry
tags:
  - type/identity-registry
---

# JIVO Data Bank — Internal Product ID Registry (JID)

Up: [[Home]]

> **Our own serial identity.** Every physical product gets ONE opaque, immutable internal ID (`JID-####`) that we control — independent of the names it wears in price-match, the ecom app, or the factory SAP master. Match a product across any of those systems via its SAP code(s) or ecom canonical listing(s) below. Source of truth: `bin/jid_registry.json` (append-only). Stamped onto every product page's frontmatter (`jid:`) and Identity table.

- **Active products:** 151
- **Retired/merged JIDs (kept, never reused):** 0
- **Highest serial minted:** JID-0151
- **Identity conflicts to review:** 14
- **Generated:** 2026-07-17T05:16:41.087306+00:00

## Registry — JID ↔ product ↔ external keys
| JID | Product (our canonical) | SAP code(s) — app/factory | Ecom canonical listing(s) | Category | Tier |
|---|---|---|---|---|---|
| `JID-0001` | [[CANOLA 5L]] | `FG0000004`, `FG0000118`, `SL0000018` | `jivo-canola-cold-pressed-edible-oil-5-litres-cooking-oil-for-daily-use-ideal-for-roasting-frying-baking-all-types-of-cuisines-cold-pressed-oil-for-cooking-5l`, `edoftx47swwqprvs`, `jivo-cold-pressed-canola-oil-5-litre-5l` … +3 | CANOLA | PREMIUM |
| `JID-0002` | [[EXTRA LIGHT 1L]] | `FG0000005` | `jivo-extra-light-olive-oil-1-litre-imported-from-spain-everyday-cooking-dressings-salad-soups-dips-and-marinades-all-culinary-uses-light-flavorful-high-mufa-rich-in-antioxidants-1l`, `edoge5whzbgw4ska`, `jivo-extra-light-olive-oil-1-litre-1l` … +2 | OLIVE | PREMIUM |
| `JID-0003` | [[JIVO POMACE 5L]] | `FG0000008` | `jivo-pomace-olive-oil-5-litre-tin-for-everyday-cooking-imported-from-spain-recommended-for-roasting-frying-and-baking-all-types-of-cuisines-rich-in-mufa-low-in-saturated-fat-5l`, `edoge5xhfzn2hz9d`, `jivo-pomace-olive-oil-5-litre-tin-for-everyday-cooking-5l` … +2 | OLIVE | PREMIUM |
| `JID-0004` | [[EXTRA LIGHT 5L]] | `FG0000009` | `jivo-extra-light-olive-oil-5-litre-tin-imported-from-spain-recommendable-daily-cooking-for-roasting-frying-baking-all-type-of-cuisines-low-saturated-fat-low-saturated-fat-5l`, `edofzfufcqdjhtqf` | OLIVE | PREMIUM |
| `JID-0005` | [[MUSTARD 5L]] | `FG0000011` | `jivo-premium-cold-pressed-kachi-ghani-mustard-oil-5-litre-contains-omega3-and-vitamin-e-ideal-for-cooking-frying-pickling-daily-use-5l`, `edoh9phgzg9h4gvt`, `jivo-premium-cold-pressed-kachi-ghani-mustard-oil-5-litre-5l` … +4 | MUSTARD | COMMODITY |
| `JID-0006` | [[CANOLA 15L]] | `FG0000015` | `jivo-canola-cold-press-oilcooking-oil-15-ltr-cooking-oil-for-daily-use-recommended-by-indian-medical-association-15l`, `jivo-refine-canola-oil-tin-15l` | CANOLA | PREMIUM |
| `JID-0007` | [[CANOLA 5+1L]] | `FG0000018`, `SL0000243` | `edofrwtzzubgdj3q`, `jivo-canola-cold-pressed-edible-oil-5-litres-with-1-litre-5l`, `jivo-canola-cold-press-oilhealthiest-cooking-oil-5-ltr-jivo-canola-oil1-litre-cold-press-healthy-cooking-oil-5l` … +6 | CANOLA | PREMIUM |
| `JID-0008` | [[CANOLA 1L POUCH]] | `FG0000021` | `jivo-canola-oil1-litre-refined-pouch-cooking-oil-for-daily-use-recommended-by-indian-medical-association-1l`, `canola-omega3-rich-cooking-oil-1-l-1l` | CANOLA | PREMIUM |
| `JID-0009` | [[CANOLA 2L]] | `FG0000022` | `jivo-canola-oil2-litre-cold-press-cooking-oil-for-daily-use-2l`, `jivo-canola-oil2-litre-cold-press-cooking-oil-for-daily-use-recommended-by-indian-medical-association-2l` | CANOLA | PREMIUM |
| `JID-0010` | [[JIVO POMACE 1L]] | `FG0000028` | `jivo-daily-cooking-pomace-olive-oil-1-litre-imported-from-spain-rich-in-monounsaturated-fatty-acids-low-in-saturated-fat-ideal-for-roasting-frying-and-baking-1l`, `edohyrptdvezvz8e`, `jivo-daily-cooking-pomace-olive-oil-1-litre-1l` … +3 | OLIVE | PREMIUM |
| `JID-0011` | [[MUSTARD 1L]] | `FG0000030` | `jivo-cold-pressed-kachi-ghani-chemical-free-mustard-daily-cooking-oil-1-litre-recommended-for-roasting-frying-baking-all-type-of-cuisines-1l`, `edogdvwygjndyrqp`, `jivo-cold-pressed-kachi-ghani-chemical-free-mustard-daily-cooking-oil-1-litre-1l` … +4 | MUSTARD | COMMODITY |
| `JID-0012` | [[CANOLA 1L]] | `FG0000032` | `jivo-canola-cold-pressed-edible-oil-1-litre-cooking-oil-for-daily-use-ideal-for-roasting-frying-baking-all-types-of-cuisines-cold-pressed-oil-for-cooking-1l`, `edogdtnzgdahuduj`, `jivo-canola-cold-pressed-edible-oil-1-litre-cooking-oil-for-daily-use-ideal-for-roasting-frying-baking-all-types-of-cuisines-1l` … +3 | CANOLA | PREMIUM |
| `JID-0013` | [[MUSTARD 1+1L]] | `FG0000038`, `FG0000275` | `edoge62hwa7ufxhw`, `jivo-cold-pressed-kachi-ghani-chemical-free-mustard-daily-cooking-oil-1-litre-recommendable-for-roasting-frying-baking-all-type-of-cuisines-2l`, `edohysj8bzygcsbu` … +2 | MUSTARD | COMMODITY |
| `JID-0014` | [[EXTRA LIGHT 500ML]] | `FG0000039` | `jivo-extra-light-olive-oil-500ml-imported-from-spain-everyday-use-for-cooking-dressings-salad-soups-dips-and-marinades-light-flavorful-high-mufa-rich-in-antioxidants-500ml` | OLIVE | PREMIUM |
| `JID-0015` | [[EXTRA VIRGIN 1L]] | `FG0000042`, `FG0000071` | `jivo-extra-virgin-olive-oil-1-litre-imported-from-spain-contains-vitamin-e-low-in-saturated-fat-natural-cooking-oil-ideal-for-dressings-salad-and-soups-dips-marinades-1l`, `edog2nmeharedmz3`, `jivo-extra-virgin-olive-oil-1-litre-1l` … +2 | OLIVE | PREMIUM |
| `JID-0016` | [[CANOLA 1+1+1L]] | `FG0000043` | `edoghersuqwaau5s`, `jivo-canola-cold-press-edible-oil-ideal-for-roasting-frying-baking-all-type-of-cuisines-everyday-cooking-oil-for-daily-use-pack-of-3-1-litre-e-3l`, `jivo-canola-oil1-litre-cold-press-canola-cold-press-edible-oil-pack-of-2-1-litre-each-1l` … +3 | CANOLA | PREMIUM |
| `JID-0017` | [[SUNFLOWER 5L]] | `FG0000053`, `FG0000059` | `jivo-cold-pressed-unrefined-sunflower-oil-5-litres-chemicalfree-oil-for-cooking-ideal-for-roasting-frying-baking-and-all-types-of-cuisines-5l`, `edogdvfwgprvttms`, `jivo-cold-pressed-unrefined-sunflower-oil-5-litres-5l` … +2 | SUNFLOWER | COMMODITY |
| `JID-0018` | [[EXTRA LIGHT 2L]] | `FG0000064` | `jivo-extra-light-olive-oil-2-litre-imported-from-spain-everyday-cooking-dressings-salads-soups-dips-marinades-low-in-saturated-fat-olive-oil-in-convenient-pet-bottle-for-easy-pouring-2l`, `edoft6pr7qmyhgjh`, `jivo-extra-light-olive-oil-2-litre-2l` … +3 | OLIVE | PREMIUM |
| `JID-0019` | [[MUSTARD 3L]] | `FG0000067` | `jivo-premium-cold-pressed-kachi-ghani-mustard-oil-3-litre-contains-omega3-and-vitamin-e-ideal-for-cooking-frying-pickling-daily-use-3l`, `edogkc6kwybcnngh` | MUSTARD | COMMODITY |
| `JID-0020` | [[EXTRA VIRGIN 5L]] | `FG0000074` | `jivo-extra-virgin-olive-oil-5-litre-tin-imported-from-spain-contains-vitamin-e-low-in-saturated-fat-natural-and-cold-pressed-cooking-oil-ideal-for-dressings-salad-and-soups-dips-marinades-5l`, `edogdtxggcgfce88`, `jivo-extra-virgin-cooking-olive-oil-5l` | OLIVE | PREMIUM |
| `JID-0021` | [[EXTRA VIRGIN 1+1L]] | `FG0000075` | `edog2nmphjzh6gjc`, `jivo-extra-virgin-olive-oil-1-litre-contains-vitamin-e-low-in-saturated-fat-natural-cooking-oil-for-dressings-salad-and-soups-dips-marinades-pack-of-2-2l`, `qwrgemns9zpzgwjh` | OLIVE | PREMIUM |
| `JID-0022` | [[SUNFLOWER 1L]] | `FG0000081` | `jivo-cold-pressed-unrefined-sunflower-oil-1-litre-chemicalfree-oil-for-cooking-ideal-for-roasting-frying-baking-and-all-types-of-cuisines-1l`, `qwrgemp4hbfd4gf3`, `jivo-cold-pressed-unrefined-sunflower-oil-1-litre-1l-b0b4sjtnf2` … +4 | SUNFLOWER | COMMODITY |
| `JID-0023` | [[A2 GHEE 500G]] | `FG0000082` | `ghegeugzhghgf5xh`, `jivo-a2-ghee-500-ml-500ml`, `ghehhzbqjbnvzggq` … +2 | GHEE | PREMIUM |
| `JID-0024` | [[A2 GHEE 1L]] | `FG0000083` | `jivo-a2-cow-ghee-1-litre-traditional-bilona-method-prepared-from-a2-cow-milk-rich-aroma-and-distinct-flavour-for-diverse-culinary-applications-suitable-for-cooking-frying-baking-indian-recipes-1l`, `ghegeujjnscchwq9` | GHEE | PREMIUM |
| `JID-0025` | [[CANOLA 1+1L]] | `FG0000088`, `FG0000123`, `FG0000125` | `jivo-canola-cold-pressed-edible-oil-11-litres-cooking-oil-for-daily-use-ideal-for-roasting-frying-baking-all-types-of-cuisines-cold-pressed-oil-for-cooking-2l`, `edofrxtmjgae9dct`, `jivo-cold-press-combo-canola-oil-plastic-bottle-2l` … +6 | CANOLA | PREMIUM |
| `JID-0026` | [[MUSTARD 1L POUCH]] | `FG0000106` | `jivo-cold-pressed-kachi-ghani-chemical-free-mustard-daily-cooking-oil-1-litre-pouch-recommendable-for-roasting-frying-baking-all-type-of-cuisines-1l`, `jivo-cold-pressed-kachi-ghani-chemical-free-mustard-daily-cooking-oil-1-litre-pouch-1l` | MUSTARD | COMMODITY |
| `JID-0027` | [[SOYABEAN 1L POUCH]] | `FG0000109`, `FG0000194` | `jivo-soyabean-oil-pouch-1-litre-edible-cooking-oil-for-daily-use-ideal-for-roasting-frying-and-baking-high-in-omega3-and-low-in-saturated-fat-1l`, `jivo-soybean-oil-soyabean-oil-pouch-1l` | SOYABEAN | COMMODITY |
| `JID-0028` | [[EXTRA VIRGIN 250ML]] | `FG0000112` | `jivo-extra-virgin-olive-oil-250-ml-glass-bottle-imported-from-spain-contains-vitamin-e-low-in-saturated-fat-natural-and-cold-pressed-cooking-oil-for-dressings-salad-and-soups-dips-marinades-250ml`, `edoguy3fp4y3rvqm` | OLIVE | PREMIUM |
| `JID-0029` | [[JIVO POMACE 2L]] | `FG0000114` | `jivo-everyday-cooking-pomace-olive-oil-2-litre-imported-from-spain-rich-in-mufa-low-in-saturated-fat-ideal-for-frying-roasting-baking-cooking-oil-for-daily-use-2l`, `edogyzhgusaddg9b`, `jivo-daily-pomace-olive-oil-2l` … +1 | OLIVE | PREMIUM |
| `JID-0030` | [[COCONUT 1L]] | `FG0000116` | `jivo-pure-extra-virgin-coconut-oil-1-litre-nourishing-oil-bottle-for-skin-hair-growth-baby-massage-good-for-salad-dressing-zero-cholesterol-and-trans-fat-keto-diet-cooking-1l`, `edogpm99cpxseuyn`, `jivo-pure-extra-virgin-coconut-oil-1-litre-1l` | COCONUT | PREMIUM |
| `JID-0031` | [[GOLD 5L]] | `FG0000128` | `jivo-gold-refined-oil-perfect-blend-of-rice-bran-sunflower-oil-cooking-oil-rich-in-antioxidants-vitamins-pro-lifestyle-5l-family-pack-5l`, `edogrf8rmwnygjpe`, `jivo-gold-refined-oil-perfect-blend-of-rice-bran-sunflower-oil-5l` … +1 | BLENDED | COMMODITY |
| `JID-0032` | [[SUNFLOWER 2L]] | `FG0000133` | `edoge62esbtmbrgf`, `jivo-cold-pressed-chemical-free-sunflower-oil-for-roasting-frying-baking-all-types-of-cuisines-high-in-antioxidants-tasteful-and-healthy-2-litre-2l` | SUNFLOWER | COMMODITY |
| `JID-0033` | [[SANO CANOLA 1L]] | `FG0000134` | `sano-canola-oil-cooking-oil-for-daily-use-recommended-for-all-types-of-cuisines-ideal-for-conscious-cooking-1-liter-1l`, `edogvh5wwcxqnjhf` | CANOLA | PREMIUM |
| `JID-0034` | [[SANO CANOLA 5L]] | `FG0000135` | `sano-canola-cooking-oil-for-daily-use-recommended-for-all-types-of-cuisines-lowest-in-saturated-fat-content-ideal-for-healthconscious-cooking-5-litre-smart-cooking-choice-5l`, `edogw3gwc36phwky` | CANOLA | PREMIUM |
| `JID-0035` | [[SANO MUSTARD 1L]] | `FG0000136` | `sano-pure-fresh-kachi-ghani-mustard-oil-1-litre-pet-bottle-high-pungency-rich-in-omega3-100-natural-authentic-indian-cooking-oil-boosts-heart-health-1l` | MUSTARD | COMMODITY |
| `JID-0036` | [[SANO MUSTARD 5L]] | `FG0000137` | `sano-pure-and-aromatic-kachi-ghani-mustard-oil-5l-pet-bottle-100-natural-ideal-for-cooking-pickling-and-health-benefits-edible-oil-5l`, `edogqthv2rjybfr9` | MUSTARD | COMMODITY |
| `JID-0037` | [[SANO SUNFLOWER 1L]] | `FG0000138` | `sano-sunflower-oil-1-litre-pet-bottle-pure-nutrientrich-sunflower-cooking-oil-with-high-smoke-point-ideal-for-frying-sauting-and-baking-1l`, `edogqwu2jyazcgzm` | SUNFLOWER | COMMODITY |
| `JID-0038` | [[SANO SUNFLOWER 5L]] | `FG0000139` | `sano-sunflower-oil-5-ltr-pet-bottle-pure-nutrient-rich-cooking-oil-with-high-smoke-point-ideal-for-frying-sauting-and-baking-all-type-of-cuisines-5l` | SUNFLOWER | COMMODITY |
| `JID-0039` | [[SANO SOYABEAN 1L]] | `FG0000140` | `sano-soyabean-oil-1-ltr-pet-bottle-pure-natural-nutrientrich-cooking-oil-ideal-for-healthy-delights-in-cooking-frying-and-baking-perfect-for-indian-and-international-cuisines-1l` | SOYABEAN | COMMODITY |
| `JID-0040` | [[SANO SOYABEAN 5L]] | `FG0000141` | `sano-soybean-oil-5-ltr-pet-bottle-allnatural-nutrientrich-cooking-oil-with-a-high-omega3-content-and-a-low-saturated-fat-content-ideal-for-delicious-and-healthful-meals-5l` | SOYABEAN | COMMODITY |
| `JID-0041` | [[GROUNDNUT 1L]] | `FG0000142` | `jivo-groundnut-oil-1-litre-cold-pressed-unrefined-peanut-oil-for-cooking-vitamin-a-d-fortified-chemicalfree-ground-nut-oil-1l-1l`, `edogwf6ugcwrregz`, `jivo-cold-pressed-groundnut-oil-1-litre-1l` … +1 | GROUNDNUT | PREMIUM |
| `JID-0042` | [[GROUNDNUT 5L]] | `FG0000143` | `jivo-groundnut-oil-5-litre-cold-pressed-unrefined-peanut-oil-for-cooking-vitamin-a-d-fortified-chemicalfree-ground-nut-oil-5l`, `edoh9p7nnnjuxgzp`, `jivo-cold-pressed-groundnut-oil-5-litre-5l` | GROUNDNUT | PREMIUM |
| `JID-0043` | [[GOLD 1L]] | `FG0000149` | `jivo-gold-premium-refined-cooking-oil-perfect-blend-of-rice-bran-sunflower-oil-natural-antioxidants-1-litre-pack-1l`, `edogxyeferfxp3zy`, `jivo-gold-refined-oil-blend-of-rice-bran-oil-and-sunflower-oil-1l` | BLENDED | COMMODITY |
| `JID-0044` | [[SANO POMACE 1L]] | `FG0000150` | `sano-pomace-olive-oil-1l-pet-bottle-ideal-for-deep-frying-sauting-roasting-high-smoke-point-cooking-oil-for-indian-kitchen-1000ml-1l`, `edogrrxuhzzhz2wz` | OLIVE | PREMIUM |
| `JID-0045` | [[SANO POMACE 5L]] | `FG0000151` | `sano-pomace-olive-oil-5l-ideal-for-frying-roasting-sauting-rich-neutral-flavour-high-smoke-point-versatile-edible-cooking-oil-for-indian-cuisine-5l`, `edogrsy3tnxgejpj` | OLIVE | PREMIUM |
| `JID-0046` | [[SANO CLASSIC 5L]] | `FG0000152` | `sano-classic-olive-oil-5-litre-ideal-for-all-indian-and-western-cuisines-perfect-for-cooking-frying-roasting-grilling-and-baking-versatile-and-healthy-cooking-oil-5l`, `edohagdyvqwt6gng` | OTHER | OTHER |
| `JID-0047` | [[EXTRA VIRGIN 2L]] | `FG0000155` | `jivo-extra-virgin-olive-oil-2-litre-imported-from-spain-contains-vitamin-e-low-in-saturated-fat-natural-and-cold-pressed-cooking-oil-ideal-for-dressings-salad-and-soups-dips-marinades-2l`, `edog2nmphjzh6gjc` | OLIVE | PREMIUM |
| `JID-0048` | [[COCONUT 500ML]] | `FG0000157` | `jivo-pure-extra-virgin-coconut-oil-500-ml-nourishing-oil-bottle-for-skin-hair-growth-baby-massage-good-for-salad-dressing-zero-cholesterol-and-trans-fat-keto-diet-cooking-500ml`, `edohf5f6bs3mehjd`, `jivo-pure-extra-virgin-coconut-oil-500-ml-500ml` | COCONUT | PREMIUM |
| `JID-0049` | [[CANOLA 4L]] | `FG0000160` | `jivo-canola-cold-pressed-edible-oil-4-litres-cooking-oil-for-daily-use-ideal-for-roasting-frying-baking-all-types-of-cuisines-cold-pressed-oil-for-cooking-4l` | CANOLA | PREMIUM |
| `JID-0050` | [[EXTRA VIRGIN 500ML]] | `FG0000161` | `jivo-extra-virgin-olive-oil-500-ml-pet-bottle-imported-from-spain-contains-vitamin-e-low-in-saturated-fat-natural-and-cold-pressed-cooking-oil-for-dressings-salad-and-soups-dips-marinades-500ml`, `edogwgz7tq6zzt3h` | OLIVE | PREMIUM |
| `JID-0051` | [[SANO CLASSIC 1L]] | `FG0000162` | `sano-extra-light-olive-oil-1-litre-product-of-spain-ideal-for-all-indian-and-western-cuisines-perfect-for-cooking-frying-roasting-grilling-and-baking-versatile-and-smart-cooking-oil-1l`, `edogvef33gyxkhew` | OTHER | OTHER |
| `JID-0052` | [[COCONUT 200ML]] | `FG0000163` | `jivo-pure-extra-virgin-coconut-oil-200ml-nourishing-oil-bottle-for-skin-hair-growth-baby-massage-good-for-salad-dressing-zero-cholesterol-and-trans-fat-keto-diet-cooking-200ml` | COCONUT | PREMIUM |
| `JID-0053` | [[EXTRA VIRGIN 200ML]] | `FG0000164` | `jivo-extra-virgin-olive-oil-200-ml-pet-bottle-imported-from-spain-contains-vitamin-e-low-in-saturated-fat-natural-cooking-oil-ideal-use-for-dressings-salad-and-soups-dips-marinades-200ml`, `edohgpf2zq9rqpb3` | OLIVE | PREMIUM |
| `JID-0054` | [[CHIA SEEDS 200GM]] | `FG0000165` | `edsh4ygygrwrqrgk`, `jivo-premium-raw-chia-seeds-i-eating-seeds-for-weight-loss-management-rich-in-calcium-protein-fiber-omega-3-non-gmo-and-fibre-reusable-antioxidant-healthy-breakfast-snack-200g-200ml` | SEEDS | OTHER |
| `JID-0055` | [[CHIA SEEDS 400G]] | `FG0000166` | `jivo-premium-raw-chia-seeds-i-eating-seeds-for-weight-loss-management-rich-in-calcium-protein-fiber-omega-3-non-gmo-and-fibre-reusable-antioxidant-healthy-breakfast-snack-400g-400ml`, `edsgxe59s7agkhug` | SEEDS | OTHER |
| `JID-0056` | [[CHIASEEDS 800G]] | `FG0000167` | `edsh3fjv4pejdfan`, `jivo-premium-raw-chia-seeds-i-eating-seeds-for-weight-loss-management-rich-in-calcium-protein-fiber-omega-3-non-gmo-and-fibre-reusable-antioxidant-healthy-breakfast-snack-800g-800ml` | SEEDS | OTHER |
| `JID-0057` | [[FLAX SEEDS 200G]] | `FG0000179` | `jivo-flax-seeds-raw-alsi-seeds-for-eating-high-in-protein-iron-dietary-fibre-rich-in-essential-nutrients-ideal-for-adding-to-smoothies-salads-yogurt-baking-healthy-snack-option-200g-200ml`, `edsh4zgfwpsuy7rh` | SEEDS | OTHER |
| `JID-0058` | [[BASIL SEEDS 200 GM]] | `FG0000180` | `edsh4zf2vbebfjuq`, `jivo-raw-basil-seeds-for-weight-loss-200gm-200ml`, `jivo-raw-basil-seeds-for-weight-loss-200gm-sabja-seed-takmuria-seeds-200g-high-fibre-and-omega-3-200ml` | SEEDS | OTHER |
| `JID-0059` | [[SUNFLOWER SEEDS 200 GM]] | `FG0000181` | `edsh5avjzcsan5p3`, `jivo-sunflower-seeds-200g-raw-natural-sunflower-seeds-for-snacking-healthy-snack-option-ideal-for-weight-management-antioxidants-great-for-diets-nutrientrich-food-packed-with-protein-200ml`, `edsh5ynwyh26yy2g` | SEEDS | OTHER |
| `JID-0060` | [[PUMPKIN SEEDS 200G]] | `FG0000182` | `jivo-raw-pumpkin-seeds-healthy-snack-for-breakfast-high-in-fiber-antioxidants-ideal-for-diets-weight-management-nutritious-superfood-for-daily-wellness-hygienically-packed-200g-200ml`, `edsh5avcxwvgycyt` | SEEDS | OTHER |
| `JID-0061` | [[SOYABEAN 5L]] | `FG0000192` | `jivo-cooking-edible-soyabean-oil-5-litre-high-in-omega6-pufa-contains-tocopherols-natural-antioxidant-suitable-for-daily-cooking-5l`, `edoggf7edc9pffhh` | SOYABEAN | COMMODITY |
| `JID-0062` | [[SOYABEAN 1L]] | `FG0000193` | `jivo-cooking-edible-soyabean-oil-1-litre-high-in-omega6-pufa-contains-tocopherols-natural-antioxidant-suitable-for-daily-cooking-1l`, `jivo-cooking-edible-soyabean-oil-1-litre-1l` | SOYABEAN | COMMODITY |
| `JID-0063` | [[BLACK CARDAMOM 100G]] | `FG0000195` | `jivo-black-cardamom-badi-elaichi-sabut-moti-kali-elaichi-whole-organic-black-cardamom-perfect-for-cooking-baking-seasoning-adds-flavor-to-dishes-no-artificial-colours-or-preservatives-100g-100ml`, `scmh4h8hzj8ahq9g` | SPICES | OTHER |
| `JID-0064` | [[BLACK PEPPER 100G]] | `FG0000196` | `jivo-black-pepper-whole-natural-peppercorns-premium-kali-mirch-perfect-for-cooking-baking-seasoning-no-artificial-colors-preservatives-or-taste-enhancers-pepper-100g-100ml`, `scmh2hmc2u7pqmnv` | SPICES | OTHER |
| `JID-0065` | [[GREEN CARDAMOM 100G]] | `FG0000197` | `jivo-green-cardamom-8mm-elaichi-whole-natural-spices-no-artificial-colors-or-preservatives-distinctive-flavor-aroma-premium-idukki-cardamom-for-cooking-baking-tea-100g-100ml`, `scmh4h8nch2pkywv` | SPICES | OTHER |
| `JID-0066` | [[CINNAMON 100G]] | `FG0000198` | `scmh4h8snyfgcykm`, `jivo-organic-cinnamon-sticks-bark-finest-dalchini-sticks-whole-spices-sourced-from-premium-origins-no-artificial-colors-or-preservatives-pack-for-cooking-seasoning-100g-100ml` | SPICES | OTHER |
| `JID-0067` | [[CUMIN SEEDS 100G]] | `FG0000199` | `jivo-cumin-seeds-fresh-aromatic-natural-spice-for-cooking-no-added-colours-or-preservatives-perfect-for-baking-seasoning-and-flavoring-glutenfree-whole-jeera-seeds-100g-100ml`, `scmh3fhauzysnuab` | SEEDS | OTHER |
| `JID-0068` | [[RICE 1KG]] | `FG0000201` | `jivo-long-grain-basmati-rice-1kg-ideal-for-pulao-biryani-and-fried-rice-trusted-for-daily-use-jivo-basmati-rice-1-kg-per-packet-na`, `ricge89buedda5u7` | RICE | OTHER |
| `JID-0069` | [[SANO HONEY 1KG]] | `FG0000216` | `hnygqtuw5db6rxqd`, `sano-pure-honey-1-kg-100-natural-organic-unadulterated-no-sugar-adulteration-rich-in-antioxidants-healthy-sweetener-for-tea-desserts-syed-1-kg-na`, `hnyhyrsbgkzhhfdz` | HONEY | OTHER |
| `JID-0070` | [[SANO HONEY 500G]] | `FG0000217` | `hnygqtnabyzxtf6e`, `sano-pure-honey-500g-100-natural-organic-unadulterated-no-sugar-adulteration-rich-in-antioxidants-healthy-sweetener-for-tea-desserts-syed-500g-500ml`, `hnyhyrsyjpmyegux` | HONEY | OTHER |
| `JID-0071` | [[DESI GHEE 1KG]] | `FG0000223`, `SL0000089` | `ghegwgqh84yszn6f`, `jivo-desi-ghee-1-litre-traditional-preparation-from-desi-cow-milk-suitable-for-cooking-frying-baking-authentic-aroma-and-flavor-ideal-for-indian-and-continental-recipes-1l`, `gheh6b93zb66sekq` … +1 | GHEE | PREMIUM |
| `JID-0072` | [[WG MANGO JUICE 500ML]] | `FG0000226`, `FG0000279` | `jivo-healthy-wheatgrass-juice-with-mango-flavor-body-detox-immunity-booster-natural-ingredients-500ml-500ml`, `jivo-healthy-wheatgrass-juice-with-mango-flavor-500ml`, `mango-healthy-wheatgrass-juice-500ml` | DRINKS | OTHER |
| `JID-0073` | [[RICE BRAN 1L]] | `FG0000227` | `jivo-rice-bran-oil-1-litre-cooking-oil-rich-in-antioxidants-ideal-for-deep-frying-sauting-baking-chemicalfree-1l`, `edohf5ykx4kjregk`, `jivo-rice-bran-oil-1-litre-cooking-oil-1l` … +1 | RICE BRAN | COMMODITY |
| `JID-0074` | [[SO OLIVE 1L]] | `FG0000228` | `jivo-so-olive-oil-1-litre-blend-of-rice-bran-olive-oil-nutritious-cooking-oil-for-a-healthy-lifestyle-ideal-for-daily-use-edible-oil-1l`, `edoh5he7fczjwtaw`, `jivo-soolive-oil-1l-1l` … +1 | BLENDED | PREMIUM |
| `JID-0075` | [[SO OLIVE 5L]] | `FG0000229` | `jivo-so-olive-oil-5-litre-blend-of-rice-bran-olive-oil-nutritious-cooking-oil-for-a-healthy-lifestyle-ideal-for-daily-use-edible-oil-5l`, `edoh5hehthkwthyy` | BLENDED | PREMIUM |
| `JID-0076` | [[RICE BRAN 5L]] | `FG0000230` | `jivo-rice-bran-oil-5-litre-premium-cooking-oil-rich-in-antioxidants-ideal-for-deep-frying-sauteing-baking-chemicalfree-5l`, `edoh3yz46gfvhepb`, `jivo-rice-bran-oil-5-litre-5l` | RICE BRAN | COMMODITY |
| `JID-0077` | [[SODA LEMON 750ML]] | `FG0000231` | `jivo-fizzy-soda-flavoured-with-lemon-750ml-carbonated-water-zero-sugar-zero-calories-i-pack-of-1-750ml`, `fizzy-water-flavoured-with-lemon-750ml` | DRINKS | OTHER |
| `JID-0078` | [[BLUEBERRY 200ML]] | `FG0000232` | `blueberry-healthy-wheatgrass-juice-200ml`, `jivo-healthy-wheatgrass-juice-with-blue-berry-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml` | DRINKS | OTHER |
| `JID-0079` | [[ROSE FLAVOR 200ML]] | `FG0000234` | `jivo-healthy-wheatgrass-juice-with-rose-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml`, `rose-healthy-wheatgrass-juice-200ml` | DRINKS | OTHER |
| `JID-0080` | [[WG MANGO JUICE 200ML]] | `FG0000236`, `FG0000262` | `mango-healthy-wheatgrass-juice-200ml`, `jivo-healthy-wheatgrass-juice-with-mango-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml` | DRINKS | OTHER |
| `JID-0081` | [[GINGER ALE 200ML]] | `FG0000238` | `jivo-healthy-wheatgrass-body-detoxifying-immunity-booster-juice-sugar-free-200-ml-200ml` | DRINKS | OTHER |
| `JID-0082` | [[WG MOJITO 200ML]] | `FG0000244` | `mojito-healthy-wheatgrass-juice-200ml`, `jivo-healthy-wheatgrass-juice-with-mojito-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml`, `dajh7vuw7j7dzn7q` | DRINKS | OTHER |
| `JID-0083` | [[JEERA JUICE]] | `FG0000245` | `jivo-wheatgrass-punjabi-jeera-juice-160ml-tangy-cumin-flavored-refreshment-blended-with-fresh-wheatgrass-extract-convenient-pet-bottles-suitable-for-daily-hydration-refreshing-160ml` | DRINKS | OTHER |
| `JID-0084` | [[WG MOJITO SF 200ML]] | `FG0000250` | `mojito-healthy-wheatgrass-juice-sugar-free-200ml`, `jivo-healthy-wheatgrass-body-detoxifying-immunity-booster-juice-sugar-free-200ml-200ml` | DRINKS | OTHER |
| `JID-0085` | [[TONIC WATER 200ML]] | `FG0000252`, `FG0000264` | `indian-tonic-water-200ml`, `jivo-indian-citric-tonic-water-premium-gt-mixer-low-calorie-flavoured-drink-100-natural-ingredients-200ml` | DRINKS | OTHER |
| `JID-0086` | [[WG APPLE JUICE 200ML]] | `FG0000258`, `FG0000251` | `apple-healthy-wheatgrass-juice-200ml`, `dajh7wyzhzayakgn`, `jivo-healthy-wheatgrass-juice-with-apple-boosts-immunity-detox-200ml-200ml` | DRINKS | OTHER |
| `JID-0087` | [[WG BLUEBERRY JUICE 200ML]] | `FG0000260` | `blueberry-healthy-wheatgrass-juice-200ml`, `dajh7uwv7cnchsjb`, `jivo-healthy-wheatgrass-juice-with-blue-berry-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml` | DRINKS | OTHER |
| `JID-0088` | [[WG ROSE 200ML]] | `FG0000263` | `rose-healthy-wheatgrass-juice-200ml`, `jivo-healthy-wheatgrass-juice-with-rose-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml` | DRINKS | OTHER |
| `JID-0089` | [[WATER 1L]] | `FG0000266` | `jivo-natural-mineral-1l-1l`, `jivo-natural-minerals-water-mineral-water-1l`, `jivo-mineral-water-1l` | DRINKS | OTHER |
| `JID-0090` | [[JIVO WATER 250ML]] | `FG0000268` | `jivo-mineral-water-250ml-250ml` | DRINKS | OTHER |
| `JID-0091` | [[SODA PEACH 750ML]] | `FG0000270` | `fizzy-water-flavoured-with-peach-750ml`, `jivo-diet-fizzy-peach-natural-spring-water-peach-750ml-750ml` | DRINKS | OTHER |
| `JID-0092` | [[COFFEE]] | `FG0000271` | `jivo-koffie-instant-smooth-premium-coffee-100-gm-soluble-instant-coffee-powder-easy-to-prepare-with-rich-aroma-and-taste-coffee-for-daily-use-100ml`, `cfegmj5gje7hd3dq` | DRINKS | OTHER |
| `JID-0093` | [[WG GINGER ALE 200ML]] | `FG0000276` | `ginger-ale-healthy-wheatgrass-juice-sugar-free-200ml`, `jivo-healthy-wheatgrass-body-detoxifying-immunity-booster-juice-sugar-free-200-ml-200ml` | DRINKS | OTHER |
| `JID-0094` | [[WATER PEACH 750ML]] | `FG0000277` | `fizzy-water-flavoured-with-peach-750ml`, `jivo-diet-fizzy-peach-natural-spring-water-peach-750ml-750ml` | DRINKS | OTHER |
| `JID-0095` | [[LEMON 750ML]] | `FG0000278` | `fizzy-water-flavoured-with-lemon-750ml`, `jivo-fizzy-soda-flavoured-with-lemon-750ml-carbonated-water-zero-sugar-zero-calories-i-pack-of-1-750ml` | DRINKS | OTHER |
| `JID-0096` | [[SODA 750ML]] | `FG0000282` | `jivo-extra-fizzy-soda-750-ml-soda-750ml` | DRINKS | OTHER |
| `JID-0097` | [[BLACK OLIVE 470G]] | `FG0000288` | `jivo-black-sliced-olives-470g-finest-olives-from-egypt-evenly-cut-black-olive-slices-suitable-for-pizza-pasta-salads-wraps-ready-to-eat-snack-smart-choice-470ml` | SLICED OLIVE | PREMIUM |
| `JID-0098` | [[FLAX SEEDS 400 GM]] | `FG0000290` | `jivo-flax-seeds-raw-alsi-seeds-for-smoothies-hair-growth-baking-more-rich-in-omega3-fiber-protein-essential-nutrients-100-natural-vegan-glutenfree-for-optimal-health-400g-400ml`, `edsh5avfzrhq43rz` | SEEDS | OTHER |
| `JID-0099` | [[DRY FRUITS 200G]] | `FG0000291` | `jivo-dry-fruits-gift-box-200g-sbs-healthy-gift-hamper-for-every-occasion-diwali-gift-pack-for-family-friends-corporate-and-office-gifts-festive-celebration-combo-pack-200ml` | OTHER | OTHER |
| `JID-0100` | [[PUNJABI JEERA 160ML]] | `FG0000293` | `jivo-wheatgrass-punjabi-jeera-juice-160ml-tangy-cumin-flavored-refreshment-blended-with-fresh-wheatgrass-extract-convenient-pet-bottles-suitable-for-daily-hydration-refreshing-160ml` | DRINKS | OTHER |
| `JID-0101` | [[BASIL SEEDS 400G]] | `FG0000296` | `jivo-raw-basil-seeds-for-weight-loss-400gm-sabja-seed-takmuria-seeds-400g-high-fibre-and-omega-3-400ml` | SEEDS | OTHER |
| `JID-0102` | [[BASIL SEEDS 800 GM]] | `FG0000297` | `edsh4yk7vc4zcnpu`, `jivo-raw-basil-seeds-for-weight-loss-sabja-seeds-tukmaria-seeds-high-in-fiber-omega3-nutrients-ideal-for-smoothies-drinks-and-baking-100-natural-vegan-glutenfree-800g-800ml` | SEEDS | OTHER |
| `JID-0103` | [[FLAX SEEDS 800G]] | `FG0000298` | `jivo-organic-flax-seeds-raw-alsi-seeds-for-smoothies-cereals-baking-more-rich-in-omega3-fiber-protein-essential-nutrients-100-natural-vegan-glutenfree-for-optimal-health-800g-800ml`, `edsh5bx4umfr4xyf` | SEEDS | OTHER |
| `JID-0104` | [[PUMPKIN SEEDS 800 GM]] | `FG0000299` | `edsh4zzgcgcmyvfh`, `jivo-raw-pumpkin-seeds-healthy-snack-for-breakfast-high-in-fiber-antioxidants-ideal-for-diets-weight-management-nutritious-superfood-for-daily-wellness-hygienically-packed-800g-800ml` | SEEDS | OTHER |
| `JID-0105` | [[SUNFLOWER SEEDS 400G]] | `FG0000300` | `jivo-sunflower-seeds-raw-natural-sunflower-seeds-for-healthy-snacking-high-in-protein-fiber-antioxidants-ideal-for-weight-management-clean-eating-nutrientrich-diets-400g-400ml`, `edsh66rre84eyvhc` | SEEDS | OTHER |
| `JID-0106` | [[SUNFLOWER SEEDS 800G]] | `FG0000301` | `jivo-sunflower-seeds-raw-natural-sunflower-seeds-for-healthy-snacking-high-in-protein-fiber-antioxidants-ideal-for-weight-management-diets-clean-eating-glutenfree-nongmo-800g-800ml`, `edsh63q3yyywhmuh` | SEEDS | OTHER |
| `JID-0107` | [[MUSTARD 4L]] | `FG0000302` | `jivo-premium-cold-pressed-kachi-ghani-mustard-oil-4-litre-contains-omega3-and-vitamin-e-ideal-for-cooking-frying-pickling-daily-use-4l`, `edohgwu9wapbehwk`, `jivo-cold-pressed-pure-cooking-mustard-oil-can-4l` | MUSTARD | COMMODITY |
| `JID-0108` | [[SUNFLOWER 4L]] | `FG0000303` | `jivo-sunflower-oil-4-litres-pure-natural-oil-for-cooking-ideal-for-roasting-frying-baking-and-all-types-of-cuisines-sunflower-oil-4l`, `edohgwsvungy8y3m` | SUNFLOWER | COMMODITY |
| `JID-0109` | [[PUMPKIN SEEDS 400G]] | `FG0000306` | `jivo-raw-pumpkin-seeds-healthy-snack-for-breakfast-high-in-fiber-antioxidants-ideal-for-diets-weight-management-nutritious-superfood-for-daily-wellness-hygienically-packed-400g-400ml`, `edsh5avgyvmtpzec` | SEEDS | OTHER |
| `JID-0110` | [[CLOVE 100G]] | `FG0000308` | `jivo-whole-clove-100-gm-no-artificial-colours-or-preservatives-100ml`, `scmhckzekpqwve5v` | SPICES | OTHER |
| `JID-0111` | [[JUMP ENERGY DRINK 200ML]] | `FG0000309` | `jivo-jump-energy-drink-zero-sugar-200ml-200ml` | OTHER | OTHER |
| `JID-0112` | [[EXTRA LIGHT 1+1+1L]] | `FG0000310` | `edoge5wygyxcrrmf`, `jivo-extra-light-olive-oil-3-litre-imported-from-spain-recommended-for-daily-cooking-roasting-frying-baking-all-types-of-cuisines-low-in-3l`, `qwrgempjjgdryacc` … +1 | OLIVE | PREMIUM |
| `JID-0113` | [[JIVO POMACE 1+1+1L]] | `FG0000311` | `edogfyrutbcs6yhw`, `jivo-pomace-edible-olive-oil-cooking-daily-use-rich-in-mufa-low-in-saturated-fat-recommendable-for-roasting-frying-baking-all-type-of-cuisines-pet-bottles-3l`, `qwrgemrynag8t2fv` | OLIVE | PREMIUM |
| `JID-0114` | [[EXTRA LIGHT 1+1L]] | `FG0000313` | `jivo-extra-light-olive-oil-2-litre-imported-from-spain-everyday-cooking-dressings-salads-soups-dips-marinades-low-in-saturated-fat-olive-oil-in-convenient-pet-bottle-for-easy-pouring-2l`, `qwrggc46ukqkvces`, `jivo-extra-light-olive-oil-combo-2l` | OLIVE | PREMIUM |
| `JID-0115` | [[SUNFLOWER 3L]] | `FG0000316` | `jivo-cold-pressed-chemicalfree-sunflower-oil-3-litres-chemicalfree-oil-for-cooking-ideal-for-roasting-frying-baking-and-all-types-of-cuisines-sunflower-oil-3l`, `edoghzsebqyya6zw` | SUNFLOWER | COMMODITY |
| `JID-0116` | [[CANOLA 3L]] | `FG0000317` | `jivo-canola-cold-pressed-edible-oil-3-litres-cooking-oil-for-daily-use-ideal-for-roasting-frying-baking-all-types-of-cuisines-cold-pressed-oil-for-cooking-3l`, `edoghersuqwaau5s` | CANOLA | PREMIUM |
| `JID-0117` | [[JIVO POMACE 1+1L]] | `FG0000320` | `edogyzhgusaddg9b`, `jivo-pomace-olive-oil-1l-for-cooking-recommendable-for-roasting-dressings-salad-and-soups-dips-marinades-healthy-oil-for-daily-use-baking-all-type-of-cuisines-2l`, `jivo-pomace-olive-oil-combo-2l` … +4 | OLIVE | PREMIUM |
| `JID-0118` | [[GOLD 1+1]] | `FG0000321` | `jivo-gold-refined-oil-blend-of-rice-bran-oil-sunflower-oil-cooking-oil-pro-healthy-lifestyle-edible-oil-1-litre-pack-of-2-2l`, `edogyj7syy4h2mdh` | BLENDED | COMMODITY |
| `JID-0119` | [[ENERGY DRINK 200ML]] | `FG0000325` | `jivo-jump-energy-drink-zero-sugar-200ml-200ml` | OTHER | OTHER |
| `JID-0120` | [[YELLOW MUSTARD 1L]] | `FG0000328`, `FG0000329` | `jivo-first-pressed-yellow-mustard-oil-1-litre-pili-sarson-oil-for-cooking-chemicalfree-ideal-for-roasting-frying-baking-omega3-pufa-tocopherols-added-vitamins-a-d-for-diverse-cuisines-1l`, `edohdgdyauqswvqv`, `jivo-first-pressed-yellow-mustard-oil-1-litre-1l` | MUSTARD | PREMIUM |
| `JID-0121` | [[SANO POMACE 1+1L]] | `FG0000339`, `FG0000326` | `sano-pomace-olive-oil-1l-pet-bottle-ideal-for-frying-roasting-sauting-rich-flavour-high-smoke-point-versatile-cooking-oil-for-indian-cuisine-2l`, `sano-pomace-olive-oil-2l-pet-bottle-ideal-for-frying-roasting-sauteing-rich-flavour-high-smoke-point-versatile-cooking-edible-oil-for-indian-cuis-2l` | OLIVE | PREMIUM |
| `JID-0122` | [[SANO POMACE 1+1+1L]] | `FG0000340`, `FG0000327` | `edogtkkpp3twkysp` | OLIVE | PREMIUM |
| `JID-0123` | [[DESI GHEE 500GM]] | `FG0000352`, `SL0000090` | `ghegwgyyfw9edubs`, `jivo-desi-ghee-500-ml-500ml`, `jivo-desi-ghee-500-ml-traditional-preparation-from-desi-cow-milk-suitable-for-cooking-frying-baking-authentic-aroma-and-flavor-ideal-for-indian-and-continental-recipes-500ml` | GHEE | PREMIUM |
| `JID-0124` | [[WG BLUEBERRY 200ML]] | `FG0000363` | `blueberry-healthy-wheatgrass-juice-200ml`, `dajh7uwv7cnchsjb`, `jivo-healthy-wheatgrass-juice-with-blue-berry-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml` | DRINKS | OTHER |
| `JID-0125` | [[SAFFRON 1GMS]] | `FG0000367` | `jivo-pure-kashmiri-saffron-a-grade-kesar-rich-in-antioxidants-boosts-immunity-skin-glow-overall-wellness-1ml`, `scmhg4hdys45ycaz` | SPICES | OTHER |
| `JID-0126` | [[ROSEMARY LEAVES 150G]] | `FG0000371` | `jivo-rosemary-leaves-whole-natural-no-preservatives-or-additives-ideal-for-hair-growth-herbal-tea-seasoning-and-cooking-salvia-rosmarinus-150ml` | SPICES | OTHER |
| `JID-0127` | [[QUINOA SEEDS 400G]] | `FG0000372` | `jivo-premium-quinoa-gluten-free-glutenfree-saponin-free-high-protein-fiber-healthy-breakfast-diet-food-for-weight-management-100-wholegrain-cereal-quinoa-jar-400g-400ml` | SEEDS | OTHER |
| `JID-0128` | [[QUINOA SEEDS 200G]] | `FG0000373` | `jivo-premium-quinoa-gluten-free-glutenfree-saponin-free-high-protein-fiber-healthy-breakfast-diet-food-for-weight-management-100-wholegrain-cereal-quinoa-jar-200g-200ml` | SEEDS | OTHER |
| `JID-0129` | [[QUINOA SEEDS 800G]] | `FG0000374` | `jivo-premium-quinoa-gluten-free-glutenfree-saponin-free-high-protein-fiber-healthy-breakfast-diet-food-for-weight-management-100-wholegrain-cereal-quinoa-jar-800g-800ml` | SEEDS | OTHER |
| `JID-0130` | [[SESAME OIL 1L]] | `FG0000376` | `jivo-first-pressed-sesame-oil-1l-bottle-gingelly-oil-contains-mufa-and-omega6-pufa-natural-antioxidants-ideal-for-cooking-1l`, `edohdgcrehez8kpz` | SESAME OIL | PREMIUM |
| `JID-0131` | [[RICE BRAN 4L]] | `FG0000383` | `jivo-rice-bran-oil-4-litre-premium-cooking-oil-rich-in-antioxidants-ideal-for-deep-frying-sauteing-baking-chemicalfree-4l` | RICE BRAN | COMMODITY |
| `JID-0132` | [[YELLOW MUSTARD 5L]] | `FG0000385` | `jivo-first-pressed-yellow-mustard-oil-5-litre-pili-sarson-oil-for-cooking-chemicalfree-ideal-for-roasting-frying-baking-omega3-pufa-tocopherols-added-vitamins-a-d-for-diverse-cuisines-5l` | MUSTARD | PREMIUM |
| `JID-0133` | [[EXTRA LIGHT 3L]] | `FG0000390` | `jivo-extra-light-olive-oil-3-litre-imported-from-spain-recommended-for-daily-cooking-roasting-frying-baking-all-types-of-cuisines-low-in-saturated-fat-3l`, `edohzyysyez2yvtm` | OLIVE | PREMIUM |
| `JID-0134` | [[POMACE 3L]] | `FG0000392` | `jivo-everyday-cooking-pomace-olive-oil-3-litre-imported-from-spain-rich-in-mufa-low-in-saturated-fat-ideal-for-frying-roasting-baking-cooking-oil-for-daily-use-3l`, `edogfyrutbcs6yhw` | OLIVE | PREMIUM |
| `JID-0135` | [[GROUNDNUT 5+1L]] | `FG0000399` | `edogw6r828yya8xa`, `jivo-groundnut-oil-5-1-litre-cold-pressed-groundnut-oil-cold-pressed-oil-peanut-oil-ground-nut-oil-natural-cooking-oil-chemical-free-pack-6l`, `jivo-cold-pressed-groundnut-peanut-oil-51-litre-6l` | GROUNDNUT | PREMIUM |
| `JID-0136` | [[SESAME 1L + 1L]] | `FG0000410` | `jivo-first-pressed-sesame-oil-1l-bottle-gingelly-oil-contains-mufa-and-omega6-pufa-natural-antioxidants-ideal-for-cooking-2l` | SESAME OIL | PREMIUM |
| `JID-0137` | [[CANOLA 1L+MUSTARD 1L]] | `SL0000007` | `edoghesnhffugqb9`, `jivo-kachi-ghani-mustard-oil-cold-pressed-canola-oil-1l-each-1l`, `qwrgg9uacyscuxk9` … +1 | CANOLA | PREMIUM |
| `JID-0138` | [[CANOLA 5+2L]] | `SL0000012` | `qwrggbfmfwgwuwtj`, `jivo-canola-refined-edible-oils-52-ltr-7l`, `jivo-canola-refined-edible-oils-52-ltr-2l` | CANOLA | PREMIUM |
| `JID-0139` | [[CANOLA 5L + SOYABEAN 5L]] | `SL0000016` | `edoggx8c5qad2mpp`, `jivo-canola-cold-pressed-oil-5-litres-with-soyabean-edible-cooking-oil-5-litres-5l`, `jivo-canola-cold-pressed-oil-5-litres-with-soyabean-edible-cooking-oil-5-litres-high-in-omega6-pufa-with-natural-antioxidant-suitable-for-daily-cooking-roasting-frying-baking-all-types-of-cuisines-na` | CANOLA | PREMIUM |
| `JID-0140` | [[CANOLA 1L+SOYABEAN 1L+MUSTARD 1L]] | `SL0000212` | `edoggy5kcr8s7shk`, `qwrgjfz8m4eggs5f` | CANOLA | PREMIUM |
| `JID-0141` | [[CANOLA 5L+ SOYABEAN 1L]] | `SL0000213` | `edoggx6sqxczkd2y`, `jivo-cold-pressed-canola-oil-5l-soyabean-oil-1l-for-roasting-frying-baking-all-types-of-cuisines-5l`, `jivo-cold-pressed-canola-oil-5l-soyabean-oil-1l-for-roasting-frying-baking-all-types-of-cuisines-6l` | CANOLA | PREMIUM |
| `JID-0142` | [[CINNAMON BARK 100G]] | — | `jivo-organic-cinnamon-sticks-bark-finest-dalchini-sticks-whole-spices-sourced-from-premium-origins-no-artificial-colors-or-preservatives-pack-for-cooking-seasoning-100g-100ml`, `scmh4h8snyfgcykm` | SPICES | OTHER |
| `JID-0143` | [[EXTRA VIRGIN 3L]] | — | `jivo-extra-virgin-olive-oil-3-litre-imported-from-spain-contains-vitamin-e-low-in-saturated-fat-natural-and-cold-pressed-cooking-oil-ideal-for-dressings-salad-and-soups-dips-marinades-3l` | OLIVE | PREMIUM |
| `JID-0144` | [[JIVO PUNJABI SHIKANJI 160 MLS]] | — | `jivo-punjabi-shikanji-wheatgrass-juice-nimbu-shikanji-masala-drink-natural-summer-refreshment-160ml-160ml` | DRINKS | OTHER |
| `JID-0145` | [[JIVO WATER 500 MLS]] | — | `jivo-natural-mineral-water-himalayan-origin-nonro-unprocessed-noncarbonated-additivefree-packaged-water-for-clean-hydration-500-ml-bottle-500ml` | DRINKS | OTHER |
| `JID-0146` | [[RICE BRAN 1L + 1L]] | — | `edohbh2fp9es6gga` | RICE BRAN | COMMODITY |
| `JID-0147` | [[SO OLIVE 1L + 1L]] | — | `edohbh2urwdmhpxc` | OLIVE | PREMIUM |
| `JID-0148` | [[SOYABEAN 1L + 1L]] | — | `jivo-soyabean-cooking-oil-1-litre-bottles-pack-of-2-litres-ideal-for-roasting-frying-and-baking-healthy-cooking-oil-for-daily-use-pack-of-2-1l`, `edoggpfz2fcj6uws` | SOYABEAN | COMMODITY |
| `JID-0149` | [[SPRING WATER 750ML]] | — | `jivo-diet-fizzy-peach-natural-spring-water-peach-750ml-750ml`, `fizzy-water-flavoured-with-peach-750ml` | DRINKS | OTHER |
| `JID-0150` | [[SUNFLOWER 1L + 1L]] | — | `jivo-cold-pressed-chemical-free-sunflower-oil-1-litre-ideal-for-roasting-frying-baking-all-types-of-cuisines-healthy-cooking-oil-for-daily-use-pack-of-2-litres-2l` | SUNFLOWER | COMMODITY |
| `JID-0151` | [[YELLOW MUSTARD 1L + 1L]] | — | `edohnfqudf32jhzr` | MUSTARD | PREMIUM |

## ⚠ Identity Conflicts (same ecom listing on >1 product — needs human call)

Each cluster below shares one or more ecom canonical listings across different product nodes. Some are true duplicates (fold together via `name_overrides.json`); some are combo-vs-single packs that must stay separate (the shared canonical is mis-attached and should be removed from one side). **Not auto-resolved — your call.**

- **`JID-0016` ⟷ `JID-0116`** — [[CANOLA 1+1+1L]] · [[CANOLA 3L]]
  - _hint:_ combo-vs-single pack — likely DO NOT MERGE (distinct SKUs; a canonical is mis-attached)
  - _shared listing(s):_ `edoghersuqwaau5s`
- **`JID-0018` ⟷ `JID-0114`** — [[EXTRA LIGHT 2L]] · [[EXTRA LIGHT 1+1L]]
  - _hint:_ combo-vs-single pack — likely DO NOT MERGE (distinct SKUs; a canonical is mis-attached)
  - _shared listing(s):_ `jivo-extra-light-olive-oil-2-litre-imported-from-spain-everyday-cooking-dressings-salads-soups-dips-marinades-low-in-saturated-fat-olive-oil-in-convenient-pet-bottle-for-easy-pouring-2l`
- **`JID-0021` ⟷ `JID-0047`** — [[EXTRA VIRGIN 1+1L]] · [[EXTRA VIRGIN 2L]]
  - _hint:_ combo-vs-single pack — likely DO NOT MERGE (distinct SKUs; a canonical is mis-attached)
  - _shared listing(s):_ `edog2nmphjzh6gjc`
- **`JID-0029` ⟷ `JID-0117`** — [[JIVO POMACE 2L]] · [[JIVO POMACE 1+1L]]
  - _hint:_ combo-vs-single pack — likely DO NOT MERGE (distinct SKUs; a canonical is mis-attached)
  - _shared listing(s):_ `edogyzhgusaddg9b`
- **`JID-0066` ⟷ `JID-0142`** — [[CINNAMON 100G]] · [[CINNAMON BARK 100G]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `jivo-organic-cinnamon-sticks-bark-finest-dalchini-sticks-whole-spices-sourced-from-premium-origins-no-artificial-colors-or-preservatives-pack-for-cooking-seasoning-100g-100ml`, `scmh4h8snyfgcykm`
- **`JID-0077` ⟷ `JID-0095`** — [[SODA LEMON 750ML]] · [[LEMON 750ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `fizzy-water-flavoured-with-lemon-750ml`, `jivo-fizzy-soda-flavoured-with-lemon-750ml-carbonated-water-zero-sugar-zero-calories-i-pack-of-1-750ml`
- **`JID-0078` ⟷ `JID-0087` ⟷ `JID-0124`** — [[BLUEBERRY 200ML]] · [[WG BLUEBERRY JUICE 200ML]] · [[WG BLUEBERRY 200ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `blueberry-healthy-wheatgrass-juice-200ml`, `jivo-healthy-wheatgrass-juice-with-blue-berry-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml`
- **`JID-0079` ⟷ `JID-0088`** — [[ROSE FLAVOR 200ML]] · [[WG ROSE 200ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `jivo-healthy-wheatgrass-juice-with-rose-flavor-body-detox-immunity-booster-natural-ingredients-200ml-200ml`, `rose-healthy-wheatgrass-juice-200ml`
- **`JID-0081` ⟷ `JID-0093`** — [[GINGER ALE 200ML]] · [[WG GINGER ALE 200ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `jivo-healthy-wheatgrass-body-detoxifying-immunity-booster-juice-sugar-free-200-ml-200ml`
- **`JID-0083` ⟷ `JID-0100`** — [[JEERA JUICE]] · [[PUNJABI JEERA 160ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `jivo-wheatgrass-punjabi-jeera-juice-160ml-tangy-cumin-flavored-refreshment-blended-with-fresh-wheatgrass-extract-convenient-pet-bottles-suitable-for-daily-hydration-refreshing-160ml`
- **`JID-0087` ⟷ `JID-0124`** — [[WG BLUEBERRY JUICE 200ML]] · [[WG BLUEBERRY 200ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `dajh7uwv7cnchsjb`
- **`JID-0091` ⟷ `JID-0094` ⟷ `JID-0149`** — [[SODA PEACH 750ML]] · [[WATER PEACH 750ML]] · [[SPRING WATER 750ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `fizzy-water-flavoured-with-peach-750ml`, `jivo-diet-fizzy-peach-natural-spring-water-peach-750ml-750ml`
- **`JID-0111` ⟷ `JID-0119`** — [[JUMP ENERGY DRINK 200ML]] · [[ENERGY DRINK 200ML]]
  - _hint:_ name variant — likely same product, review then add to name_overrides.json
  - _shared listing(s):_ `jivo-jump-energy-drink-zero-sugar-200ml-200ml`
- **`JID-0113` ⟷ `JID-0134`** — [[JIVO POMACE 1+1+1L]] · [[POMACE 3L]]
  - _hint:_ combo-vs-single pack — likely DO NOT MERGE (distinct SKUs; a canonical is mis-attached)
  - _shared listing(s):_ `edogfyrutbcs6yhw`
