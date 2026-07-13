#!/usr/bin/env python3
"""Select three live Blinkit pincodes for each top-8 report city."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path("/opt/ecom-intel")
IST = dt.timezone(dt.timedelta(hours=5, minutes=30))


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def captured_ist_date(value: Any) -> str:
    parsed = dt.datetime.fromisoformat(str(value or "").replace("Z", "+00:00"))
    return parsed.astimezone(IST).date().isoformat()


def pin(value: Any) -> str:
    return str(value or "").strip()


def live(rec: dict[str, Any]) -> bool:
    return bool(
        rec.get("resolved")
        and rec.get("auth_accepted") == 1
        and not rec.get("blocked")
        and not rec.get("partial_block")
    )


def distance_sq(a: dict[str, Any], b: dict[str, Any]) -> float:
    try:
        lat1, lon1 = float(a["lat"]), float(a["lon"])
        lat2, lon2 = float(b["lat"]), float(b["lon"])
    except (KeyError, TypeError, ValueError):
        return 0.0
    mean_lat = math.radians((lat1 + lat2) / 2)
    return (lat1 - lat2) ** 2 + ((lon1 - lon2) * math.cos(mean_lat)) ** 2


def choose_fallback(
    candidates: list[dict[str, Any]],
    chosen: list[dict[str, Any]],
    result_by_pin: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    chosen_stores = {
        str(result_by_pin[pin(row["pincode"])].get("store_id") or "")
        for row in chosen
    }

    def score(row: dict[str, Any]) -> tuple[int, float, str]:
        result = result_by_pin[pin(row["pincode"])]
        store = str(result.get("store_id") or "")
        unique_store = int(bool(store) and store not in chosen_stores)
        spread = min((distance_sq(row, item) for item in chosen), default=0.0)
        return unique_store, spread, pin(row["pincode"])

    return max(candidates, key=score)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", required=True)
    parser.add_argument(
        "--preferred",
        type=Path,
        default=ROOT / "tools/competitor/blinkit_top8_pincodes.json",
    )
    parser.add_argument(
        "--daily",
        type=Path,
        default=ROOT / "platforms/blinkit/pincodes.daily.json",
    )
    parser.add_argument(
        "--result",
        type=Path,
        default=ROOT / "platforms/blinkit/result.json",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--audit", type=Path)
    args = parser.parse_args()

    preferred = read_json(args.preferred)
    daily = read_json(args.daily)
    result = read_json(args.result)
    if not isinstance(preferred, list) or not isinstance(daily, list):
        raise SystemExit("pincode inputs must be JSON lists")

    summary = result.get("summary") or {}
    if captured_ist_date(summary.get("captured_at")) != args.date:
        raise SystemExit(
            f"Blinkit result is not from {args.date}: {summary.get('captured_at')}"
        )
    if summary.get("auth_verified") != 1:
        raise SystemExit("Blinkit result did not pass authenticated-session verification")

    daily_by_pin = {pin(row.get("pincode")): row for row in daily}
    result_by_pin = {
        pin(row.get("pincode")): row for row in (result.get("perPin") or [])
    }
    preferred_cities: list[str] = []
    preferred_by_city: dict[str, list[str]] = {}
    for row in preferred:
        city = str(row.get("city") or "").strip()
        pincode = pin(row.get("pincode"))
        if not city or not pincode:
            raise SystemExit("preferred pincode config has a blank city or pincode")
        if city not in preferred_by_city:
            preferred_cities.append(city)
            preferred_by_city[city] = []
        preferred_by_city[city].append(pincode)
    if len(preferred_cities) != 25:
        raise SystemExit(f"expected 25 preferred cities, found {len(preferred_cities)}")

    selected: list[dict[str, Any]] = []
    replacements: list[dict[str, str]] = []
    for city in preferred_cities:
        candidates = [
            row
            for row in daily
            if str(row.get("city") or "").strip() == city
            and pin(row.get("pincode")) in result_by_pin
            and live(result_by_pin[pin(row.get("pincode"))])
        ]
        candidate_by_pin = {pin(row.get("pincode")): row for row in candidates}
        chosen: list[dict[str, Any]] = []
        for preferred_pin in preferred_by_city[city]:
            if preferred_pin in candidate_by_pin and len(chosen) < 3:
                chosen.append(candidate_by_pin.pop(preferred_pin))
        while len(chosen) < 3 and candidate_by_pin:
            replacement = choose_fallback(
                list(candidate_by_pin.values()), chosen, result_by_pin
            )
            candidate_by_pin.pop(pin(replacement["pincode"]))
            chosen.append(replacement)
        if len(chosen) != 3:
            raise SystemExit(
                f"{city}: only {len(chosen)} authenticated/resolved pincodes available"
            )

        original = preferred_by_city[city]
        chosen_pins = [pin(row["pincode"]) for row in chosen]
        for old in original:
            if old not in chosen_pins:
                new = next((value for value in chosen_pins if value not in original), "")
                replacements.append({"city": city, "from": old, "to": new})
        for index, row in enumerate(chosen, 1):
            current = dict(daily_by_pin[pin(row["pincode"])])
            current["competitor_sample_index"] = index
            selected.append(current)

    pins = [pin(row["pincode"]) for row in selected]
    if len(selected) != 75 or len(set(pins)) != 75:
        raise SystemExit("selection gate failed: expected 75 unique pincodes")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(selected, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    audit = {
        "date": args.date,
        "cities": 25,
        "pincodes": 75,
        "pincodes_per_city": 3,
        "preferred_source": str(args.preferred),
        "daily_source": str(args.daily),
        "result_source": str(args.result),
        "replacements": replacements,
        "selection": {
            city: [
                pin(row["pincode"])
                for row in selected
                if str(row.get("city") or "").strip() == city
            ]
            for city in preferred_cities
        },
    }
    if args.audit:
        args.audit.write_text(
            json.dumps(audit, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    print(json.dumps(audit, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
