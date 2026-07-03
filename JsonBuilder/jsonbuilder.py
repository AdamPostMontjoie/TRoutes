import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


DEFAULT_GTFS_DIR = Path("/Users/adampost/Downloads/MBTA_GTFS")
OUTPUT_DIR = Path(__file__).resolve().parent


UNDERGROUND_STATIONS_BY_ID = {
    "place-alfcl": "Alewife",
    "place-aport": "Airport",
    "place-aqucl": "Aquarium",
    "place-armnl": "Arlington",
    "place-bbsta": "Back Bay",
    "place-bomnl": "Bowdoin",
    "place-boyls": "Boylston",
    "place-brdwy": "Broadway",
    "place-ccmnl": "Community College",
    "place-chmnl": "Charles/MGH",
    "place-chncl": "Chinatown",
    "place-cntsq": "Central",
    "place-coecl": "Copley",
    "place-crtst": "Courthouse",
    "place-davis": "Davis",
    "place-dwnxg": "Downtown Crossing",
    "place-gover": "Government Center",
    "place-haecl": "Haymarket",
    "place-hymnl": "Hynes Convention Center",
    "place-kencl": "Kenmore",
    "place-knncl": "Kendall/MIT",
    "place-mvbcl": "Maverick",
    "place-north": "North Station",
    "place-pktrm": "Park Street",
    "place-portr": "Porter",
    "place-prmnl": "Prudential",
    "place-sstat": "South Station",
    "place-state": "State",
    "place-sull": "Sullivan Square",
    "place-symcl": "Symphony",
    "place-tumnl": "Tufts Medical Center",
    "place-wtcst": "World Trade Center",
}


def monitoring_mode(station_id, station_name):
    expected_name = UNDERGROUND_STATIONS_BY_ID.get(station_id)
    if expected_name is None:
        return "aboveground"
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


def build_pattern_models(patterns):
    pattern_models = []

    for pattern in patterns:
        pattern_models.append(
            {
                "patternId": pattern["route_pattern_id"],
                "routeId": pattern["route_id"],
                "directionId": int(pattern["direction_id"]),
                "name": pattern["route_pattern_name"],
                "typicality": int(pattern["route_pattern_typicality"])
                if pattern.get("route_pattern_typicality")
                else None,
                "isCanonical": pattern.get("canonical_route_pattern") == "1",
            }
        )

    pattern_models.sort(
        key=lambda row: (row["routeId"], row["directionId"], row["patternId"])
    )
    return pattern_models


def stop_name(stop):
    platform_name = stop.get("platform_name", "")
    if platform_name:
        return f"{stop['stop_name']} - {platform_name}"
    return stop["stop_name"]


def transit_type(stop):
    vehicle_type = stop.get("vehicle_type", "")
    if vehicle_type in {"0", "1"}:
        return "rapid_transit"
    if vehicle_type == "2":
        return "commuter_rail"
    if vehicle_type == "4":
        return "ferry"
    return "surface"


def build_static_json(gtfs_dir, route_ids):
    target_routes = set(route_ids) if route_ids else None

    stops = read_csv_by_id(gtfs_dir / "stops.txt", "stop_id")
    patterns = read_route_patterns(gtfs_dir, target_routes)
    representative_trip_ids = {pattern["representative_trip_id"] for pattern in patterns}
    stop_times_by_trip = read_stop_times_for_trips(gtfs_dir, representative_trip_ids)
    pattern_models = build_pattern_models(patterns)

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
        platforms.append(
            {
                "platformId": platform_id,
                "parentId": parent_id,
                "name": stop_name(stop),
                "latitude": float(stop["stop_lat"]) if stop.get("stop_lat") else None,
                "longitude": float(stop["stop_lon"]) if stop.get("stop_lon") else None,
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
