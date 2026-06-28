import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


DEFAULT_GTFS_DIR = Path("/Users/adampost/Downloads/MBTA_GTFS")
OUTPUT_DIR = Path(__file__).resolve().parent


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


def read_trip_pattern_lookup(gtfs_dir, target_pattern_ids):
    trips = []

    with (gtfs_dir / "trips.txt").open(newline="", encoding="utf-8-sig") as file:
        for row in csv.DictReader(file):
            pattern_id = row["route_pattern_id"]
            if pattern_id not in target_pattern_ids:
                continue

            trips.append(
                {
                    "tripId": row["trip_id"],
                    "routeId": row["route_id"],
                    "directionId": int(row["direction_id"]),
                    "patternId": pattern_id,
                    "serviceId": row["service_id"],
                    "headsign": row["trip_headsign"],
                }
            )

    trips.sort(key=lambda row: (row["routeId"], row["patternId"], row["tripId"]))
    return trips


def stop_name(stop):
    platform_name = stop.get("platform_name", "")
    if platform_name:
        return f"{stop['stop_name']} - {platform_name}"
    return stop["stop_name"]


def monitoring_mode(stop):
    vehicle_type = stop.get("vehicle_type", "")
    if stop.get("location_type") == "1":
        return "station"
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
    pattern_ids = {pattern["route_pattern_id"] for pattern in patterns}
    representative_trip_ids = {pattern["representative_trip_id"] for pattern in patterns}
    stop_times_by_trip = read_stop_times_for_trips(gtfs_dir, representative_trip_ids)
    trips = read_trip_pattern_lookup(gtfs_dir, pattern_ids)

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
                "monitoringMode": monitoring_mode(stop),
                "patterns": sorted(platform_pattern_ids[platform_id]),
            }
        )

    stations = []
    for station_id in sorted(station_platform_ids):
        stop = stops.get(station_id)
        first_platform = stops.get(next(iter(station_platform_ids[station_id])), {})
        source = stop or first_platform

        stations.append(
            {
                "stationId": station_id,
                "name": source.get("stop_name", station_id),
                "latitude": float(source["stop_lat"]) if source.get("stop_lat") else None,
                "longitude": float(source["stop_lon"]) if source.get("stop_lon") else None,
                "municipality": source.get("municipality", ""),
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

    return sequences, platforms, stations, trips


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
    sequences, platforms, stations, trips = build_static_json(args.gtfs_dir, args.routes)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_json(args.output_dir / "sequences.json", sequences)
    write_json(args.output_dir / "platforms.json", platforms)
    write_json(args.output_dir / "stations.json", stations)
    write_json(args.output_dir / "trips.json", trips)

    print(f"Wrote {len(sequences):,} sequence edges")
    print(f"Wrote {len(platforms):,} platforms")
    print(f"Wrote {len(stations):,} stations")
    print(f"Wrote {len(trips):,} trip pattern mappings")
    print(f"Output directory: {args.output_dir}")


if __name__ == "__main__":
    main()
