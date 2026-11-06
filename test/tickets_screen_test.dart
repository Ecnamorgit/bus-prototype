// Écran Mes titres : portefeuille vide, parcours d'achat simulé, titre et validation.
// Deux garde-fous qui comptent plus que le reste :
//   - aucun champ de saisie dans tout le parcours (jamais de formulaire de paiement, même faux) ;
//   - l'étiquetage « démonstration » présent à chaque étape.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/tickets.dart';
import 'package:monrezo_mvp/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tarifs = '''
{
 "source": "https://exemple.test/tarifs",
 "fetched": "2026-11-06",
 "fares": [
  {"id":"unite","name":"Ticket unitaire","price_cents":120,"description":"Un trajet, correspondances comprises pendant 60 minutes.",
   "trips":1,"validity_minutes":60,"all_day":false,"note":""},
  {"id":"dix","name":"Titre 10 voyages","price_cents":900,"description":"Dix trajets.",
   "trips":10,"validity_minutes":60,"all_day":false,"note":"En boutique aujourd'hui."},
  {"id":"journee","name":"Ticket journée","price_cents":360,"description":"Voyages illimités jusqu'à la fin de la journée.",
   "trips":0,"validity_minutes":0,"all_day":true,"note":""}
 ]
}
''';

Widget _app({Future<FareCatalog> Function()? loader, double textScale = 1.0}) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: TicketsScreen(catalogLoader: loader ?? () async => FareCatalog.fromJsonString(_tarifs)),
        ),
      ),
    );

/// Déroule tout le parcours d'achat jusqu'au titre affiché.
Future<void> _acheterUnTicket(WidgetTester tester) async {
  await tester.tap(find.text('Acheter un titre').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ticket unitaire'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Payer (simulation)'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('portefeuille vide : on dit quoi faire, pas « rien à afficher »', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Aucun titre'), findsOneWidget);
    expect(find.textContaining('sans compte'), findsOneWidget);
    expect(find.textContaining('aucun paiement réel'), findsOneWidget);
  });

  testWidgets('le catalogue montre les trois titres et leurs prix, avec la source', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acheter un titre').last);
    await tester.pumpAndSettle();

    expect(find.text('Ticket unitaire'), findsOneWidget);
    expect(find.text('1,20 €'), findsOneWidget);
    expect(find.text('9 €'), findsOneWidget);
    expect(find.text('3,60 €'), findsOneWidget);
    expect(find.textContaining('relevés le 06/11/2026'), findsOneWidget);
  });

  testWidgets('acheter donne un titre à valider, étiqueté démonstration', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _acheterUnTicket(tester);

    expect(find.text('À valider à la montée'), findsOneWidget);
    expect(find.textContaining('n’est pas valable à bord'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets); // le QR factice
    expect(find.text('Valider mon voyage'), findsOneWidget);
  });

  testWidgets('aucun champ de saisie dans tout le parcours d’achat', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Acheter un titre').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Ticket unitaire'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'un récapitulatif ne demande pas de numéro de carte');
    expect(find.textContaining('Aucun numéro de carte'), findsOneWidget);

    await tester.tap(find.text('Payer (simulation)'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('valider lance le voyage, après confirmation', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _acheterUnTicket(tester);

    await tester.tap(find.text('Valider mon voyage'));
    await tester.pumpAndSettle();
    expect(find.text('Commencer le voyage ?'), findsOneWidget);

    // On peut renoncer : rien n'est consommé.
    await tester.tap(find.text('Pas encore'));
    await tester.pumpAndSettle();
    expect(find.text('À valider à la montée'), findsOneWidget);

    await tester.tap(find.text('Valider mon voyage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Voyage en cours'), findsOneWidget);
    expect(find.text('59 min'), findsOneWidget); // le compte à rebours tourne
    expect(find.text('Valider mon voyage'), findsNothing);
  });

  testWidgets('le titre acheté est retrouvé au retour, et reste après rechargement', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _acheterUnTicket(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ticket unitaire'), findsOneWidget);
    expect(find.text('1 voyage restant'), findsOneWidget);

    // Nouvel écran, même stockage : le titre est toujours là.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Ticket unitaire'), findsOneWidget);
  });

  testWidgets('effacer les titres de démonstration ramène à l’écran vide', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _acheterUnTicket(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Effacer les titres de démonstration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Effacer'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun titre'), findsOneWidget);
  });

  testWidgets('tarifs illisibles : message d’erreur, pas de catalogue vide', (tester) async {
    await tester.pumpWidget(_app(loader: () async => throw const FormatException('fichier abîmé')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acheter un titre').last);
    await tester.pumpAndSettle();

    expect(find.text('Tarifs indisponibles'), findsOneWidget);
    expect(find.text('Revenir'), findsOneWidget);
  });

  testWidgets('texte à 1,6× sur 375 px : aucun débordement', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(textScale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _acheterUnTicket(tester);
    expect(tester.takeException(), isNull);
  });
}
