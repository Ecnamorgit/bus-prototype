import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/data/schedule.dart';

// Mini-réseau fictif : 1 ligne M1 Gare → Hôpital (3 arrêts), service semaine, une course de nuit.
const _json = '''
{
 "network": {"name":"Test","generated":"2026-11-06","valid_from":"20260101","valid_to":"20261231","source":""},
 "stops": [{"id":"S1","name":"Gare SNCF","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Mairie","lat":46.81,"lon":4.43},
           {"id":"S3","name":"Hôpital","lat":46.82,"lon":4.44}],
 "routes": [{"id":"R1","short":"M1","long":"Gare - Hôpital","color":"#E11D48","text":"#FFFFFF"}],
 "services": {"SEM": {"days":[1,1,1,1,1,0,0],"start":"20260101","end":"20261231","add":["20261107"],"remove":["20261111"]}},
 "patterns": [{"id":"P1","route":"R1","direction":0,"headsign":"Hôpital","stops":["S1","S2","S3"]},
              {"id":"P2","route":"R1","direction":1,"headsign":"Gare SNCF","stops":["S3","S2","S1"]}],
 "trips": [{"pattern":"P1","service":"SEM","times":[480,485,492]},
           {"pattern":"P1","service":"SEM","times":[510,515,522]},
           {"pattern":"P2","service":"SEM","times":[1510,1517,1522]}]
}
''';

// Mini-réseau en boucle : la course repasse par le même arrêt (cas réel de CORIOLIS sur la navette TGV).
const _jsonBoucle = '''
{
 "network": {"name":"Test boucle","generated":"2026-11-06","valid_from":"20260101","valid_to":"20261231","source":""},
 "stops": [{"id":"S1","name":"Gare","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Coriolis","lat":46.81,"lon":4.43},
           {"id":"S3","name":"Zone","lat":46.82,"lon":4.44}],
 "routes": [{"id":"R1","short":"TGV","long":"Navette","color":"#F2E700","text":"#000000"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20260101","end":"20261231","add":[],"remove":[]}},
 "patterns": [{"id":"PB","route":"R1","direction":0,"headsign":"Gare","stops":["S1","S2","S3","S2","S1"]}],
 "trips": [{"pattern":"PB","service":"TLJ","times":[600,605,612,619,625]}]
}
''';

void main() {
  final net = Network.fromJsonString(_json);
  final sched = Schedule(net);

  group('calendrier', () {
    test('un mardi de semaine est actif', () {
      expect(net.services['SEM']!.activeOn(DateTime(2026, 11, 10)), isTrue); // mardi
    });
    test('un samedi est inactif', () {
      expect(net.services['SEM']!.activeOn(DateTime(2026, 11, 14)), isFalse);
    });
    test('calendar_dates : exception de retrait le 11 novembre', () {
      expect(net.services['SEM']!.activeOn(DateTime(2026, 11, 11)), isFalse);
    });
    test('calendar_dates : ajout un samedi (7 novembre)', () {
      expect(net.services['SEM']!.activeOn(DateTime(2026, 11, 7)), isTrue);
    });
  });

  group('prochains départs', () {
    test('à la Gare à 7h50 un mardi : 08:00 puis 08:30, sens Hôpital', () {
      final d = sched.nextDepartures('S1', DateTime(2026, 11, 10, 7, 50));
      expect(d.map((x) => formatMinutes(x.minutesSinceMidnight)).toList(), ['08:00', '08:30']);
      expect(d.first.headsign, 'Hôpital');
      expect(d.first.minutesFrom(DateTime(2026, 11, 10, 7, 50)), 10);
    });
    test('le terminus n\'est pas proposé comme départ', () {
      // À l'Hôpital, P1 y termine (pas proposé) ; P2 y part à 25:10 = 01:10 le lendemain.
      final d = sched.nextDepartures('S3', DateTime(2026, 11, 10, 8, 0), window: const Duration(hours: 24));
      expect(d.every((x) => x.headsign == 'Gare SNCF'), isTrue);
    });
    test('course de nuit : à 00:30 mercredi, le bus de 25:10 (mardi) part à 01:10', () {
      final d = sched.nextDepartures('S3', DateTime(2026, 11, 11, 0, 30));
      expect(d.length, 1);
      expect(d.first.scheduled, DateTime(2026, 11, 11, 1, 10));
    });
    test('un samedi : rien', () {
      expect(sched.nextDepartures('S1', DateTime(2026, 11, 14, 7, 50)), isEmpty);
    });
    test('fenêtre de 3 h respectée', () {
      expect(sched.nextDepartures('S1', DateTime(2026, 11, 10, 3, 0)), isEmpty);
    });
  });

  group('grille horaire', () {
    test('P1 à la Mairie un mardi : 08:05 et 08:35', () {
      expect(sched.timetable('P1', 'S2', DateTime(2026, 11, 10)), [485, 515]);
    });
    test('arrêt hors motif : vide', () {
      expect(sched.timetable('P1', 'S9', DateTime(2026, 11, 10)), isEmpty);
    });
    test('tripCount à 0 un samedi', () {
      expect(sched.tripCount('P1', DateTime(2026, 11, 14)), 0);
    });
  });

  group('recherche et proximité', () {
    test('recherche sans accent ni casse', () {
      expect(sched.searchStops('hop').map((s) => s.name), ['Hôpital']);
      expect(sched.searchStops('GARE').first.id, 'S1');
    });
    test('arrêt le plus proche', () {
      final near = sched.nearestStops(46.8105, 4.4305, limit: 1);
      expect(near.first.$1.id, 'S2');
      expect(near.first.$2, lessThan(100));
    });
    test('lignes à un arrêt', () {
      expect(net.routesAtStop('S2').map((r) => r.short), ['M1']);
    });
  });

  test('formatMinutes gère les heures après minuit', () {
    expect(formatMinutes(1510), '01:10');
    expect(formatMinutes(480), '08:00');
  });
  group('motif en boucle', () {
    final netB = Network.fromJsonString(_jsonBoucle);
    final schedB = Schedule(netB);
    final matin = DateTime(2026, 11, 10, 9, 0);

    test('un arrêt desservi deux fois donne ses deux passages', () {
      final d = schedB.nextDepartures('S2', matin);
      expect(d.map((x) => formatMinutes(x.minutesSinceMidnight)).toList(), ['10:05', '10:19']);
    });

    test('au départ de la boucle, le retour au terminus n’est pas un départ', () {
      final d = schedB.nextDepartures('S1', matin);
      expect(d.map((x) => formatMinutes(x.minutesSinceMidnight)).toList(), ['10:00']);
    });

    test('la grille horaire liste les deux passages', () {
      expect(schedB.timetable('PB', 'S2', DateTime(2026, 11, 10)), [605, 619]);
    });
  });

  // Ligne à variantes : une course sur quatre fait un détour par la Zone et affiche une autre
  // destination. Cas réel de M3 (HOPITAL J. BOUVERI / LES GAUTHERETS) et de la navette TGV.
  group('ligne à variantes', () {
    const jsonVar = '''
{
 "network": {"name":"Test variantes","generated":"2026-11-06","valid_from":"20260101","valid_to":"20261231","source":""},
 "stops": [{"id":"S1","name":"Gare","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Mairie","lat":46.81,"lon":4.43},
           {"id":"S3","name":"Hôpital","lat":46.82,"lon":4.44},
           {"id":"S4","name":"Zone","lat":46.83,"lon":4.45}],
 "routes": [{"id":"L1","short":"M9","long":"Gare - Hôpital","color":"#2E4694","text":"#FFFFFF"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20260101","end":"20261231","add":[],"remove":[]}},
 "patterns": [{"id":"PA","route":"L1","direction":0,"headsign":"Hôpital","stops":["S1","S2","S3"]},
              {"id":"PB","route":"L1","direction":0,"headsign":"Hôpital via Zone","stops":["S1","S2","S4","S3"]},
              {"id":"PC","route":"L1","direction":1,"headsign":"Gare","stops":["S3","S2","S1"]}],
 "trips": [{"pattern":"PA","service":"TLJ","times":[480,485,492]},
           {"pattern":"PA","service":"TLJ","times":[510,515,522]},
           {"pattern":"PA","service":"TLJ","times":[540,545,552]},
           {"pattern":"PB","service":"TLJ","times":[495,500,505,512]},
           {"pattern":"PC","service":"TLJ","times":[600,607,612]}]
}
''';
    final netV = Network.fromJsonString(jsonVar);
    final schedV = Schedule(netV);
    final jour = DateTime(2026, 11, 10);

    test('le sens est nommé par la variante la plus fréquentée, pas la plus longue', () {
      // PB dessert 4 arrêts contre 3, mais ne porte qu'une course sur quatre.
      expect(netV.mainPatternOfDirection('L1', 0)?.id, 'PA');
      expect(netV.mainPatternOfDirection('L1', 0)?.headsign, 'Hôpital');
    });

    test('les arrêts d’un sens fusionnent les variantes, dans l’ordre', () {
      final ds = netV.directionStops('L1', 0);
      expect(ds.map((d) => d.stop.name).toList(), ['Gare', 'Mairie', 'Zone', 'Hôpital']);
    });

    test('un arrêt desservi par une seule variante est signalé', () {
      final ds = netV.directionStops('L1', 0);
      expect({for (final d in ds) d.stop.name: d.everyTrip},
          {'Gare': true, 'Mairie': true, 'Zone': false, 'Hôpital': true});
    });

    test('la grille d’un sens réunit toutes les variantes, triées', () {
      final t = schedV.directionTimetable('L1', 0, 'S2', jour);
      expect(t.map((x) => formatMinutes(x.minutes)).toList(), ['08:05', '08:20', '08:35', '09:05']);
      expect(t.map((x) => x.headsign).toList(), ['Hôpital', 'Hôpital via Zone', 'Hôpital', 'Hôpital']);
    });

    test('un arrêt de détour n’a que les passages de sa variante', () {
      final t = schedV.directionTimetable('L1', 0, 'S4', jour);
      expect(t.map((x) => formatMinutes(x.minutes)).toList(), ['08:25']);
    });

    test('le terminus d’un sens n’apparaît pas comme départ', () {
      expect(schedV.directionTimetable('L1', 0, 'S3', jour), isEmpty);
    });

    test('sens inconnu : vide, pas d’exception', () {
      expect(netV.directionStops('L1', 7), isEmpty);
      expect(netV.mainPatternOfDirection('L9', 0), isNull);
      expect(schedV.directionTimetable('L1', 7, 'S1', jour), isEmpty);
    });

    test('nombre de courses du jour pour un sens', () {
      expect(schedV.directionTripCount('L1', 0, jour), 4);
      expect(schedV.directionTripCount('L1', 1, jour), 1);
    });
  });
}
