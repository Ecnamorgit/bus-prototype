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
}
