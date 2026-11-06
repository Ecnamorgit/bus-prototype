// Moteur d'horaires : prochains passages à un arrêt, grille d'une ligne à un arrêt, services du jour.
// Pur Dart, sans Flutter, testé dans test/schedule_test.dart.

import 'dart:math' as math;

import 'network.dart';

class Departure {
  const Departure({
    required this.route,
    required this.pattern,
    required this.stopId,
    required this.scheduled,
    required this.minutesSinceMidnight,
    required this.isLastStop,
  });
  final BusLine route;
  final StopPattern pattern;
  final String stopId;
  final DateTime scheduled; // heure prévue (horaire théorique)
  final int minutesSinceMidnight; // relatif au jour de service
  final bool isLastStop; // terminus : on n'y monte pas

  String get headsign => pattern.headsign;

  /// Minutes avant le départ par rapport à [now] (négatif si passé).
  int minutesFrom(DateTime now) => scheduled.difference(now).inMinutes;
}

class Schedule {
  Schedule(this.net);
  final Network net;

  /// Les services actifs à une date (jour calendaire).
  Set<String> servicesOn(DateTime date) =>
      net.services.entries.where((e) => e.value.activeOn(date)).map((e) => e.key).toSet();

  /// Prochains départs à un arrêt à partir de [now], toutes lignes, triés par heure.
  /// Tient compte des courses de la veille après minuit (minutes > 1440) et de celles du jour.
  List<Departure> nextDepartures(String stopId, DateTime now, {int limit = 10, Duration window = const Duration(hours: 3)}) {
    final out = <Departure>[];
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final horizon = now.add(window);

    void collect(DateTime serviceDay) {
      final active = servicesOn(serviceDay);
      if (active.isEmpty) return;
      for (final t in net.trips) {
        if (!active.contains(t.serviceId)) continue;
        final p = net.patternById[t.patternId];
        if (p == null) continue;
        final idx = p.stopIds.indexOf(stopId);
        if (idx < 0) continue;
        final m = t.times[idx];
        final at = serviceDay.add(Duration(minutes: m));
        if (at.isBefore(now) || at.isAfter(horizon)) continue;
        final r = net.routeById[p.routeId];
        if (r == null) continue;
        out.add(Departure(
          route: r,
          pattern: p,
          stopId: stopId,
          scheduled: at,
          minutesSinceMidnight: m,
          isLastStop: idx == p.stopIds.length - 1,
        ));
      }
    }

    collect(yesterday); // courses de nuit commencées la veille
    collect(today);
    out.removeWhere((d) => d.isLastStop);
    out.sort((a, b) => a.scheduled.compareTo(b.scheduled));
    return out.take(limit).toList();
  }

  /// Tous les départs d'un motif (ligne + sens) à un arrêt pour une journée, en minutes depuis minuit, triés.
  List<int> timetable(String patternId, String stopId, DateTime date) {
    final p = net.patternById[patternId];
    if (p == null) return const [];
    final idx = p.stopIds.indexOf(stopId);
    if (idx < 0) return const [];
    final active = servicesOn(DateTime(date.year, date.month, date.day));
    final times = <int>[];
    for (final t in net.trips) {
      if (t.patternId == patternId && active.contains(t.serviceId)) times.add(t.times[idx]);
    }
    times.sort();
    return times;
  }

  /// Nombre de courses d'un motif ce jour-là (0 = pas de service, utile pour afficher « pas de bus aujourd'hui »).
  int tripCount(String patternId, DateTime date) {
    final active = servicesOn(DateTime(date.year, date.month, date.day));
    return net.trips.where((t) => t.patternId == patternId && active.contains(t.serviceId)).length;
  }

  /// Arrêts les plus proches d'une position (distance à vol d'oiseau, en mètres).
  List<(Stop, double)> nearestStops(double lat, double lon, {int limit = 5}) {
    final list = net.stops.map((s) => (s, haversineMeters(lat, lon, s.lat, s.lon))).toList();
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list.take(limit).toList();
  }

  /// Recherche d'arrêt par nom (insensible aux accents et à la casse).
  List<Stop> searchStops(String query, {int limit = 20}) {
    final q = _fold(query.trim());
    if (q.isEmpty) return const [];
    final starts = <Stop>[];
    final contains = <Stop>[];
    for (final s in net.stops) {
      final n = _fold(s.name);
      if (n.startsWith(q)) {
        starts.add(s);
      } else if (n.contains(q)) {
        contains.add(s);
      }
    }
    return [...starts, ...contains].take(limit).toList();
  }
}

String formatMinutes(int m) {
  final mm = m % 1440;
  return '${(mm ~/ 60).toString().padLeft(2, '0')}:${(mm % 60).toString().padLeft(2, '0')}';
}

double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180;

const _accents = 'àâäéèêëîïôöùûüç';
const _plain = 'aaaeeeeiioouuuc';

String _fold(String s) {
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _accents.indexOf(ch);
    sb.write(i >= 0 ? _plain[i] : ch);
  }
  return sb.toString();
}
