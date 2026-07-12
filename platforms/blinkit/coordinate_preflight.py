#!/usr/bin/env python3
"""Fail-closed validation for Blinkit's pincode coordinate configuration."""

import argparse
import json
import math
import statistics
import sys
from collections import Counter, defaultdict


INDIA_BBOX = (6.0, 38.5, 68.0, 98.0)


def distance_km(a, b):
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = (math.sin(dlat / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * 6371.0088 * math.asin(min(1.0, math.sqrt(h)))


def robust_center(points):
    center = (statistics.median(p[0] for p in points),
              statistics.median(p[1] for p in points))
    core = [p for p in points if distance_km(center, p) <= 300]
    if core:
        center = (statistics.median(p[0] for p in core),
                  statistics.median(p[1] for p in core))
    return center


def validate(records):
    issues = []
    warnings = []
    seen = Counter(str(r.get("pincode") or "") for r in records)
    duplicates = sorted(p for p, count in seen.items() if p and count > 1)
    if duplicates:
        issues.append({"code": "duplicate_pincodes", "count": len(duplicates),
                       "sample": duplicates[:10]})

    valid_by_city = defaultdict(list)
    parsed = []
    for index, rec in enumerate(records):
        pin = str(rec.get("pincode") or "")
        city = str(rec.get("city") or "").strip()
        try:
            lat, lon = float(rec.get("lat")), float(rec.get("lon"))
        except (TypeError, ValueError):
            issues.append({"code": "missing_coordinate", "index": index,
                           "city": city, "pincode": pin})
            continue
        if not (INDIA_BBOX[0] <= lat <= INDIA_BBOX[1]
                and INDIA_BBOX[2] <= lon <= INDIA_BBOX[3]):
            swap_hint = (INDIA_BBOX[0] <= lon <= INDIA_BBOX[1]
                         and INDIA_BBOX[2] <= lat <= INDIA_BBOX[3])
            issues.append({"code": "coordinate_outside_india", "city": city,
                           "pincode": pin, "lat": lat, "lon": lon,
                           "swap_hint": swap_hint})
            continue
        valid_by_city[city].append((lat, lon, pin))
        parsed.append((city, pin, lat, lon))

    city_stats = {}
    for city, rows in sorted(valid_by_city.items()):
        if len(rows) < 4:
            warnings.append({"code": "small_city_sample", "city": city,
                             "count": len(rows)})
            continue
        center = robust_center([(r[0], r[1]) for r in rows])
        distances = [distance_km(center, (r[0], r[1])) for r in rows]
        median = statistics.median(distances)
        mad = statistics.median(abs(d - median) for d in distances)
        limit = max(75.0, min(300.0, median + 10 * mad + 50.0))
        outliers = [
            {"city": city, "pincode": pin, "lat": lat, "lon": lon,
             "distance_km": round(distance_km(center, (lat, lon)), 1),
             "limit_km": round(limit, 1)}
            for lat, lon, pin in rows
            if distance_km(center, (lat, lon)) > limit
        ]
        city_stats[city] = {
            "count": len(rows),
            "center": [round(center[0], 5), round(center[1], 5)],
            "distance_limit_km": round(limit, 1),
            "outliers": len(outliers),
        }
        if outliers:
            issues.append({"code": "city_coordinate_outliers", "city": city,
                           "count": len(outliers), "sample": outliers[:10]})

    return {
        "ok": not issues,
        "records": len(records),
        "unique_pincodes": len(seen),
        "issues": issues,
        "warnings": warnings,
        "city_stats": city_stats,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    parser.add_argument("--compact", action="store_true")
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    try:
        records = json.load(open(args.config, encoding="utf-8"))
        if not isinstance(records, list):
            raise ValueError("top-level JSON must be an array")
        result = validate(records)
    except Exception as exc:
        result = {"ok": False, "issues": [{"code": "config_unreadable",
                                             "message": str(exc)}]}
    if args.summary:
        result = {key: value for key, value in result.items() if key != "city_stats"}
    print(json.dumps(result, ensure_ascii=True,
                     indent=None if args.compact else 2, sort_keys=True))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
