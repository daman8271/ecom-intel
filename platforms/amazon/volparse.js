// ---------------------------------------------------------------------------
// parseVolMl — total volume (ml) of a pack string, summing ADDITIVE combos.
//
// ROOT-FIX (2026-06-05): the previous parser read only the FIRST volume token,
// so additive bundles ("5LTR + 1LTR", "5 + 1 LTR", "200 ML + 5LTR (BUNDLE)")
// got a partial denominator -> per_litre inflated 1.2x-26x on ~93 oil SKUs.
// Now we split on '+', parse every component, inherit a missing unit from a
// sibling component that has one ("5 + 1 LTR" => 5L + 1L), keep the "N x M"
// multiplicative case, and SUM. If NO component carries a unit anywhere
// ("5 + 1 EV") we still return null rather than guess.
//
// MIXED-BUNDLE FIX (2026-06-06): a pack that mixes a true VOLUME component with
// a WEIGHT component ("1LTR + 200 GM (BUNDLE)" = 1L oil + 200g seed freebie) is
// an oil + non-oil combo — the grams are NOT oil volume (the old code summed
// them g≈ml -> 1200ml, inflating the denominator's meaning and tripping
// review.py's per_litre_sanity). Catalog agrees: those ASINs carry uom=LTR,
// per_unit_value=1. Now we count ONLY the volume components in a mixed pack
// (vol_ml = oil volume, per_litre = sale ÷ oil litres). Weight-ONLY packs
// ("200 GMS", "800 GMS", "250 GMS X 2") keep the historical g≈ml behavior
// unchanged. A bare number inside a mixed pack is ambiguous (litres or grams?)
// -> whole parse returns null (fail-safe, never a confident wrong number).
// Pure function — unit-tested offline (test_volparse.js); no network/account.
// ---------------------------------------------------------------------------
const UNIT = 'ml|mls|l|ltr|ltrs|litre|litres|kg|gms?|g';
const isLitreClass = (u) => /^(l|ltr|ltrs|litre|litres|kg)$/.test(u);
const isWeightClass = (u) => /^(kg|gms?|g)$/.test(u);
const toMl = (n, u) => (isLitreClass(u) ? n * 1000 : n);

// Parse a single additive component. Returns one of:
//   { ml }            -> resolved volume (component carried its own unit)
//   { num }           -> a bare leading number, unit unknown (inherit later)
//   null              -> no number at all
function parseComponent(comp) {
  comp = comp.trim();
  if (!comp) return null;
  // multiplicative: "N x M unit"  (e.g. "5 x 200ml" -> 1000)
  const mult = comp.match(new RegExp('([\\d.]+)\\s*x\\s*([\\d.]+)\\s*(' + UNIT + ')\\b'));
  if (mult) return { ml: parseFloat(mult[1]) * toMl(parseFloat(mult[2]), mult[3]), unit: mult[3] };
  // number immediately followed by a unit (e.g. "5ltr", "200 ml", "50 gms")
  const m = comp.match(new RegExp('([\\d.]+)\\s*(' + UNIT + ')\\b'));
  if (m) return { ml: toMl(parseFloat(m[1]), m[2]), unit: m[2] };
  // bare leading number with no/none-unit suffix (e.g. "5", "1 ev") -> inherit
  const bare = comp.match(/^([\d.]+)\b/);
  if (bare) return { num: parseFloat(bare[1]) };
  return null;
}

function parseVolMl(pack) {
  if (!pack) return null;
  const p = String(pack).toLowerCase().replace(/\(.*?\)/g, ' '); // drop "(bundle)", "(pack of 2)"
  let comps = p.split('+').map(parseComponent).filter(Boolean);
  if (!comps.length) return null;

  // MIXED volume+weight bundle (oil + non-oil freebie): keep ONLY the volume
  // components — grams/kg of seeds/atta are not oil volume. Weight-only packs
  // fall through unchanged (historical g≈ml). A bare number alongside the mix
  // is ambiguous -> null (fail-safe).
  const hasVolume = comps.some((c) => c.unit && !isWeightClass(c.unit));
  const hasWeight = comps.some((c) => c.unit && isWeightClass(c.unit));
  if (hasVolume && hasWeight) {
    if (comps.some((c) => c.ml == null && c.num != null)) return null;
    comps = comps.filter((c) => !(c.unit && isWeightClass(c.unit)));
  }

  // the unit to lend to bare-number components: the first explicit unit seen.
  const lend = comps.find((c) => c.unit);
  let total = 0;
  let any = false;
  for (const c of comps) {
    if (c.ml != null) { total += c.ml; any = true; }
    else if (c.num != null && lend) { total += toMl(c.num, lend.unit); any = true; }
    // bare number with NO unit anywhere in the pack -> cannot trust -> skip,
    // and (below) the whole parse returns null so we never publish a partial.
    else if (c.num != null && !lend) { return null; }
  }
  return any ? total : null;
}

module.exports = { parseVolMl };
