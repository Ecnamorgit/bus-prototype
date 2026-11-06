// Modèles du réseau, chargés depuis assets/data/network.json (produit par tools/gtfs_to_json.py).
// Format : voir l'en-tête du script. Ne pas changer l'un sans l'autre.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class Stop {
  const Stop({required this.id, required this.name, required this.lat, required this.lon});
  final String id;
  final String name;
  final double lat;
  final double lon;

  factory Stop.fromJson(Map<String, dynamic> j) => Stop(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

class BusLine {
  const BusLine({required this.id, required this.short, required this.long, required this.color, required this.textColor});
  final String id;
  final String short;
  final String long;
  final String color; // "#RRGGBB"
  final String textColor;

  factory BusLine.fromJson(Map<String, dynamic> j) => BusLine(
        id: j['id'] as String,
        short: j['short'] as String,
        long: j['long'] as String,
        color: j['color'] as String,
        textColor: j['text'] as String,
      );
}

class Service {
  const Service({required this.days, required this.start, required this.end, required this.add, required this.remove});
  final List<int> days; // lundi..dimanche, 0/1
  final String start; // YYYYMMDD
  final String end;
  final Set<String> add;
  final Set<String> remove;

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        days: (j['days'] as List).map((e) => e as int).toList(),
        start: j['start'] as String,
        end: j['end'] as String,
        add: (j['add'] as List).map((e) => e as String).toSet(),
        remove: (j['remove'] as List).map((e) => e as String).toSet(),
      );

  /// Le service circule-t-il à cette date (calendar_dates prime sur calendar) ?
  bool activeOn(DateTime date) {
    final ymd = yyyymmdd(date);
    if (remove.contains(ymd)) return false;
    if (add.contains(ymd)) return true;
    if (ymd.compareTo(start) < 0 || ymd.compareTo(end) > 0) return false;
    return days[date.weekday - 1] == 1;
  }
}

class StopPattern {
  const StopPattern({required this.id, required this.routeId, required this.direction, required this.headsign, required this.stopIds});
  final String id;
  final String routeId;
  final int direction;
  final String headsign;
  final List<String> stopIds;

  factory StopPattern.fromJson(Map<String, dynamic> j) => StopPattern(
        id: j['id'] as String,
        routeId: j['route'] as String,
        direction: j['direction'] as int,
        headsign: j['headsign'] as String,
        stopIds: (j['stops'] as List).map((e) => e as String).toList(),
      );
}

class Trip {
  const Trip({required this.patternId, required this.serviceId, required this.times});
  final String patternId;
  final String serviceId;
  final List<int> times; // minutes depuis minuit, alignées sur StopPattern.stopIds ; > 1440 après minuit

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        patternId: j['pattern'] as String,
        serviceId: j['service'] as String,
        times: (j['times'] as List).map((e) => e as int).toList(),
      );
}

class Network {
  Network({
    required this.name,
    required this.generated,
    required this.validFrom,
    required this.validTo,
    required this.source,
    required this.stops,
    required this.routes,
    required this.services,
    required this.patterns,
    required this.trips,
  })  : stopById = {for (final s in stops) s.id: s},
        routeById = {for (final r in routes) r.id: r},
        patternById = {for (final p in patterns) p.id: p};

  final String name;
  final String generated;
  final String validFrom;
  final String validTo;
  final String source;
  final List<Stop> stops;
  final List<BusLine> routes;
  final Map<String, Service> services;
  final List<StopPattern> patterns;
  final List<Trip> trips;

  final Map<String, Stop> stopById;
  final Map<String, BusLine> routeById;
  final Map<String, StopPattern> patternById;

  factory Network.fromJson(Map<String, dynamic> j) {
    final net = j['network'] as Map<String, dynamic>;
    return Network(
      name: net['name'] as String,
      generated: net['generated'] as String,
      validFrom: net['valid_from'] as String,
      validTo: net['valid_to'] as String,
      source: net['source'] as String,
      stops: (j['stops'] as List).map((e) => Stop.fromJson(e as Map<String, dynamic>)).toList(),
      routes: (j['routes'] as List).map((e) => BusLine.fromJson(e as Map<String, dynamic>)).toList(),
      services: (j['services'] as Map<String, dynamic>).map((k, v) => MapEntry(k, Service.fromJson(v as Map<String, dynamic>))),
      patterns: (j['patterns'] as List).map((e) => StopPattern.fromJson(e as Map<String, dynamic>)).toList(),
      trips: (j['trips'] as List).map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  static Network fromJsonString(String s) => Network.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// Charge le réseau embarqué dans les assets.
  static Future<Network> load([String asset = 'assets/data/network.json']) async {
    final s = await rootBundle.loadString(asset);
    return fromJsonString(s);
  }

  /// Motifs (sens) d'une ligne, direction 0 puis 1.
  List<StopPattern> patternsOfRoute(String routeId) {
    final list = patterns.where((p) => p.routeId == routeId).toList();
    list.sort((a, b) => a.direction.compareTo(b.direction));
    return list;
  }

  /// Lignes passant à un arrêt.
  List<BusLine> routesAtStop(String stopId) {
    final ids = <String>{};
    for (final p in patterns) {
      if (p.stopIds.contains(stopId)) ids.add(p.routeId);
    }
    return routes.where((r) => ids.contains(r.id)).toList();
  }
}

String yyyymmdd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
