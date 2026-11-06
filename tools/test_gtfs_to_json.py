#!/usr/bin/env python3
"""Tests du convertisseur GTFS, sans dépendance : python tools/test_gtfs_to_json.py

Le GTFS réel n'est pas committé : ces tests fabriquent un mini-GTFS en mémoire.
Ils verrouillent deux garanties que l'application ne peut pas récupérer toute seule :
  - un arrêt = un lieu (les quais d'un même nom proches fusionnent, les homonymes lointains non) ;
  - les identifiants survivent à une régénération (les favoris sont enregistrés dessus).
"""
import io
import json
import os
import random
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtfs_to_json import main as convertir  # noqa: E402

STOPS = [
    # stop_id, stop_code, nom,            lat,        lon
    ("1", "AAPLA1", "PLACE CENTRALE", 46.800000, 4.400000),  # quai 1
    ("2", "AAPLA2", "PLACE CENTRALE", 46.800200, 4.400000),  # quai 2, ~22 m -> même lieu
    ("3", "AAMAR1", "MARCHE", 46.810000, 4.410000),
    ("4", "AACCO1", "CENTRE COMMERCIAL", 46.820000, 4.420000),
    ("5", "ZZCCO1", "CENTRE COMMERCIAL", 46.920000, 4.520000),  # ~13 km -> lieu différent
]
TRIPS = [("T1", "P", "S1", "MARCHE")]
TIMES = [("T1", "1", 1, "08:00:00"), ("T1", "3", 2, "08:10:00"), ("T1", "4", 3, "08:20:00")]


def ecrire_gtfs(chemin, stops):
    def csv_bloc(entete, lignes):
        return entete + "\n" + "\n".join(lignes) + "\n"

    with zipfile.ZipFile(chemin, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("agency.txt", csv_bloc(
            "agency_id,agency_name,agency_url,agency_timezone",
            ["A,Réseau test,https://example.invalid,Europe/Paris"]))
        z.writestr("stops.txt", csv_bloc(
            "stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type,parent_station",
            [f"{i},{c},{n},{la},{lo},," for i, c, n, la, lo in stops]))
        z.writestr("routes.txt", csv_bloc(
            "route_id,route_short_name,route_long_name,route_type,route_color,route_text_color",
            ["P,M1,Place - Centre,3,E11D48,FFFFFF"]))
        z.writestr("trips.txt", csv_bloc(
            "route_id,service_id,trip_id,trip_headsign,direction_id",
            [f"{r},{s},{t},{h},0" for t, r, s, h in TRIPS]))
        z.writestr("stop_times.txt", csv_bloc(
            "trip_id,arrival_time,departure_time,stop_id,stop_sequence",
            [f"{t},{hm},{hm},{s},{n}" for t, s, n, hm in TIMES]))
        z.writestr("calendar.txt", csv_bloc(
            "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date",
            ["S1,1,1,1,1,1,0,0,20260101,20261231"]))
        z.writestr("calendar_dates.txt", "service_id,date,exception_type\n")


def convertir_vers_dict(stops, dossier, nom):
    src = os.path.join(dossier, nom + ".zip")
    dst = os.path.join(dossier, nom + ".json")
    ecrire_gtfs(src, stops)
    silence = io.StringIO()
    vrai_stdout, sys.stdout = sys.stdout, silence
    try:
        convertir(src, dst, "test")
    finally:
        sys.stdout = vrai_stdout
    with open(dst, encoding="utf-8") as f:
        return json.load(f)


def executer():
    echecs = []

    def verifier(nom, condition, detail=""):
        print(("  OK   " if condition else "  ECHEC") + " " + nom + ("" if condition else f"  ({detail})"))
        if not condition:
            echecs.append(nom)

    with tempfile.TemporaryDirectory() as tmp:
        base = convertir_vers_dict(STOPS, tmp, "base")
        par_nom = {}
        for s in base["stops"]:
            par_nom.setdefault(s["name"], []).append(s)

        print("Un arrêt = un lieu")
        verifier("les deux quais de PLACE CENTRALE ne font qu'un arrêt",
                 len(par_nom.get("PLACE CENTRALE", [])) == 1, par_nom.get("PLACE CENTRALE"))
        verifier("les deux CENTRE COMMERCIAL lointains restent séparés",
                 len(par_nom.get("CENTRE COMMERCIAL", [])) == 2, par_nom.get("CENTRE COMMERCIAL"))
        verifier("l'arrêt fusionné se place entre ses quais",
                 abs(par_nom["PLACE CENTRALE"][0]["lat"] - 46.8001) < 1e-6,
                 par_nom["PLACE CENTRALE"][0]["lat"])
        ids = [s["id"] for s in base["stops"]]
        verifier("les identifiants sont uniques", len(ids) == len(set(ids)), ids)
        verifier("l'identifiant vient du code exploitant, sans numéro de quai",
                 par_nom["PLACE CENTRALE"][0]["id"] == "AAPLA", par_nom["PLACE CENTRALE"][0]["id"])

        print("Identifiants stables d'une régénération à l'autre")
        melange = list(STOPS)
        random.Random(1).shuffle(melange)
        melange.insert(0, ("99", "AANEW1", "QUARTIER NEUF", 46.700000, 4.300000))
        apres = convertir_vers_dict(melange, tmp, "perturbe")

        avant_ids = {s["id"]: s["name"] for s in base["stops"]}
        apres_ids = {s["id"]: s["name"] for s in apres["stops"]}
        communs = set(avant_ids) & set(apres_ids)
        deplaces = {i for i in communs if avant_ids[i] != apres_ids[i]}
        verifier("aucun identifiant ne change d'arrêt après mélange et ajout",
                 not deplaces, {i: (avant_ids[i], apres_ids[i]) for i in deplaces})
        verifier("aucun arrêt existant ne perd son identifiant",
                 not (set(avant_ids) - set(apres_ids)), sorted(set(avant_ids) - set(apres_ids)))
        verifier("le nouvel arrêt apparaît, et lui seul",
                 set(apres_ids) - set(avant_ids) == {"AANEW"}, set(apres_ids) - set(avant_ids))

        print("Motif desservant deux fois le même lieu")
        verifier("un motif garde ses deux passages",
                 all(len(p["stops"]) == len(t["times"])
                     for p in apres["patterns"] for t in apres["trips"] if t["pattern"] == p["id"]))

    print()
    if echecs:
        print(f"{len(echecs)} test(s) en échec.")
        return 1
    print("Tous les tests du convertisseur passent.")
    return 0


if __name__ == "__main__":
    sys.exit(executer())
