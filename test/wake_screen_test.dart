// Écran d'alarme d'arrivée : l'usager se déplace, l'écran suit.
//
// L'alarme se déclenche sur la position : le test déplace donc l'usager, relevé après
// relevé, sans bouger de la pièce. Le minuteur tourne toutes les 5 secondes, donc jamais
// de pumpAndSettle ici — il ne s'arrêterait pas — et chaque test désarme avant de finir,
// sinon le minuteur reste pendant.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/location.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/main.dart';

/// L'arrêt visé, et des positions de plus en plus proches.
const _arret = Stop(id: 'S1', name: 'MONTCEAU GARE', lat: 46.6700, lon: 4.3600);

/// Positions calculées par décalage de latitude : 0,001° ≈ 111 m.
LocationResult _a(double metres) =>
    LocationResult(LocationStatus.found, lat: 46.6700 + metres / 111000.0, lon: 4.3600);

/// Un capteur qui rend les positions l'une après l'autre, puis garde la dernière.
class _Parcours {
  _Parcours(this.etapes);
  final List<LocationResult> etapes;
  int _i = 0;
  Future<LocationResult> probe() async {
    final r = etapes[_i];
    if (_i < etapes.length - 1) _i++;
    return r;
  }
}

void main() {
  Future<void> ouvrir(WidgetTester tester, LocationProbe probe, {double textScale = 1.0}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: WakeScreen(stop: _arret, probe: probe),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Arrête l'alarme : sans cela le minuteur survit au test.
  Future<void> arreter(WidgetTester tester) async {
    await tester.tap(find.text('Arrêter l’alarme'));
    await tester.pump();
  }

  testWidgets('avant de partir : l’arrêt, le choix de distance, et la limite écrite', (tester) async {
    await ouvrir(tester, _Parcours([_a(4000)]).probe);

    expect(find.text('MONTCEAU GARE'), findsOneWidget);
    expect(find.text('500 m'), findsOneWidget, reason: 'le rayon par défaut est proposé');
    expect(find.textContaining('sur votre position, pas sur l’horaire'), findsOneWidget);
    expect(find.textContaining('L’écran reste allumé'), findsOneWidget,
        reason: 'la limite doit être écrite, pas cachée');
    expect(find.textContaining('ne quitte pas le téléphone'), findsOneWidget);
  });

  testWidgets('l’alarme prévient à l’approche, puis à l’arrivée', (tester) async {
    final p = _Parcours([_a(4000), _a(800), _a(200)]);
    await ouvrir(tester, p.probe);

    await tester.tap(find.text('Activer l’alarme'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alarme active'), findsOneWidget);
    expect(find.textContaining('encore'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Vous approchez'), findsOneWidget,
        reason: '800 m, soit dans le double du rayon de 500 m');

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('DESCENDEZ ICI'), findsOneWidget);

    await arreter(tester);
    expect(find.text('Activer l’alarme'), findsOneWidget, reason: 'on revient au réglage');
  });

  testWidgets('armée alors qu’on y est déjà : elle le dit au lieu de hurler', (tester) async {
    await ouvrir(tester, _Parcours([_a(100)]).probe);
    await tester.tap(find.text('Activer l’alarme'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('déjà à cet arrêt'), findsOneWidget);
    await arreter(tester);
  });

  testWidgets('position refusée : l’écran dit quoi faire', (tester) async {
    await ouvrir(tester, () async => const LocationResult(LocationStatus.deniedForever));
    await tester.tap(find.text('Activer l’alarme'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('réglages du téléphone'), findsOneWidget);
    await arreter(tester);
  });

  testWidgets('aucun bouton n’est annoncé sans dire lequel', (tester) async {
    final handle = tester.ensureSemantics();
    await ouvrir(tester, _Parcours([_a(4000)]).probe);

    final muets = <String>[];
    void parcours(SemanticsNode n) {
      final d = n.getSemanticsData();
      if (!n.isMergedIntoParent && d.flagsCollection.isButton && d.label.trim().isEmpty) {
        muets.add('#${n.id}');
      }
      n.visitChildren((c) {
        parcours(c);
        return true;
      });
    }

    parcours(tester.semantics.find(find.byType(MaterialApp)));
    expect(muets, isEmpty);
    handle.dispose();
  });

  testWidgets('texte à 1,6× sur 375 px : aucun débordement', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final p = _Parcours([_a(4000), _a(150)]);
    await ouvrir(tester, p.probe, textScale: 1.6);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Activer l’alarme'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'l’écran d’arrivée non plus ne doit pas déborder');

    await arreter(tester);
  });
}
