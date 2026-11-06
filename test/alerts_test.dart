// Informations trafic : lecture du flux, filtrage par date, tri, robustesse.
// Le dernier test lit le vrai fichier livré avec l'application.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/alerts.dart';

const _json = '''
{
 "_note": "jeu d'essai",
 "alerts": [
  {"id":"en-cours-grave","severity":"severe","lines":["C1","TGV"],"title":"Place fermée","body":"Déviation.",
   "from":"2026-11-02","to":"2026-11-14","updated":"2026-11-05T17:40","example":true},
  {"id":"en-cours-moyen","severity":"warning","lines":["M1"],"title":"Arrêt provisoire","body":"Cent mètres plus loin.",
   "from":"2026-11-06","to":"2026-11-07","updated":"2026-11-06T06:30","example":true},
  {"id":"permanent","severity":"info","lines":[],"title":"Correspondances garanties","body":"La navette attend.",
   "from":"2026-09-28","to":null,"updated":"2026-09-28T08:00","example":true},
  {"id":"a-venir","severity":"warning","lines":["M4"],"title":"Marché de Noël","body":"Arrêt déplacé.",
   "from":"2026-12-12","to":"2026-12-24","updated":"2026-11-03T09:15","example":true},
  {"id":"a-venir-proche","severity":"info","lines":[],"title":"Horaires d'hiver","body":"Au 1er décembre.",
   "from":"2026-11-15","to":"2026-12-01","updated":"2026-11-02T14:00","example":true},
  {"id":"termine","severity":"warning","lines":["M3"],"title":"Déviation d'octobre","body":"Fini.",
   "from":"2026-10-12","to":"2026-10-30","updated":"2026-10-30T18:00","example":true}
 ]
}
''';

void main() {
  final feed = AlertFeed.fromJsonString(_json);
  final jour = DateTime(2026, 11, 6);

  group('lecture', () {
    test('toutes les alertes sont lues, avec leurs champs', () {
      expect(feed.alerts.length, 6);
      final a = feed.alerts.first;
      expect(a.id, 'en-cours-grave');
      expect(a.severity, AlertSeverity.severe);
      expect(a.lines, ['C1', 'TGV']);
      expect(a.from, DateTime(2026, 11, 2));
      expect(a.updated, DateTime(2026, 11, 5, 17, 40));
      expect(a.example, isTrue);
    });

    test('le flux de la maquette est entièrement constitué d’exemples', () {
      expect(feed.allExamples, isTrue);
    });
  });

  group('périodes', () {
    test('une alerte en cours est active ses jours de début et de fin inclus', () {
      final a = feed.alerts.firstWhere((x) => x.id == 'en-cours-moyen');
      expect(a.isActiveOn(DateTime(2026, 11, 6)), isTrue);
      expect(a.isActiveOn(DateTime(2026, 11, 7)), isTrue); // dernier jour inclus
      expect(a.isActiveOn(DateTime(2026, 11, 8)), isFalse);
      expect(a.isActiveOn(DateTime(2026, 11, 5)), isFalse);
    });

    test('une alerte sans fin annoncée reste active', () {
      final a = feed.alerts.firstWhere((x) => x.id == 'permanent');
      expect(a.isActiveOn(DateTime(2027, 6, 1)), isTrue);
      expect(a.isOverOn(DateTime(2027, 6, 1)), isFalse);
    });

    test('l’heure du jour ne change rien : une alerte du jour vaut toute la journée', () {
      final a = feed.alerts.firstWhere((x) => x.id == 'en-cours-moyen');
      expect(a.isActiveOn(DateTime(2026, 11, 7, 23, 59)), isTrue);
    });
  });

  group('écran du jour', () {
    test('les perturbations terminées ne sont plus affichées', () {
      final ids = feed.current(jour).map((a) => a.id).toList();
      expect(ids, isNot(contains('termine')));
      expect(feed.upcoming(jour).map((a) => a.id), isNot(contains('termine')));
    });

    test('en cours : la plus grave d’abord, puis la plus récemment mise à jour', () {
      expect(feed.current(jour).map((a) => a.id).toList(), ['en-cours-grave', 'en-cours-moyen', 'permanent']);
    });

    test('à venir : dans l’ordre où elles arrivent', () {
      expect(feed.upcoming(jour).map((a) => a.id).toList(), ['a-venir-proche', 'a-venir']);
    });

    test('un jour sans rien : les deux listes sont vides', () {
      final vide = AlertFeed.fromJsonString('{"alerts": []}');
      expect(vide.current(jour), isEmpty);
      expect(vide.upcoming(jour), isEmpty);
    });
  });

  group('robustesse d’un flux de back-office', () {
    test('une entrée illisible est ignorée, les autres sont gardées', () {
      final f = AlertFeed.fromJsonString('''
{"alerts": [
  "ceci n'est pas une alerte",
  {"severity":"warning","body":"sans titre"},
  {"title":"Celle-ci est valable","severity":"warning"}
]}''');
      expect(f.alerts.length, 1);
      expect(f.alerts.single.title, 'Celle-ci est valable');
      expect(f.alerts.single.id, isNotEmpty); // un identifiant de repli est attribué
    });

    test('une gravité inconnue devient une information, jamais une urgence', () {
      final f = AlertFeed.fromJsonString('{"alerts":[{"title":"X","severity":"catastrophe"}]}');
      expect(f.alerts.single.severity, AlertSeverity.info);
    });

    test('sans « example », l’alerte est traitée comme un exemple', () {
      // On préfère étiqueter à tort une vraie alerte que présenter un exemple comme vrai.
      final f = AlertFeed.fromJsonString('{"alerts":[{"title":"X"}]}');
      expect(f.alerts.single.example, isTrue);
    });

    test('une date illisible est ignorée sans faire tomber le flux', () {
      final f = AlertFeed.fromJsonString('{"alerts":[{"title":"X","from":"hier","to":"demain"}]}');
      expect(f.alerts.single.from, isNull);
      expect(f.alerts.single.isActiveOn(jour), isTrue);
    });

    test('un fichier sans champ « alerts » est une erreur, pas un écran vide silencieux', () {
      expect(() => AlertFeed.fromJsonString('{"autre": 1}'), throwsFormatException);
      expect(() => AlertFeed.fromJsonString('pas du json'), throwsA(isA<Exception>()));
    });
  });

  test('le fichier livré dans assets se lit et n’annonce que des exemples', () {
    final f = AlertFeed.fromJsonString(File('assets/data/alerts.json').readAsStringSync());
    expect(f.alerts, isNotEmpty);
    expect(f.allExamples, isTrue, reason: 'une donnée simulée doit rester étiquetée comme telle');
    for (final a in f.alerts) {
      expect(a.title.trim(), isNotEmpty);
      expect(a.body.trim(), isNotEmpty);
      expect(a.from, isNotNull, reason: '${a.id} : une alerte doit dire quand elle commence');
    }
  });
}
