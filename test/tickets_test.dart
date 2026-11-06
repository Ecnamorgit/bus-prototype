// Titres : lecture du catalogue, cycle de vie d'un titre, portefeuille persistant.
// Le dernier test lit le vrai fichier de tarifs livré avec l'application.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/tickets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _json = '''
{
 "source": "https://exemple.test/tarifs",
 "fetched": "2026-11-06",
 "fares": [
  {"id":"unite","name":"Ticket unitaire","price_cents":120,"description":"Un trajet.",
   "trips":1,"validity_minutes":60,"all_day":false,"note":""},
  {"id":"dix","name":"Titre 10 voyages","price_cents":900,"description":"Dix trajets.",
   "trips":10,"validity_minutes":60,"all_day":false,"note":"En boutique aujourd'hui."},
  {"id":"journee","name":"Ticket journée","price_cents":360,"description":"Illimité.",
   "trips":0,"validity_minutes":0,"all_day":true,"note":""}
 ]
}
''';

void main() {
  final cat = FareCatalog.fromJsonString(_json);
  final unite = cat.byId('unite')!;
  final dix = cat.byId('dix')!;
  final journee = cat.byId('journee')!;
  final midi = DateTime(2026, 11, 6, 12, 0);

  group('catalogue', () {
    test('les trois titres sont lus avec leur prix et leur source', () {
      expect(cat.fares.map((f) => f.id).toList(), ['unite', 'dix', 'journee']);
      expect(unite.priceCents, 120);
      expect(cat.source, 'https://exemple.test/tarifs');
      expect(cat.fetched, '2026-11-06');
    });

    test('les prix s’écrivent en euros, à la française', () {
      expect(formatPrice(120), '1,20 €');
      expect(formatPrice(900), '9 €');
      expect(formatPrice(360), '3,60 €');
    });

    test('un tarif sans prix ou sans nom est ignoré, un catalogue vide est une erreur', () {
      final f = FareCatalog.fromJsonString(
          '{"fares":[{"id":"x"},{"id":"y","name":"Sans prix"},{"id":"z","name":"Bon","price_cents":100}]}');
      expect(f.fares.map((x) => x.id).toList(), ['z']);
      expect(() => FareCatalog.fromJsonString('{"fares":[]}'), throwsFormatException);
      expect(() => FareCatalog.fromJsonString('{"autre":1}'), throwsFormatException);
    });
  });

  group('cycle de vie d’un titre', () {
    test('un titre acheté attend sa validation', () {
      final t = Ticket.bought(unite, midi);
      expect(t.stateAt(midi), TicketState.aValider);
      expect(t.expiresAt, isNull);
      expect(t.remainingAt(midi), isNull);
      expect(t.demo, isTrue);
    });

    test('validé, il court 60 minutes puis s’épuise', () {
      final t = Ticket.bought(unite, midi).validate(midi);
      expect(t.stateAt(midi), TicketState.enCours);
      expect(t.remainingAt(midi.add(const Duration(minutes: 20))), const Duration(minutes: 40));
      expect(t.stateAt(midi.add(const Duration(minutes: 59))), TicketState.enCours);
      expect(t.stateAt(midi.add(const Duration(minutes: 61))), TicketState.epuise);
    });

    test('un carnet rend un voyage à chaque validation, et pas un de plus', () {
      var t = Ticket.bought(dix, midi);
      expect(t.tripsLeft, 10);

      t = t.validate(midi); // premier voyage
      expect(t.tripsLeft, 9);
      expect(t.stateAt(midi), TicketState.enCours);

      // Pendant la correspondance, revalider ne consomme rien.
      final pendant = midi.add(const Duration(minutes: 30));
      t = t.validate(pendant);
      expect(t.tripsLeft, 9);

      // Une fois la fenêtre passée, le titre redevient utilisable.
      final apres = midi.add(const Duration(minutes: 70));
      expect(t.stateAt(apres), TicketState.aValider);
      t = t.validate(apres);
      expect(t.tripsLeft, 8);
    });

    test('un carnet épuisé le reste', () {
      var t = Ticket.bought(dix, midi);
      var quand = midi;
      for (var i = 0; i < 10; i++) {
        t = t.validate(quand);
        quand = quand.add(const Duration(minutes: 61));
      }
      expect(t.tripsLeft, 0);
      expect(t.stateAt(quand), TicketState.epuise);
      expect(t.validate(quand).tripsLeft, 0); // pas de voyage en trop
    });

    test('un titre journée vaut jusqu’à la fin de la journée, puis plus rien', () {
      final t = Ticket.bought(journee, midi).validate(midi);
      expect(t.stateAt(DateTime(2026, 11, 6, 23, 0)), TicketState.enCours);
      expect(t.stateAt(DateTime(2026, 11, 7, 0, 1)), TicketState.epuise);
      expect(t.stateAt(DateTime(2026, 11, 7, 12, 0)), TicketState.epuise);
    });

    test('un titre relu depuis le stockage est identique à celui qu’on a rangé', () {
      final t = Ticket.bought(dix, midi).validate(midi);
      final relu = Ticket.tryFromJson(t.toJson())!;
      expect(relu.id, t.id);
      expect(relu.validatedAt, t.validatedAt);
      expect(relu.tripsLeft, t.tripsLeft);
      expect(relu.allDay, t.allDay);
      expect(relu.demo, isTrue);
    });
  });

  group('portefeuille', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('un titre acheté survit à un redémarrage', () async {
      final w = TicketWallet();
      await w.load();
      await w.buy(unite, midi);

      final autre = TicketWallet();
      await autre.load();
      expect(autre.tickets.length, 1);
      expect(autre.tickets.single.name, 'Ticket unitaire');
    });

    test('la validation est enregistrée, pas seulement affichée', () async {
      final w = TicketWallet();
      await w.load();
      final t = await w.buy(unite, midi);
      await w.validate(t.id, midi);

      final autre = TicketWallet();
      await autre.load();
      expect(autre.tickets.single.validatedAt, midi);
      expect(autre.tickets.single.stateAt(midi), TicketState.enCours);
    });

    test('les titres utilisables passent devant, voyage en cours en tête', () async {
      final w = TicketWallet();
      await w.load();
      await w.buy(unite, midi.subtract(const Duration(days: 1)));
      final recent = await w.buy(unite, midi);
      final enCours = await w.buy(dix, midi.subtract(const Duration(hours: 2)));
      await w.validate(enCours.id, midi.subtract(const Duration(minutes: 10)));

      final list = w.usable(midi);
      expect(list.first.id, enCours.id);
      expect(list[1].id, recent.id);
      expect(w.spent(midi), isEmpty);
    });

    test('un titre épuisé quitte la liste des utilisables', () async {
      final w = TicketWallet();
      await w.load();
      final t = await w.buy(unite, midi);
      await w.validate(t.id, midi);
      final tard = midi.add(const Duration(hours: 2));
      expect(w.usable(tard), isEmpty);
      expect(w.spent(tard).single.id, t.id);
    });

    test('effacer les titres de démonstration vide aussi le stockage', () async {
      final w = TicketWallet();
      await w.load();
      await w.buy(unite, midi);
      await w.clear();

      final autre = TicketWallet();
      await autre.load();
      expect(autre.tickets, isEmpty);
    });

    test('un stockage abîmé ne bloque pas l’écran', () async {
      SharedPreferences.setMockInitialValues({'demo_tickets': 'ceci n est pas du json'});
      final w = TicketWallet();
      await w.load();
      expect(w.tickets, isEmpty);
    });
  });

  test('le catalogue livré se lit, avec sa source et des prix plausibles', () {
    final f = FareCatalog.fromJsonString(File('assets/data/fares.json').readAsStringSync());
    expect(f.fares.length, greaterThanOrEqualTo(3));
    expect(f.source, isNotNull, reason: 'un tarif s’affiche avec la page d’où il vient');
    expect(f.fetched, isNotNull);
    for (final fare in f.fares) {
      expect(fare.priceCents, greaterThan(0));
      expect(fare.description.trim(), isNotEmpty);
    }
  });

  test('un titre ne peut pas être fabriqué autrement qu’en démonstration', () {
    // Le seul constructeur public d'achat marque le titre ; l'écran s'appuie dessus
    // pour l'étiqueter, et rien ne doit pouvoir produire un titre non étiqueté.
    expect(Ticket.bought(unite, midi).demo, isTrue);
    expect(Ticket.bought(journee, midi).validate(midi).demo, isTrue);
  });
}
