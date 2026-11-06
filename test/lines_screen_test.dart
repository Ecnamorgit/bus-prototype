// Test de widget de l'écran Lignes, sur un réseau fictif à variantes : c'est le cas qui casse
// (une ligne a plusieurs parcours par sens, et le plus long n'est pas le principal).
// Vérifie aussi que l'écran tient à 1,6× de taille de texte sur un écran de 375 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/data/schedule.dart';
import 'package:monrezo_mvp/main.dart';

const _json = '''
{
 "network": {"name":"Test","generated":"2026-11-06","valid_from":"20260101","valid_to":"20271231","source":""},
 "stops": [{"id":"S1","name":"Gare","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Mairie","lat":46.81,"lon":4.43},
           {"id":"S3","name":"Hôpital Jean Bouveri","lat":46.82,"lon":4.44},
           {"id":"S4","name":"Zone industrielle","lat":46.83,"lon":4.45}],
 "routes": [{"id":"L1","short":"M9","long":"Saint-Vallier < > Montceau-les-Mines","color":"#00B6E8","text":"#FFFFFF"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20260101","end":"20271231","add":[],"remove":[]}},
 "patterns": [{"id":"PA","route":"L1","direction":0,"headsign":"Hôpital Jean Bouveri","stops":["S1","S2","S3"]},
              {"id":"PB","route":"L1","direction":0,"headsign":"Zone industrielle","stops":["S1","S2","S4","S3"]},
              {"id":"PC","route":"L1","direction":1,"headsign":"Gare","stops":["S3","S2","S1"]}],
 "trips": [{"pattern":"PA","service":"TLJ","times":[480,485,492]},
           {"pattern":"PA","service":"TLJ","times":[510,515,522]},
           {"pattern":"PA","service":"TLJ","times":[540,545,552]},
           {"pattern":"PB","service":"TLJ","times":[495,500,505,512]},
           {"pattern":"PC","service":"TLJ","times":[600,607,612]}]
}
''';

Widget _app(Network net, {double textScale = 1.0}) {
  final sched = Schedule(net);
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: LinesScreen(net: net, sched: sched, favorites: Favorites(), onChanged: () {}),
      ),
    ),
  );
}

void main() {
  final net = Network.fromJsonString(_json);

  testWidgets('la liste montre la ligne, son numéro et son nom lisible', (tester) async {
    await tester.pumpWidget(_app(net));
    expect(find.text('M9'), findsOneWidget);
    // Le GTFS écrit « Saint-Vallier < > Montceau-les-Mines ».
    expect(find.text('Saint-Vallier ↔ Montceau-les-Mines'), findsOneWidget);
    expect(find.textContaining('4 arrêts'), findsOneWidget);
  });

  testWidgets('la ligne mène aux arrêts du sens principal, pas du parcours le plus long', (tester) async {
    await tester.pumpWidget(_app(net));
    await tester.tap(find.text('Saint-Vallier ↔ Montceau-les-Mines'));
    await tester.pumpAndSettle();

    // PB est plus long (4 arrêts) mais ne porte qu'une course sur quatre : la direction
    // affichée doit être celle de PA.
    expect(find.text('Hôpital Jean Bouveri'), findsWidgets);
    expect(find.text('Zone industrielle'), findsOneWidget); // présent comme arrêt, pas comme direction
    expect(find.text('Certains bus seulement'), findsOneWidget);
  });

  testWidgets('un arrêt ouvre la grille du jour, toutes variantes du sens réunies', (tester) async {
    await tester.pumpWidget(_app(net));
    await tester.tap(find.text('Saint-Vallier ↔ Montceau-les-Mines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mairie'));
    await tester.pumpAndSettle();

    expect(find.text('horaires prévus'), findsOneWidget);
    // Les trois courses de PA et celle de PB, groupées par destination.
    expect(find.text('08:05'), findsOneWidget);
    expect(find.text('08:20'), findsOneWidget); // la variante
    expect(find.text('08:35'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    expect(find.textContaining('vers Zone industrielle'), findsOneWidget);
  });

  testWidgets('le terminus du sens n’affiche aucun départ', (tester) async {
    await tester.pumpWidget(_app(net));
    await tester.tap(find.text('Saint-Vallier ↔ Montceau-les-Mines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hôpital Jean Bouveri').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Pas de passage aujourd’hui'), findsOneWidget);
  });

  testWidgets('texte à 1,6× sur 375 px : aucun débordement', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(net, textScale: 1.6));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Saint-Vallier ↔ Montceau-les-Mines'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Mairie'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('une ligne sans service aujourd’hui le dit, et montre quand même son tracé', (tester) async {
    // Même réseau, mais aucun jour de circulation : c'est l'état « pas de bus aujourd'hui ».
    final dormant = Network.fromJsonString(_json.replaceAll('"days":[1,1,1,1,1,1,1]', '"days":[0,0,0,0,0,0,0]'));
    await tester.pumpWidget(_app(dormant));
    expect(find.text('Pas de bus aujourd’hui'), findsOneWidget);

    await tester.tap(find.text('Saint-Vallier ↔ Montceau-les-Mines'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun bus dans ce sens aujourd’hui'), findsOneWidget);
    expect(find.text('Mairie'), findsOneWidget); // le tracé reste affiché

    await tester.tap(find.text('Mairie'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pas de passage aujourd’hui'), findsOneWidget);
  });

  testWidgets('« Changer de sens » renverse la ligne', (tester) async {
    await tester.pumpWidget(_app(net));
    await tester.tap(find.text('Saint-Vallier ↔ Montceau-les-Mines'));
    await tester.pumpAndSettle();
    expect(find.text('Hôpital Jean Bouveri'), findsWidgets);

    await tester.tap(find.byTooltip('Changer de sens'));
    await tester.pumpAndSettle();

    // Sens retour : destination Gare, et le détour n'existe pas dans ce sens.
    expect(find.text('Gare'), findsWidgets);
    expect(find.text('Certains bus seulement'), findsNothing);
  });
}
