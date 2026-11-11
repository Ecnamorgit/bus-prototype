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

/// Un passage dans la grille horaire d'un sens de ligne, à un arrêt.
class DirectionDeparture {
  const DirectionDeparture({required this.minutes, required this.headsign, required this.patternId});
  final int minutes; // depuis minuit du jour de service, > 1440 après minuit
  final String headsign; // destination de cette course : elle varie d'une variante à l'autre
  final String patternId;
}

class Schedule {
  Schedule(this.net);
  final Network net;

  /// Les services actifs à une date (jour calendaire).
  Set<String> servicesOn(DateTime date) =>
      net.services.entries.where((e) => e.value.activeOn(date)).map((e) => e.key).toSet();

  /// Le réseau circule-t-il ce jour-là ? Aucun service actif = dimanche, jour férié, ou
  /// date sortie de la période couverte par les données embarquées.
  bool runsOn(DateTime date) => servicesOn(DateTime(date.year, date.month, date.day)).isNotEmpty;

  /// Premier jour où le réseau circule, à partir de [from] inclus.
  ///
  /// Renvoie null si rien ne circule dans les [withinDays] jours qui suivent : ce n'est
  /// alors plus « c'est dimanche », ce sont les données qui ont expiré, et les deux ne se
  /// disent pas de la même façon à l'usager.
  DateTime? nextServiceDay(DateTime from, {int withinDays = 14}) {
    for (var i = 0; i <= withinDays; i++) {
      // DateTime(y, m, j + i) normalise les fins de mois et reste juste aux changements
      // d'heure, contrairement à une addition de Duration.
      final day = DateTime(from.year, from.month, from.day + i);
      if (runsOn(day)) return day;
    }
    return null;
  }

  /// Les premiers départs d'un arrêt sur une journée entière, à partir de minuit.
  ///
  /// Sert les jours où le réseau ne circule pas : plutôt qu'une carte vide, on montre
  /// quand les bus reprennent. La fenêtre de 24 h couvre la journée complète ; les
  /// courses de nuit de la veille qui débordent après minuit sont déjà gérées par
  /// [nextDepartures].
  List<Departure> firstDeparturesOfDay(String stopId, DateTime day, {int limit = 3}) =>
      nextDepartures(stopId, DateTime(day.year, day.month, day.day),
          limit: limit, window: const Duration(hours: 24));

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
        final r = net.routeById[p.routeId];
        if (r == null) continue;
        // Un motif peut desservir deux fois le même arrêt (ligne en boucle) : tous les passages comptent.
        for (var idx = 0; idx < p.stopIds.length; idx++) {
          if (p.stopIds[idx] != stopId) continue;
          final m = t.times[idx];
          final at = serviceDay.add(Duration(minutes: m));
          if (at.isBefore(now) || at.isAfter(horizon)) continue;
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
    // Idem : un arrêt peut revenir plusieurs fois dans le motif.
    final idxs = [for (var i = 0; i < p.stopIds.length; i++) if (p.stopIds[i] == stopId) i];
    if (idxs.isEmpty) return const [];
    final active = servicesOn(DateTime(date.year, date.month, date.day));
    final times = <int>[];
    for (final t in net.trips) {
      if (t.patternId != patternId || !active.contains(t.serviceId)) continue;
      for (final i in idxs) {
        times.add(t.times[i]);
      }
    }
    times.sort();
    return times;
  }

  /// Grille horaire du jour à un arrêt pour un sens entier : toutes les variantes réunies.
  ///
  /// À CORIOLIS, la navette TGV a trois variantes dans le même sens ; n'en montrer qu'une
  /// cache un bus sur six. Sur M3, les deux variantes n'ont même pas la même destination,
  /// d'où la destination portée par chaque passage.
  /// Le terminus d'une variante n'est pas un départ : on n'y monte pas.
  List<DirectionDeparture> directionTimetable(String routeId, int direction, String stopId, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final active = servicesOn(day);
    final out = <DirectionDeparture>[];
    for (final p in net.patternsOfDirection(routeId, direction)) {
      final idxs = [
        for (var i = 0; i < p.stopIds.length - 1; i++)
          if (p.stopIds[i] == stopId) i,
      ];
      if (idxs.isEmpty) continue;
      for (final t in net.trips) {
        if (t.patternId != p.id || !active.contains(t.serviceId)) continue;
        for (final i in idxs) {
          out.add(DirectionDeparture(minutes: t.times[i], headsign: p.headsign, patternId: p.id));
        }
      }
    }
    out.sort((a, b) => a.minutes.compareTo(b.minutes));
    return out;
  }

  /// Nombre de courses d'un sens ce jour-là, toutes variantes : 0 = pas de bus aujourd'hui.
  int directionTripCount(String routeId, int direction, DateTime date) {
    final active = servicesOn(DateTime(date.year, date.month, date.day));
    final ids = net.patternsOfDirection(routeId, direction).map((p) => p.id).toSet();
    return net.trips.where((t) => ids.contains(t.patternId) && active.contains(t.serviceId)).length;
  }

  /// Nombre de courses d'une ligne ce jour-là, tous sens : 0 = la ligne ne circule pas.
  int routeTripCount(String routeId, DateTime date) {
    final active = servicesOn(DateTime(date.year, date.month, date.day));
    final ids = net.patterns.where((p) => p.routeId == routeId).map((p) => p.id).toSet();
    return net.trips.where((t) => ids.contains(t.patternId) && active.contains(t.serviceId)).length;
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
