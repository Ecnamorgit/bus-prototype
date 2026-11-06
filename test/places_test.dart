// Informations pratiques : lecture, robustesse, et contrôle du fichier réellement livré.
// Ces informations servent à agir (composer un numéro, se déplacer) : elles doivent être
// complètes et datées, sinon elles ne valent rien.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/places.dart';

void main() {
  group('lecture', () {
    test('boutiques, TAD et liens sont lus', () {
      final p = PracticalInfo.fromJsonString('''
{
 "source":"https://exemple.test/contact","fetched":"2026-11-06",
 "shops":[{"name":"Boutique","address":"1 rue du Test","hours":["Du lundi au vendredi","9h – 17h"],"phone":"03 85 00 00 00"}],
 "on_demand":{"title":"TAD","intro":"Sur réservation.","phone":"03 85 11 11 11",
              "hours":["Centrale","9h – 16h"],"rules":["Réservez la veille."]},
 "email":"contact@exemple.test",
 "links":[{"label":"Site","url":"https://exemple.test"}]
}''');
      expect(p.shops.single.name, 'Boutique');
      expect(p.shops.single.hours, ['Du lundi au vendredi', '9h – 17h']);
      expect(p.onDemand!.phone, '03 85 11 11 11');
      expect(p.links.single.url, 'https://exemple.test');
      expect(p.fetched, '2026-11-06');
    });

    test('une entrée incomplète est ignorée plutôt qu’affichée à moitié', () {
      final p = PracticalInfo.fromJsonString('''
{"shops":[{"name":"Sans adresse"},{"address":"Sans nom"},
          {"name":"Correcte","address":"2 rue du Test"}],
 "links":[{"label":"Sans url"},{"url":"https://sans-label.test"},
          {"label":"Correct","url":"https://ok.test"}]}''');
      expect(p.shops.map((s) => s.name).toList(), ['Correcte']);
      expect(p.links.map((l) => l.label).toList(), ['Correct']);
    });

    test('un lien qui n’est pas http(s) est refusé', () {
      // Un libellé rassurant ne doit pas pouvoir faire ouvrir autre chose qu'une page web.
      final p = PracticalInfo.fromJsonString(
          '{"links":[{"label":"Site officiel","url":"javascript:alert(1)"},{"label":"Fichier","url":"file:///etc/passwd"}]}');
      expect(p.links, isEmpty);
    });

    test('un fichier vide ne fait pas tomber l’écran', () {
      final p = PracticalInfo.fromJsonString('{}');
      expect(p.shops, isEmpty);
      expect(p.onDemand, isNull);
      expect(p.links, isEmpty);
      expect(() => PracticalInfo.fromJsonString('pas du json'), throwsA(isA<Exception>()));
    });
  });

  group('numéro composable', () {
    test('un numéro français devient un lien tel: international', () {
      expect(telUri('03 85 73 01 10'), 'tel:+33385730110');
      expect(telUri('03.85.69.01.10'), 'tel:+33385690110');
    });
    test('un numéro déjà international est conservé', () {
      expect(telUri('+33 3 85 73 01 10'), 'tel:+33385730110');
    });
  });

  test('le fichier livré est complet et daté', () {
    final p = PracticalInfo.fromJsonString(File('assets/data/places.json').readAsStringSync());
    expect(p.source, isNotNull, reason: 'une information de contact s’affiche avec sa provenance');
    expect(p.fetched, isNotNull, reason: 'et avec sa date de relevé');
    expect(p.shops.length, greaterThanOrEqualTo(2));
    for (final s in p.shops) {
      expect(s.address.trim(), isNotEmpty);
      expect(s.hours, isNotEmpty, reason: '${s.name} : des horaires manquants envoient quelqu’un devant une porte fermée');
      expect(telUri(s.phone), startsWith('tel:+33'), reason: '${s.name} : numéro non composable');
    }
    expect(p.onDemand, isNotNull);
    expect(telUri(p.onDemand!.phone), startsWith('tel:+33'));
    expect(p.onDemand!.rules, isNotEmpty);
    expect(p.links, isNotEmpty);
    for (final l in p.links) {
      expect(l.url, startsWith('https://'));
    }
  });
}
