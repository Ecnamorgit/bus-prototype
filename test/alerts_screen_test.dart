// Écran Infos trafic : les trois états (chargement, erreur, vide), l'étiquetage des données
// d'exemple, et le texte à 1,6× sur 375 px.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/alerts.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/main.dart';

const _reseau = '''
{
 "network": {"name":"Test","generated":"2026-11-06","valid_from":"20260101","valid_to":"20271231","source":""},
 "stops": [{"id":"S1","name":"Gare","lat":46.80,"lon":4.42},{"id":"S2","name":"Mairie","lat":46.81,"lon":4.43}],
 "routes": [{"id":"L1","short":"M9","long":"Gare - Mairie","color":"#1CA23A","text":"#FFFFFF"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20260101","end":"20271231","add":[],"remove":[]}},
 "patterns": [{"id":"PA","route":"L1","direction":0,"headsign":"Mairie","stops":["S1","S2"]}],
 "trips": [{"pattern":"PA","service":"TLJ","times":[480,485]}]
}
''';

// Une alerte en cours, une à venir, une terminée — avec des dates relatives au jour du test,
// pour que ce test ne pourrisse pas en décembre.
String _fluxDuJour() {
  final now = DateTime.now();
  String d(int days) {
    final x = now.add(Duration(days: days));
    return '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  }

  return '''
{"alerts": [
  {"id":"en-cours","severity":"severe","lines":["M9"],"title":"Place fermée","body":"Les bus sont déviés.",
   "from":"${d(-2)}","to":"${d(3)}","updated":"${d(-1)}T17:40","example":true},
  {"id":"a-venir","severity":"warning","lines":[],"title":"Marché de Noël","body":"Arrêt déplacé.",
   "from":"${d(20)}","to":"${d(30)}","updated":"${d(-3)}T09:15","example":true},
  {"id":"termine","severity":"warning","lines":["M9"],"title":"Vieille déviation","body":"Finie.",
   "from":"${d(-20)}","to":"${d(-5)}","updated":"${d(-5)}T18:00","example":true}
]}''';
}

Widget _app(Network net, Future<AlertFeed> Function() loader, {double textScale = 1.0}) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: AlertsScreen(net: net, loader: loader),
        ),
      ),
    );

void main() {
  final net = Network.fromJsonString(_reseau);
  Future<AlertFeed> duJour() async => AlertFeed.fromJsonString(_fluxDuJour());

  testWidgets('pendant le chargement, un indicateur, pas un écran vide', (tester) async {
    final completer = Completer<AlertFeed>();
    await tester.pumpWidget(_app(net, () => completer.future));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(AlertFeed.fromJsonString('{"alerts": []}'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('aucune alerte : l’écran rassure au lieu d’avoir l’air cassé', (tester) async {
    await tester.pumpWidget(_app(net, () async => AlertFeed.fromJsonString('{"alerts": []}')));
    await tester.pumpAndSettle();
    expect(find.text('Aucune perturbation'), findsOneWidget);
    expect(find.textContaining('Aucune information trafic'), findsOneWidget);
  });

  testWidgets('flux illisible : message d’erreur et bouton Réessayer qui relance', (tester) async {
    var essais = 0;
    await tester.pumpWidget(_app(net, () async {
      essais++;
      if (essais == 1) throw const FormatException('fichier abîmé');
      return AlertFeed.fromJsonString('{"alerts": []}');
    }));
    await tester.pumpAndSettle();
    expect(find.text('Informations indisponibles'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune perturbation'), findsOneWidget);
    expect(essais, 2);
  });

  testWidgets('les alertes du jour sont classées, les terminées ont disparu', (tester) async {
    await tester.pumpWidget(_app(net, duJour));
    await tester.pumpAndSettle();

    expect(find.text('En cours (1)'), findsOneWidget);
    expect(find.text('À venir (1)'), findsOneWidget);
    expect(find.text('Place fermée'), findsOneWidget);
    expect(find.text('Marché de Noël'), findsOneWidget);
    expect(find.text('Vieille déviation'), findsNothing);
  });

  testWidgets('chaque donnée simulée est étiquetée, bandeau et carte', (tester) async {
    await tester.pumpWidget(_app(net, duJour));
    await tester.pumpAndSettle();

    expect(find.textContaining('Démonstration'), findsOneWidget);
    // Une étiquette par carte : un bandeau seul ne suit pas une capture d'écran.
    expect(find.text('exemple'), findsNWidgets(2));
    expect(find.text('M9'), findsOneWidget); // la ligne concernée, par son nom public
    expect(find.text('Tout le réseau'), findsOneWidget); // alerte sans ligne précisée
  });

  testWidgets('une carte ouvre le détail, avec sa date de mise à jour', (tester) async {
    await tester.pumpWidget(_app(net, duJour));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place fermée'));
    await tester.pumpAndSettle();

    expect(find.text('Les bus sont déviés.'), findsOneWidget);
    expect(find.textContaining('Mis à jour le'), findsOneWidget);
    expect(find.textContaining('Information d’exemple'), findsOneWidget);
  });

  testWidgets('texte à 1,6× sur 375 px : aucun débordement', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(net, duJour, textScale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Place fermée'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('le vrai fichier livré s’affiche sans erreur', (tester) async {
    // Lu depuis le disque : le test vérifie le contenu réellement embarqué.
    final feed = AlertFeed.fromJsonString(File('assets/data/alerts.json').readAsStringSync());
    await tester.pumpWidget(_app(net, () async => feed));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Démonstration'), findsOneWidget);
  });

  testWidgets('un badge de ligne garde sa taille de badge', (tester) async {
    // Dans une Row, le badge se serrait tout seul ; dans le Wrap des alertes, il s'étirait sur
    // toute la largeur de la carte. Une ligne de bus n'est pas une bannière.
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(net, duJour));
    await tester.pumpAndSettle();

    final taille = tester.getSize(find.byType(RouteBadge).first);
    expect(taille.width, lessThan(90), reason: 'badge étiré sur la largeur de la carte');
    expect(taille.width, greaterThanOrEqualTo(32));
  });
}
