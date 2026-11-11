// Écran Prochains passages : l'écran d'accueil. Les six états de la géolocalisation, le badge
// « horaires prévus », les favoris, et le texte à 1,6×.
//
// Les horaires du réseau d'essai sont calculés à partir de l'heure du test : l'écran lit
// l'horloge du téléphone, un jeu de données figé ne montrerait jamais de départ.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/location.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/data/schedule.dart';
import 'package:monrezo_mvp/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minute de la journée au moment du test : les horaires du réseau d'essai s'y accrochent.
late int baseMinute;

String _hhmmA(int minutes) {
  final mm = minutes % 1440;
  return '${(mm ~/ 60).toString().padLeft(2, '0')}:${(mm % 60).toString().padLeft(2, '0')}';
}

String _reseauDuJour() {
  final now = DateTime.now();
  final m = now.hour * 60 + now.minute;
  baseMinute = m;
  return '''
{
 "network": {"name":"Test","generated":"2026-11-06","valid_from":"20200101","valid_to":"20301231","source":""},
 "stops": [{"id":"S1","name":"Gare Routière","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Mairie","lat":46.8060,"lon":4.42},
           {"id":"S3","name":"Hôpital","lat":46.8120,"lon":4.42}],
 "routes": [{"id":"L1","short":"M9","long":"Gare - Hôpital","color":"#1CA23A","text":"#FFFFFF"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20200101","end":"20301231","add":[],"remove":[]}},
 "patterns": [{"id":"PA","route":"L1","direction":0,"headsign":"Hôpital","stops":["S1","S2","S3"]}],
 "trips": [{"pattern":"PA","service":"TLJ","times":[${m + 5},${m + 8},${m + 12}]},
           {"pattern":"PA","service":"TLJ","times":[${m + 35},${m + 38},${m + 42}]}]
}
''';
}

/// Position à environ 200 m au nord de la Gare Routière.
Future<LocationResult> _positionProche() async => const LocationResult(LocationStatus.found, lat: 46.8018, lon: 4.42);

/// Réseau dont le service existe tous les jours SAUF aujourd'hui : c'est exactement le
/// dimanche et le jour férié du réseau réel. Les horaires sont fixes (08:00, 08:30) et non
/// calés sur l'heure du test, puisqu'on affiche une journée entière depuis minuit.
String _reseauSansBusAujourdhui() {
  final d = DateTime.now();
  final iso = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  return '''
{
 "network": {"name":"Test","generated":"2026-11-06","valid_from":"20200101","valid_to":"20301231","source":""},
 "stops": [{"id":"S1","name":"Gare Routière","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Mairie","lat":46.8060,"lon":4.42},
           {"id":"S3","name":"Hôpital","lat":46.8120,"lon":4.42}],
 "routes": [{"id":"L1","short":"M9","long":"Gare - Hôpital","color":"#1CA23A","text":"#FFFFFF"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20200101","end":"20301231","add":[],"remove":["$iso"]}},
 "patterns": [{"id":"PA","route":"L1","direction":0,"headsign":"Hôpital","stops":["S1","S2","S3"]}],
 "trips": [{"pattern":"PA","service":"TLJ","times":[480,483,487]},
           {"pattern":"PA","service":"TLJ","times":[510,513,517]}]
}
''';
}

void main() {
  late Network net;
  late Schedule sched;
  late Favorites favorites;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    net = Network.fromJsonString(_reseauDuJour());
    sched = Schedule(net);
    favorites = Favorites();
    await favorites.load();
  });

  Widget app({LocationProbe? probe, double textScale = 1.0}) => MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: DeparturesScreen(
              net: net,
              sched: sched,
              favorites: favorites,
              onChanged: () {},
              probe: probe,
            ),
          ),
        ),
      );

  group('écran d’accueil vide', () {
    testWidgets('propose les deux portes d’entrée, et dit où va la position', (tester) async {
      await tester.pumpWidget(app(probe: _positionProche));
      await tester.pumpAndSettle();

      expect(find.text('Vos arrêts, vos prochains bus'), findsOneWidget);
      expect(find.text('Arrêts près de moi'), findsOneWidget);
      expect(find.text('Chercher un arrêt'), findsOneWidget);
      expect(find.textContaining('reste sur le téléphone'), findsOneWidget);
    });

    testWidgets('la position n’est jamais demandée toute seule', (tester) async {
      var demandes = 0;
      await tester.pumpWidget(app(probe: () async {
        demandes++;
        return _positionProche();
      }));
      await tester.pumpAndSettle();
      expect(demandes, 0, reason: 'une demande de position au lancement se fait refuser');

      await tester.tap(find.text('Arrêts près de moi'));
      await tester.pumpAndSettle();
      expect(demandes, 1);
    });
  });

  group('arrêts proches', () {
    testWidgets('l’arrêt le plus proche s’affiche avec sa distance et ses départs', (tester) async {
      await tester.pumpWidget(app(probe: _positionProche));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrêts près de moi'));
      await tester.pumpAndSettle();

      expect(find.text('Le plus proche de vous'), findsOneWidget);
      expect(find.text('Gare Routière'), findsOneWidget);
      expect(find.text('à 200 m'), findsOneWidget);
      // L'heure prévue est déterministe ; le « dans N minutes » dépend de la seconde courante.
      expect(find.text(_hhmmA(baseMinute + 5)), findsWidgets);
      expect(find.text('vers Hôpital'), findsWidgets);
      // Les deux autres arrêts proches sont proposés en dessous.
      expect(find.text('Mairie'), findsOneWidget);
      expect(find.text('Hôpital'), findsOneWidget);
    });

    testWidgets('un arrêt proche peut devenir favori d’un geste', (tester) async {
      await tester.pumpWidget(app(probe: _positionProche));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrêts près de moi'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Ajouter aux favoris').first);
      await tester.pumpAndSettle();
      expect(favorites.contains('S1'), isTrue);

      final autre = Favorites();
      await autre.load();
      expect(autre.ids, ['S1'], reason: 'un favori doit survivre au redémarrage');
    });
  });

  group('la géolocalisation rate', () {
    Future<void> verifie(WidgetTester tester, LocationStatus statut, String extrait, {required String bouton}) async {
      await tester.pumpWidget(app(probe: () async => LocationResult(statut)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrêts près de moi'));
      await tester.pumpAndSettle();

      expect(find.textContaining(extrait), findsOneWidget);
      expect(find.text(bouton), findsOneWidget, reason: 'l’usager doit savoir quoi faire ensuite');
    }

    testWidgets('refusée : on peut réessayer', (tester) async {
      await verifie(tester, LocationStatus.denied, 'Position refusée', bouton: 'Réessayer la position');
    });

    testWidgets('refusée définitivement : on renvoie aux réglages, pas à un bouton inutile', (tester) async {
      await verifie(tester, LocationStatus.deniedForever, 'réglages du téléphone', bouton: 'Chercher un arrêt');
      expect(find.text('Réessayer la position'), findsNothing);
    });

    testWidgets('localisation coupée sur le téléphone', (tester) async {
      await verifie(tester, LocationStatus.serviceDisabled, 'localisation est désactivée', bouton: 'Chercher un arrêt');
    });

    testWidgets('position introuvable : on peut réessayer', (tester) async {
      await verifie(tester, LocationStatus.unavailable, 'Position introuvable', bouton: 'Réessayer la position');
    });

    testWidgets('pendant la recherche, l’écran le dit', (tester) async {
      await tester.pumpWidget(app(probe: () async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return _positionProche();
      }));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrêts près de moi'));
      await tester.pump();

      expect(find.textContaining('Recherche de votre position'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Le plus proche de vous'), findsOneWidget);
    });
  });

  // Le 11 novembre, et tous les dimanches, le réseau ne circule pas. L'écran affichait
  // alors « Pas de passage prévu dans les 3 prochaines heures » sur chaque arrêt : exact à
  // la lettre, mais un décideur qui ouvre l'application ce jour-là lit une panne.
  group('jour sans bus', () {
    late Network mort;

    Widget ecran({double textScale = 1.0}) => MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: DeparturesScreen(
                net: mort,
                sched: Schedule(mort),
                favorites: favorites,
                onChanged: () {},
              ),
            ),
          ),
        );

    setUp(() => mort = Network.fromJsonString(_reseauSansBusAujourdhui()));

    testWidgets('le dit, et montre les premiers départs du jour de reprise', (tester) async {
      await favorites.toggle('S1');
      await tester.pumpWidget(ecran());
      await tester.pumpAndSettle();

      expect(find.textContaining('Le réseau ne circule pas aujourd’hui'), findsOneWidget);
      expect(find.textContaining('Premiers départs'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.textContaining('Pas de passage prévu'), findsNothing);
    });

    testWidgets('texte à 1,6× sur 375 px : le bandeau ne déborde pas', (tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await favorites.toggle('S1');
      await tester.pumpWidget(ecran(textScale: 1.6));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('favoris', () {
    testWidgets('un favori affiche ses prochains passages et le badge « horaires prévus »', (tester) async {
      await favorites.toggle('S2');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Mairie'), findsOneWidget);
      expect(find.text('horaires prévus'), findsOneWidget);
      expect(find.text(_hhmmA(baseMinute + 8)), findsWidgets);
      expect(find.textContaining('Aucun temps réel'), findsOneWidget);
    });

    testWidgets('un favori sans passage le dit au lieu de rester vide', (tester) async {
      // Réseau sans aucune course aujourd'hui.
      final mort = Network.fromJsonString(_reseauDuJour().replaceAll('"days":[1,1,1,1,1,1,1]', '"days":[0,0,0,0,0,0,0]'));
      await favorites.toggle('S1');
      await tester.pumpWidget(MaterialApp(
        home: DeparturesScreen(net: mort, sched: Schedule(mort), favorites: favorites, onChanged: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de passage prévu'), findsOneWidget);
    });

    testWidgets('un favori périmé est ignoré, jamais remplacé par un autre arrêt', (tester) async {
      // Cas réel : un identifiant enregistré avant un changement de données.
      SharedPreferences.setMockInitialValues({'flutter.favorite_stops': <String>['S404']});
      final f = Favorites();
      await f.load();
      await tester.pumpWidget(MaterialApp(
        home: DeparturesScreen(net: net, sched: sched, favorites: f, onChanged: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Vos arrêts, vos prochains bus'), findsOneWidget);
      expect(find.text('Gare Routière'), findsNothing);
    });
  });

  testWidgets('l’heure du téléphone est affichée', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    expect(find.text(hhmm), findsOneWidget);
  });

  testWidgets('texte à 1,6× sur 375 px : aucun débordement', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await favorites.toggle('S2');
    await tester.pumpWidget(app(probe: _positionProche, textScale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Autour de vous'), 250, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrêts près de moi'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('un arrêt déjà en favori ne se répète pas dans « Autour de vous »', (tester) async {
    await favorites.toggle('S1'); // le plus proche
    await tester.pumpWidget(app(probe: _positionProche));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Arrêts près de moi'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Arrêts près de moi'));
    await tester.pumpAndSettle();

    // S1 est en haut, en favori : « Autour de vous » enchaîne sur le suivant.
    expect(find.text('Gare Routière'), findsOneWidget);
    expect(find.text('Le plus proche de vous'), findsOneWidget);
    expect(find.text('Mairie'), findsWidgets);
  });

  testWidgets('quand tout est déjà en favori, on le dit au lieu de répéter', (tester) async {
    for (final id in ['S1', 'S2', 'S3']) {
      await favorites.toggle(id);
    }
    await tester.pumpWidget(app(probe: _positionProche));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Arrêts près de moi'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Arrêts près de moi'));
    await tester.pumpAndSettle();

    expect(find.textContaining('déjà dans vos favoris'), findsOneWidget);
    expect(find.text('Le plus proche de vous'), findsNothing);
  });
}
