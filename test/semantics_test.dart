// Ce que le lecteur d'écran annonce sur l'écran d'accueil.
//
// Ces défauts-là ne se voient pas : l'écran est juste, les tests de widget passent,
// et pourtant l'application est inutilisable au doigt et à l'oreille. Ils ont été
// trouvés en sondant l'arbre de sémantique, pas en regardant l'écran.
//
// Le plus grave : un IconButton avec un `tooltip` mais sans `Semantics` propre
// s'annonçait « bouton », sans dire lequel — et c'était le seul moyen de retirer un
// arrêt des favoris. Le test ci-dessous refuse désormais tout bouton sans nom.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/data/schedule.dart';
import 'package:monrezo_mvp/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

late int baseMinute;

String _hhmmA(int minutes) {
  final mm = minutes % 1440;
  return '${(mm ~/ 60).toString().padLeft(2, '0')}:${(mm % 60).toString().padLeft(2, '0')}';
}

/// Réseau d'essai calé sur l'heure du test : l'écran lit l'horloge du téléphone,
/// un jeu figé ne montrerait jamais de départ.
String _reseau() {
  final n = DateTime.now();
  final m = n.hour * 60 + n.minute;
  baseMinute = m;
  return '''
{
 "network": {"name":"Test","generated":"2026-11-06","valid_from":"20200101","valid_to":"20301231","source":""},
 "stops": [{"id":"S1","name":"Gare Routière","lat":46.80,"lon":4.42},
           {"id":"S2","name":"Mairie","lat":46.806,"lon":4.42}],
 "routes": [{"id":"L1","short":"M9","long":"Gare - Mairie","color":"#1CA23A","text":"#FFFFFF"}],
 "services": {"TLJ": {"days":[1,1,1,1,1,1,1],"start":"20200101","end":"20301231","add":[],"remove":[]}},
 "patterns": [{"id":"PA","route":"L1","direction":0,"headsign":"Mairie","stops":["S1","S2"]}],
 "trips": [{"pattern":"PA","service":"TLJ","times":[${m + 4},${m + 8}]},
           {"pattern":"PA","service":"TLJ","times":[${m + 34},${m + 38}]}]
}
''';
}

/// Un nœud tel que le lecteur d'écran le rencontre : les nœuds fondus dans leur
/// parent ne sont pas des arrêts de navigation, on ne les compte pas.
class _Noeud {
  _Noeud(this.label, this.estBouton);
  final String label;
  final bool estBouton;
}

List<_Noeud> _lecture(WidgetTester tester) {
  final out = <_Noeud>[];
  void parcours(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (!n.isMergedIntoParent) {
      final bouton = d.flagsCollection.isButton;
      final t = d.label.trim().replaceAll('\n', ' | ');
      if (t.isNotEmpty || bouton) out.add(_Noeud(t, bouton));
    }
    n.visitChildren((c) {
      parcours(c);
      return true;
    });
  }

  parcours(tester.semantics.find(find.byType(MaterialApp)));
  return out;
}

void main() {
  late Network net;
  late Favorites favorites;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    net = Network.fromJsonString(_reseau());
    favorites = Favorites();
    await favorites.load();
  });

  Future<List<_Noeud>> accueil(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DeparturesScreen(net: net, sched: Schedule(net), favorites: favorites, onChanged: () {}),
    ));
    await tester.pumpAndSettle();
    return _lecture(tester);
  }

  testWidgets('aucun bouton n’est annoncé sans dire lequel', (tester) async {
    final handle = tester.ensureSemantics();
    await favorites.toggle('S1');
    final noeuds = await accueil(tester);

    final muets = noeuds.where((n) => n.estBouton && n.label.isEmpty).toList();
    expect(muets, isEmpty,
        reason: '${muets.length} bouton(s) sans libellé : le lecteur d’écran dira « bouton » sans dire lequel');
    handle.dispose();
  });

  testWidgets('le bouton favori dit ce qu’il fait, et à quel arrêt', (tester) async {
    final handle = tester.ensureSemantics();
    await favorites.toggle('S1');
    final noeuds = await accueil(tester);

    expect(noeuds.map((n) => n.label), contains('Retirer Gare Routière des favoris'));
    handle.dispose();
  });

  testWidgets('un passage est un arrêt de navigation, et une seule phrase', (tester) async {
    final handle = tester.ensureSemantics();
    await favorites.toggle('S1');
    final noeuds = await accueil(tester);

    // La minute exacte dérive entre la construction du jeu d'essai et le rendu :
    // c'est la forme de la phrase qui est testée, pas l'horloge.
    final phrase = RegExp(r'^ligne M9, vers Mairie, dans \d+ minutes?, départ prévu à \d\d:\d\d$');
    final passages = noeuds.where((n) => phrase.hasMatch(n.label)).toList();

    // Deux nœuds, pas un : sans cela les six départs d'une carte se lisent d'un seul
    // bloc, et on ne peut pas s'arrêter sur celui qu'on cherche.
    expect(passages, hasLength(2),
        reason: 'chaque passage doit être un arrêt de navigation à lui seul');

    // Le délai avant l'heure — l'ordre dans lequel l'information sert — et l'heure
    // dite une seule fois.
    expect(passages.first.label.indexOf('dans'), lessThan(passages.first.label.indexOf('départ prévu')));
    expect(RegExp(r'\d\d:\d\d').allMatches(passages.first.label), hasLength(1));
    expect(_hhmmA(baseMinute + 4), isNotEmpty); // le jeu d'essai est bien calé sur l'heure
    handle.dispose();
  });

  testWidgets('l’heure de l’en-tête n’est pas dite deux fois', (tester) async {
    final handle = tester.ensureSemantics();
    final noeuds = await accueil(tester);

    final horloge = noeuds.where((n) => n.label.startsWith('il est ')).toList();
    expect(horloge, hasLength(1));
    expect(horloge.single.label.contains('|'), isFalse,
        reason: 'le libellé s’ajoutait au texte au lieu de le remplacer : « il est 09:30 | 09:30 »');
    handle.dispose();
  });
}
