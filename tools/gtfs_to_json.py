#!/usr/bin/env python3
"""Convertit un GTFS (zip) en un JSON compact embarqué dans l'application.

Usage : python tools/gtfs_to_json.py data/gtfs/monrezo.zip assets/data/network.json

Format de sortie (voir lib/data/network.dart, à garder synchronisé) :
{
  "network":  {"name", "generated", "valid_from", "valid_to", "source"},
  "stops":    [{"id", "name", "lat", "lon"}],                       # dédoublonnés (parent_station ou nom+position)
  "routes":   [{"id", "short", "long", "color", "text"}],
  "services": {"<id>": {"days": [lun..dim en 0/1], "start", "end", "add": [...], "remove": [...]}},
  "patterns": [{"id", "route", "direction", "headsign", "stops": ["<stop id>", ...]}],
  "trips":    [{"pattern", "service", "times": [minutes depuis minuit, aligné sur pattern.stops]}]
}
Les heures > 24:00 (courses après minuit) restent en minutes > 1440, comme dans le GTFS.
"""
import csv
import io
import json
import sys
import zipfile
from collections import defaultdict
from datetime import datetime


def read_table(z, name, required=True):
    try:
        raw = z.read(name)
    except KeyError:
        if required:
            sys.exit(f"Fichier manquant dans le GTFS : {name}")
        return []
    text = raw.decode("utf-8-sig")
    return list(csv.DictReader(io.StringIO(text)))


def to_minutes(hms):
    h, m, s = (int(x) for x in hms.strip().split(":"))
    return h * 60 + m + (1 if s >= 30 else 0)


def norm_color(c, default):
    c = (c or "").strip().lstrip("#")
    return f"#{c.upper()}" if len(c) == 6 else default


def main(src, dst, source_url=""):
    z = zipfile.ZipFile(src)
    agency = read_table(z, "agency.txt", required=False)
    stops_raw = read_table(z, "stops.txt")
    routes_raw = read_table(z, "routes.txt")
    trips_raw = read_table(z, "trips.txt")
    stop_times_raw = read_table(z, "stop_times.txt")
    calendar_raw = read_table(z, "calendar.txt", required=False)
    cal_dates_raw = read_table(z, "calendar_dates.txt", required=False)

    # --- Arrêts : fusion des quais d'une même station (parent_station) ou même nom à < 60 m.
    by_id = {s["stop_id"]: s for s in stops_raw}
    merged = {}          # clé de fusion -> id compact
    stop_of = {}         # stop_id GTFS -> id compact
    stops = []

    def key_for(s):
        parent = (s.get("parent_station") or "").strip()
        if parent and parent in by_id:
            p = by_id[parent]
            return ("P", parent), p
        lat, lon = float(s["stop_lat"]), float(s["stop_lon"])
        return ("N", s["stop_name"].strip().lower(), round(lat, 3), round(lon, 3)), s

    for s in stops_raw:
        if (s.get("location_type") or "0").strip() not in ("", "0"):
            continue  # stations (1), entrées (2)… ne sont pas des points d'arrêt
        k, ref = key_for(s)
        if k not in merged:
            cid = f"S{len(stops) + 1}"
            merged[k] = cid
            stops.append({
                "id": cid,
                "name": ref["stop_name"].strip(),
                "lat": round(float(ref["stop_lat"]), 6),
                "lon": round(float(ref["stop_lon"]), 6),
            })
        stop_of[s["stop_id"]] = merged[k]

    # --- Lignes
    route_of = {}
    routes = []
    for r in sorted(routes_raw, key=lambda r: (r.get("route_sort_order") or "9999", r.get("route_short_name") or "")):
        rid = f"R{len(routes) + 1}"
        route_of[r["route_id"]] = rid
        routes.append({
            "id": rid,
            "short": (r.get("route_short_name") or "").strip() or (r.get("route_long_name") or "").strip()[:6],
            "long": (r.get("route_long_name") or "").strip(),
            "color": norm_color(r.get("route_color"), "#0F2A4F"),
            "text": norm_color(r.get("route_text_color"), "#FFFFFF"),
        })

    # --- Calendrier
    services = {}
    for c in calendar_raw:
        services[c["service_id"]] = {
            "days": [int(c[d]) for d in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
            "start": c["start_date"].strip(),
            "end": c["end_date"].strip(),
            "add": [],
            "remove": [],
        }
    for d in cal_dates_raw:
        svc = services.setdefault(d["service_id"], {"days": [0] * 7, "start": "00000000", "end": "99999999", "add": [], "remove": []})
        (svc["add"] if d["exception_type"].strip() == "1" else svc["remove"]).append(d["date"].strip())

    # --- Courses et motifs
    st_by_trip = defaultdict(list)
    for st in stop_times_raw:
        st_by_trip[st["trip_id"]].append(st)
    patterns = {}
    pattern_list = []
    trips = []
    for t in trips_raw:
        sts = sorted(st_by_trip.get(t["trip_id"], []), key=lambda x: int(x["stop_sequence"]))
        if len(sts) < 2 or t["route_id"] not in route_of:
            continue
        seq = tuple(stop_of.get(x["stop_id"]) for x in sts)
        if any(s is None for s in seq):
            continue
        direction = int((t.get("direction_id") or "0").strip() or 0)
        headsign = (t.get("trip_headsign") or "").strip() or stops[int(seq[-1][1:]) - 1]["name"]
        pk = (route_of[t["route_id"]], direction, seq)
        if pk not in patterns:
            pid = f"P{len(pattern_list) + 1}"
            patterns[pk] = pid
            pattern_list.append({"id": pid, "route": route_of[t["route_id"]], "direction": direction, "headsign": headsign, "stops": list(seq)})
        times = [to_minutes(x.get("departure_time") or x["arrival_time"]) for x in sts]
        trips.append({"pattern": patterns[pk], "service": t["service_id"], "times": times})

    trips.sort(key=lambda x: (x["pattern"], x["times"][0]))

    starts = [s["start"] for s in services.values() if s["start"] != "00000000"]
    ends = [s["end"] for s in services.values() if s["end"] != "99999999"]
    out = {
        "network": {
            "name": (agency[0]["agency_name"].strip() if agency else "Réseau"),
            "generated": datetime.now().strftime("%Y-%m-%d"),
            "valid_from": min(starts) if starts else "",
            "valid_to": max(ends) if ends else "",
            "source": source_url,
        },
        "stops": stops,
        "routes": routes,
        "services": services,
        "patterns": pattern_list,
        "trips": trips,
    }
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    print(f"Réseau : {out['network']['name']}  validité {out['network']['valid_from']} → {out['network']['valid_to']}")
    print(f"Lignes : {len(routes)}  " + ", ".join(r['short'] for r in routes))
    print(f"Arrêts : {len(stops)} (dédoublonnés depuis {len(stops_raw)})")
    print(f"Motifs : {len(pattern_list)}   Courses : {len(trips)}   Services : {len(services)}")
    import os
    print(f"Écrit : {dst} ({os.path.getsize(dst) // 1024} Ko)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "https://transport.data.gouv.fr/datasets/arrets-horaires-et-parcours-theoriques-du-reseau-monrezo-cucm-gtfs-1")
