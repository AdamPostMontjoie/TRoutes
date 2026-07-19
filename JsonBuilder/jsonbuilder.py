import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


DEFAULT_GTFS_DIR = Path("/Users/adampost/Downloads/MBTA_GTFS")
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "TRoutes" / "TRoutes" / "Resources" / "JsonBuilder"

UNDERGROUND_STATIONS_BY_ID = {
    # --- MULTI-LINE & INTERMODAL TRANSFER STATIONS ---
    "place-pktrm": "Park Street",             # Red Line / Green Line
    "place-dwnxg": "Downtown Crossing",       # Red Line / Orange Line
    "place-sstat": "South Station",           # Red Line / Silver Line / Commuter Rail
    "place-state": "State",                   # Orange Line / Blue Line
    "place-gover": "Government Center",       # Blue Line / Green Line
    "place-north": "North Station",           # Orange Line / Green Line / Commuter Rail
    "place-haecl": "Haymarket",               # Orange Line / Green Line / Bus Terminal
    "place-bbsta": "Back Bay",                # Orange Line / Commuter Rail
    "place-portr": "Porter",                  # Red Line / Commuter Rail
    "place-harsq": "Harvard",                 # Red Line / Bus
    "place-andrw": "Andrew",                  # Red Line / Bus Concourse
    "place-qnctr": "Quincy Center",           # Red Line / Commuter Rail / Bus Terminal
    "place-rugg": "Ruggles",                  # Orange Line / Commuter Rail / Bus Terminal
    "place-forhl": "Forest Hills",            # Orange Line / Commuter Rail / Bus Terminal
    "place-sull": "Sullivan Square",          # Orange Line / Bus Terminal
    "place-kencl": "Kenmore",                 # Green Line / Bus Terminal

    # --- RED LINE (SINGLE-LINE STATIONS) ---
    "place-alfcl": "Alewife",
    "place-davis": "Davis",
    "place-cntsq": "Central",
    "place-knncl": "Kendall/MIT",
    "place-chmnl": "Charles/MGH",
    "place-brdwy": "Broadway",
    "place-smmnl": "Shawmut",

    # --- ORANGE LINE (SINGLE-LINE STATIONS) ---
    "place-ccmnl": "Community College",    # Double-decked I-93 & Route 1 highway overpasses
    "place-chncl": "Chinatown",
    "place-tumnl": "Tufts Medical Center",
    "place-rcmnl": "Roxbury Crossing",
    "place-jaksn": "Jackson Square",
    "place-sbmnl": "Stony Brook",
    "place-grnst": "Green Street",

    # --- BLUE LINE (SINGLE-LINE STATIONS) ---
    "place-bomnl": "Bowdoin",
    "place-aqucl": "Aquarium",
    "place-mvbcl": "Maverick",
    "place-aport": "Airport",

    # --- GREEN LINE (SINGLE-LINE STATIONS) ---
    "place-boyls": "Boylston",
    "place-armnl": "Arlington",
    "place-coecl": "Copley",
    "place-hymnl": "Hynes Convention Center",
    "place-prmnl": "Prudential",
    "place-symcl": "Symphony",

    # --- SILVER LINE (BUSWAY TUNNEL STATIONS) ---
    "place-crtst": "Courthouse",
    "place-wtcst": "World Trade Center",
}

def monitoring_mode(station_id, station_name):
    expected_name = UNDERGROUND_STATIONS_BY_ID.get(station_id)
    if expected_name is None:
        return "surface"
    if expected_name != station_name:
        raise ValueError(
            f"Underground station ID/name mismatch for {station_id}: "
            f"expected {expected_name!r}, got {station_name!r}"
        )
    return "underground"


def read_csv_by_id(path, key):
    with path.open(newline="", encoding="utf-8-sig") as file:
        return {row[key]: row for row in csv.DictReader(file)}


def read_route_patterns(gtfs_dir, target_routes):
    patterns = []

    with (gtfs_dir / "route_patterns.txt").open(newline="", encoding="utf-8-sig") as file:
        for row in csv.DictReader(file):
            if target_routes and row["route_id"] not in target_routes:
                continue

            representative_trip_id = row.get("representative_trip_id", "")
            if not representative_trip_id:
                continue

            patterns.append(row)

    return patterns


def read_stop_times_for_trips(gtfs_dir, trip_ids):
    stop_times_by_trip = defaultdict(list)

    with (gtfs_dir / "stop_times.txt").open(newline="", encoding="utf-8-sig") as file:
        for row in csv.DictReader(file):
            trip_id = row["trip_id"]
            if trip_id in trip_ids:
                stop_times_by_trip[trip_id].append(row)

    for rows in stop_times_by_trip.values():
        rows.sort(key=lambda row: int(row["stop_sequence"]))

    return stop_times_by_trip


def parse_optional_int(value):
    return int(value) if value else None


def build_pattern_models(patterns, stop_times_by_trip):
    route_direction_patterns = defaultdict(list)

    for pattern in patterns:
        route_direction_patterns[
            (pattern["route_id"], int(pattern["direction_id"]))
        ].append(pattern)

    pattern_models = []

    for (route_id, direction_id), grouped_patterns in route_direction_patterns.items():
        canonical_pattern_ids = {
            pattern["route_pattern_id"]
            for pattern in grouped_patterns
            if pattern.get("canonical_route_pattern") == "1"
        }

        if canonical_pattern_ids:
            default_pattern_ids = canonical_pattern_ids
            default_reason = "mbta_canonical"
        else:
            typicalities = [
                parse_optional_int(pattern.get("route_pattern_typicality"))
                for pattern in grouped_patterns
                if parse_optional_int(pattern.get("route_pattern_typicality")) is not None
            ]
            best_typicality = min(typicalities) if typicalities else None
            default_pattern_ids = {
                pattern["route_pattern_id"]
                for pattern in grouped_patterns
                if parse_optional_int(pattern.get("route_pattern_typicality")) == best_typicality
            }
            default_reason = "best_typicality"

        is_branched = len(default_pattern_ids) > 1
        rows = []

        for pattern in grouped_patterns:
            pattern_id = pattern["route_pattern_id"]
            stop_count = len(stop_times_by_trip.get(pattern["representative_trip_id"], []))
            is_default_candidate = pattern_id in default_pattern_ids

            rows.append(
                {
                    "patternId": pattern_id,
                    "routeId": route_id,
                    "directionId": direction_id,
                    "name": pattern["route_pattern_name"],
                    "typicality": parse_optional_int(pattern.get("route_pattern_typicality")),
                    "isCanonical": pattern.get("canonical_route_pattern") == "1",
                    "stopCount": stop_count,
                    "isDefaultCandidate": is_default_candidate,
                    "defaultReason": default_reason if is_default_candidate else None,
                    "isBranched": is_branched,
                }
            )

        rows.sort(
            key=lambda row: (
                not row["isDefaultCandidate"],
                row["typicality"] if row["typicality"] is not None else 9999,
                -row["stopCount"],
                row["patternId"],
            )
        )

        for default_rank, row in enumerate(rows, start=1):
            row["defaultRank"] = default_rank
            pattern_models.append(row)

    pattern_models.sort(
        key=lambda row: (row["routeId"], row["directionId"], row["defaultRank"])
    )
    return pattern_models


def stop_name(stop):
    platform_name = stop.get("platform_name", "")
    if platform_name:
        return f"{stop['stop_name']} - {platform_name}"
    return stop["stop_name"]


def transit_type(stop):
    vehicle_type = stop.get("vehicle_type", "")
    if vehicle_type == "0":
        return "light rail"
    if vehicle_type == "1":
        return "heavy rail"
    if vehicle_type == "2":
        return "commuter rail"
    if vehicle_type == "3":
        return "bus"
    if vehicle_type == "4":
        return "ferry"
    raise ValueError(f"Unknown vehicle_type {vehicle_type!r} for stop {stop['stop_id']}")


def build_static_json(gtfs_dir, route_ids):
    target_routes = set(route_ids) if route_ids else None

    stops = read_csv_by_id(gtfs_dir / "stops.txt", "stop_id")
    patterns = read_route_patterns(gtfs_dir, target_routes)
    representative_trip_ids = {pattern["representative_trip_id"] for pattern in patterns}
    stop_times_by_trip = read_stop_times_for_trips(gtfs_dir, representative_trip_ids)
    pattern_models = build_pattern_models(patterns, stop_times_by_trip)

    sequences = []
    platform_pattern_ids = defaultdict(set)
    station_platform_ids = defaultdict(set)

    for pattern in patterns:
        pattern_id = pattern["route_pattern_id"]
        route_id = pattern["route_id"]
        direction_id = int(pattern["direction_id"])
        trip_id = pattern["representative_trip_id"]

        for stop_time in stop_times_by_trip.get(trip_id, []):
            platform_id = stop_time["stop_id"]
            sequence_number = int(stop_time["stop_sequence"])

            sequences.append(
                {
                    "routeId": route_id,
                    "patternId": pattern_id,
                    "directionId": direction_id,
                    "sequenceNumber": sequence_number,
                    "platformId": platform_id,
                }
            )
            platform_pattern_ids[platform_id].add(pattern_id)

            stop = stops.get(platform_id, {})
            station_id = stop.get("parent_station") or platform_id
            station_platform_ids[station_id].add(platform_id)

    platforms = []
    for platform_id in sorted(platform_pattern_ids):
        stop = stops.get(platform_id)
        if not stop:
            continue

        parent_id = stop.get("parent_station") or platform_id
        station = stops.get(parent_id, stop)
        station_name = station.get("stop_name", parent_id)
        platforms.append(
            {
                "platformId": platform_id,
                "parentId": parent_id,
                "name": stop_name(stop),
                "latitude": float(stop["stop_lat"]) if stop.get("stop_lat") else None,
                "longitude": float(stop["stop_lon"]) if stop.get("stop_lon") else None,
                "monitoringMode": monitoring_mode(parent_id, station_name),
                "transitType": transit_type(stop),
                "patterns": sorted(platform_pattern_ids[platform_id]),
            }
        )
    stations = []
    for station_id in sorted(station_platform_ids):
        stop = stops.get(station_id)
        first_platform = stops.get(next(iter(station_platform_ids[station_id])), {})
        source = stop or first_platform

        station_name = source.get("stop_name", station_id)
        stations.append(
            {
                "stationId": station_id,
                "name": station_name,
                "latitude": float(source["stop_lat"]) if source.get("stop_lat") else None,
                "longitude": float(source["stop_lon"]) if source.get("stop_lon") else None,
                "municipality": source.get("municipality", ""),
                "monitoringMode": monitoring_mode(station_id, station_name),
                "platforms": sorted(station_platform_ids[station_id]),
            }
        )

    sequences.sort(
        key=lambda row: (
            row["routeId"],
            row["patternId"],
            row["directionId"],
            row["sequenceNumber"],
        )
    )

    return sequences, platforms, stations, pattern_models


def write_json(path, data):
    with path.open("w", encoding="utf-8") as file:
        json.dump(data, file, indent=2)
        file.write("\n")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build MBTA structure JSON from static GTFS files."
    )
    parser.add_argument(
        "--gtfs-dir",
        type=Path,
        default=DEFAULT_GTFS_DIR,
        help=f"Path to unpacked MBTA GTFS folder. Default: {DEFAULT_GTFS_DIR}",
    )
    parser.add_argument(
        "--routes",
        nargs="*",
        help="Optional route IDs to include, e.g. Red Orange Green-B CR-Lowell.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=OUTPUT_DIR,
        help=f"Directory for generated JSON files. Default: {OUTPUT_DIR}",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    sequences, platforms, stations, patterns = build_static_json(
        args.gtfs_dir, args.routes
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_json(args.output_dir / "sequences.json", sequences)
    write_json(args.output_dir / "platforms.json", platforms)
    write_json(args.output_dir / "stations.json", stations)
    write_json(args.output_dir / "patterns.json", patterns)

    print(f"Wrote {len(sequences):,} sequence edges")
    print(f"Wrote {len(platforms):,} platforms")
    print(f"Wrote {len(stations):,} stations")
    print(f"Wrote {len(patterns):,} route patterns")
    print(f"Output directory: {args.output_dir}")


if __name__ == "__main__":
    main()
