#!/usr/bin/env python3
"""Convertit un GTFS (zip) en un JSON compact embarqué dans l'application.

Usage : python tools/gtfs_to_json.py data/gtfs/monrezo.zip assets/data/network.json

Format de sortie (voir lib/data/network.dart, à garder synchronisé) :
{
  "network":  {"name", "generated", "valid_from", "valid_to", "source"},
  "stops":    [{"id", "name", "lat", "lon"}],                       # un lieu, pas un quai (voir MERGE_RADIUS_M)
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

# Console Windows en cp1252 : les accents et les flèches du résumé la font planter.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import hashlib
import math
import re
import unicodedata
import zipfile
from collections import Counter, defaultdict
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


# Deux arrêts de même nom plus éloignés que ça sont deux lieux différents (ex. CENTRE COMMERCIAL
# existe à Blanzy et au Creusot, à 15 km). En deçà, ce sont les quais d'un même point d'arrêt.
MERGE_RADIUS_M = 300.0


def norm_name(n):
    n = unicodedata.normalize("NFD", (n or "").strip().lower())
    n = "".join(c for c in n if unicodedata.category(c) != "Mn")
    return " ".join(n.split())


# Le code de quai de l'exploitant (stop_code) porte le lieu puis le numéro de quai :
# BLBSA1 / BLBSA2 = les deux quais de BOIS DE SAVIGNY à Blanzy. Le code sans son numéro nomme le lieu.
_CODE_TAIL = re.compile(r"^(.+?)(\d+)$")


def place_code(code):
    m = _CODE_TAIL.match(code)
    return m.group(1) if m else code


def haversine_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


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

    # --- Arrêts : un point d'arrêt = un lieu pour l'usager, pas un quai.
    # Deux quais opposés portent le même nom à quelques dizaines de mètres : les laisser séparés
    # donne deux entrées identiques dans la recherche, impossibles à départager.
    # Règle : même parent_station, OU même nom (accents et casse ignorés) à MERGE_RADIUS_M ou moins.
    # On mesure une vraie distance : arrondir les coordonnées découpe sur une grille et sépare
    # deux quais à 15 m s'ils tombent de part et d'autre d'une frontière.
    by_id = {s["stop_id"]: s for s in stops_raw}
    points = [s for s in stops_raw if (s.get("location_type") or "0").strip() in ("", "0")]

    parent_of = {s["stop_id"]: s["stop_id"] for s in points}

    def find(x):
        while parent_of[x] != x:
            parent_of[x] = parent_of[parent_of[x]]
            x = parent_of[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent_of[rb] = ra

    # 1. parent_station quand le producteur l'a renseignée
    for s in points:
        parent = (s.get("parent_station") or "").strip()
        if parent and parent in by_id:
            for other in points:
                if (other.get("parent_station") or "").strip() == parent:
                    union(s["stop_id"], other["stop_id"])

    # 2. même nom et proches
    by_name = defaultdict(list)
    for s in points:
        by_name[norm_name(s["stop_name"])].append(s)
    for group in by_name.values():
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                a, b = group[i], group[j]
                if haversine_m(float(a["stop_lat"]), float(a["stop_lon"]),
                               float(b["stop_lat"]), float(b["stop_lon"])) <= MERGE_RADIUS_M:
                    union(a["stop_id"], b["stop_id"])

    members = defaultdict(list)
    for s in points:
        members[find(s["stop_id"])].append(s)

    stop_of = {}         # stop_id GTFS -> id compact
    stops = []
    # --- Identifiants : ils doivent survivre à une régénération.
    # Les favoris sont enregistrés sur le téléphone sous cet identifiant. Un simple compteur dans
    # l'ordre du fichier ne tient pas : un arrêt ajouté décale toute la suite et le favori de
    # l'usager désigne alors un AUTRE arrêt — un écran faux, pas un écran vide. On s'ancre donc
    # sur le code de l'exploitant, qui lui ne bouge pas d'une publication à l'autre.
    roots = []
    seen_root = set()
    for s in points:
        root = find(s["stop_id"])
        if root not in seen_root:
            seen_root.add(root)
            roots.append(root)

    def codes_of(grp):
        return sorted(m["stop_code"].strip() for m in grp if (m.get("stop_code") or "").strip())

    def candidate(grp):
        codes = codes_of(grp)
        if not codes:
            # Producteur sans stop_code : repli déterministe, sans compteur ni ordre de fichier.
            base = norm_name(grp[0]["stop_name"]) + "|" + min(m["stop_id"] for m in grp)
            return "X" + hashlib.sha1(base.encode("utf-8")).hexdigest()[:6].upper()
        prefixes = {place_code(c) for c in codes}
        return prefixes.pop() if len(prefixes) == 1 else min(codes)

    cand = {r: candidate(members[r]) for r in roots}
    shared = {c for c, n in Counter(cand.values()).items() if n > 1}
    id_of_root = {}
    used = set()
    for root in roots:
        cid = cand[root]
        if cid in shared:
            # Deux lieux distincts sous le même code : l'exploitant les voit comme un seul
            # (GARE TGV ARRIVEE / DEPART). On garde le code de quai complet pour les départager.
            codes = codes_of(members[root])
            cid = codes[0] if codes else cid
        if cid in used:            # garde-fou : jamais deux arrêts sous le même identifiant
            n = 2
            while f"{cid}-{n}" in used:
                n += 1
            cid = f"{cid}-{n}"
        used.add(cid)
        id_of_root[root] = cid
        grp = members[root]
        # nom affiché : l'orthographe la plus fréquente du groupe ; position : barycentre des quais
        names = Counter(m["stop_name"].strip() for m in grp)
        stops.append({
            "id": cid,
            "name": names.most_common(1)[0][0],
            "lat": round(sum(float(m["stop_lat"]) for m in grp) / len(grp), 6),
            "lon": round(sum(float(m["stop_lon"]) for m in grp) / len(grp), 6),
        })
    for s in points:
        stop_of[s["stop_id"]] = id_of_root[find(s["stop_id"])]
    stops.sort(key=lambda x: x["id"])   # ordre du fichier indépendant de celui du GTFS

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
    print(f"Arrêts : {len(stops)} lieux (depuis {len(points)} quais GTFS)")
    print(f"Motifs : {len(pattern_list)}   Courses : {len(trips)}   Services : {len(services)}")
    import os
    print(f"Écrit : {dst} ({os.path.getsize(dst) // 1024} Ko)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "https://transport.data.gouv.fr/datasets/arrets-horaires-et-parcours-theoriques-du-reseau-monrezo-cucm-gtfs-1")
