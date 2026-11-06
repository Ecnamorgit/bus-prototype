// Écran Plan et infos : le plan tracé depuis les données, et les informations avec lesquelles
// quelqu'un va agir — composer un numéro, ouvrir un lien. On vérifie ce qui serait composé.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/data/places.dart';
import 'package:monrezo_mvp/main.dart';

const _reseau = '''
{
 "network": {"name":"Test","generated":"2026-11-06","valid_from":"20260928","valid_to":"20270927","source":""},
 "stops": [{"id":"S1","name":"Gare","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Mairie","lat":46.81,"lon":4.43},
           {"id":"S3","name":"Hôpital","lat":46.82,"lon":4.45}],
 "routes": [{"id":"L1","short":"M9","long":"Gare - Hôpital","color":"#1CA23A","text":"#FFFFFF"},
            {"id":"L2","short":"C9","long":"Gare - Mairie","color":"#2E4694","text":"#FFFFFF"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20260101","end":"20271231","add":[],"remove":[]}},
 "patterns": [{"id":"PA","route":"L1","direction":0,"headsign":"Hôpital","stops":["S1","S2","S3"]},
              {"id":"PB","route":"L2","direction":0,"headsign":"Mairie","stops":["S1","S2"]}],
 "trips": [{"pattern":"PA","service":"TLJ","times":[480,485,492]}]
}
''';

const _infos = '''
{
 "source":"https://exemple.test/contact","fetched":"2026-11-06",
 "shops":[
  {"name":"Boutique du Creusot","address":"Esplanade Simone Veil, 71200 Le Creusot",
   "hours":["Du lundi au vendredi","9h00 – 12h30 et 13h30 – 17h00"],"phone":"03 85 73 01 10"}],
 "on_demand":{"title":"Transport à la demande","intro":"Un véhicule vient vous chercher.",
              "phone":"03 85 69 01 10","hours":["Centrale de réservation","9h00 – 16h00"],
              "rules":["Réservez la veille avant 16h."]},
 "email":"contact@exemple.test",
 "links":[{"label":"Site officiel du réseau","url":"https://exemple.test"}]
}
''';

void main() {
  final net = Network.fromJsonString(_reseau);
  final ouverts = <String>[];

  Widget app({Future<PracticalInfo> Function()? loader, double textScale = 1.0}) => MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: PlacesScreen(
              net: net,
              loader: loader ?? () async => PracticalInfo.fromJsonString(_infos),
              opener: (url) async {
                ouverts.add(url);
                return true;
              },
            ),
          ),
        ),
      );

  setUp(ouverts.clear);

  /// L'écran est long : il faut amener l'élément à l'écran avant de le toucher.
  Future<void> jusqua(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('la boutique s’affiche avec son adresse, ses horaires et son numéro', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Boutique du Creusot'), findsOneWidget);
    expect(find.text('Esplanade Simone Veil, 71200 Le Creusot'), findsOneWidget);
    expect(find.text('9h00 – 12h30 et 13h30 – 17h00'), findsOneWidget);
    expect(find.text('03 85 73 01 10'), findsOneWidget);
  });

  testWidgets('toucher le numéro compose bien ce numéro-là', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await jusqua(tester, find.text('03 85 73 01 10'));
    await tester.tap(find.text('03 85 73 01 10'));
    await tester.pumpAndSettle();
    expect(ouverts, ['tel:+33385730110']);
  });

  testWidgets('le transport à la demande donne son numéro et ses règles', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await jusqua(tester, find.text('Réserver au 03 85 69 01 10'));
    expect(find.text('Réserver au 03 85 69 01 10'), findsOneWidget);
    expect(find.text('Réservez la veille avant 16h.'), findsOneWidget);

    await tester.tap(find.text('Réserver au 03 85 69 01 10'));
    await tester.pumpAndSettle();
    expect(ouverts, ['tel:+33385690110']);
  });

  testWidgets('un lien officiel s’ouvre tel qu’il est écrit', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await jusqua(tester, find.text('Site officiel du réseau'));
    await tester.tap(find.text('Site officiel du réseau'));
    await tester.pumpAndSettle();
    expect(ouverts, ['https://exemple.test']);
  });

  testWidgets('le plan est tracé, et une ligne peut être isolée', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(NetworkMap), findsOneWidget);
    expect(find.textContaining('Touchez une ligne'), findsOneWidget);
    expect(find.textContaining('les parcours réels suivent les rues'), findsOneWidget);

    await tester.tap(find.text('M9').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ligne isolée'), findsOneWidget);

    await tester.tap(find.text('M9').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Touchez une ligne'), findsOneWidget);
  });

  testWidgets('« Agrandir » ouvre le plan en grand', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await jusqua(tester, find.text('Agrandir'));
    await tester.tap(find.text('Agrandir'));
    await tester.pumpAndSettle();

    expect(find.text('Plan du réseau'), findsWidgets);
    expect(find.byType(NetworkMap), findsOneWidget);
  });

  testWidgets('la provenance et la validité des données sont affichées', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await jusqua(tester, find.textContaining('valables du 28/09/2026'));
    expect(find.textContaining('valables du 28/09/2026 au 27/09/2027'), findsOneWidget);
    expect(find.textContaining('relevés le 06/11/2026'), findsOneWidget);
    expect(find.textContaining('n’envoie aucune donnée'), findsOneWidget);
  });

  testWidgets('informations illisibles : message d’erreur et bouton Réessayer', (tester) async {
    var essais = 0;
    await tester.pumpWidget(MaterialApp(
      home: PlacesScreen(
        net: net,
        loader: () async {
          essais++;
          if (essais == 1) throw const FormatException('fichier abîmé');
          return PracticalInfo.fromJsonString(_infos);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Informations indisponibles'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Boutique du Creusot'), findsOneWidget);
  });

  testWidgets('un réseau sans arrêt n’affiche pas un plan vide sans explication', (tester) async {
    final vide = Network.fromJsonString(
        '{"network":{"name":"V","generated":"","valid_from":"","valid_to":"","source":""},'
        '"stops":[],"routes":[],"services":{},"patterns":[],"trips":[]}');
    await tester.pumpWidget(MaterialApp(
      home: PlacesScreen(net: vide, loader: () async => PracticalInfo.fromJsonString(_infos)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aucun arrêt à afficher.'), findsOneWidget);
  });

  testWidgets('texte à 1,6× sur 375 px : aucun débordement', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(textScale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await jusqua(tester, find.text('Réservez la veille avant 16h.'));
    expect(tester.takeException(), isNull);
  });
}
