// Contraste des badges de ligne, sur les vraies couleurs du réseau embarqué.
// Le GTFS déclare une couleur de texte par ligne ; cinq des huit échouent le critère AA.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/network.dart';
import 'package:monrezo_mvp/main.dart';

void main() {
  final net = Network.fromJsonString(File('assets/data/network.json').readAsStringSync());

  test('chaque badge de ligne atteint 4,5:1', () {
    for (final r in net.routes) {
      final fond = hexColor(r.color);
      final texte = readableOn(fond, hexColor(r.textColor));
      expect(contrastRatio(fond, texte), greaterThanOrEqualTo(4.5), reason: 'ligne ${r.short} (${r.color})');
    }
  });

  test('la couleur déclarée est gardée quand elle passe, remplacée sinon', () {
    // C1 : blanc sur bleu marine, 8,7:1 — on ne touche à rien.
    expect(readableOn(const Color(0xFF2E4694), Colors.white), Colors.white);
    // C3 : blanc sur cyan, 2,4:1 — le noir prend sa place.
    expect(readableOn(const Color(0xFF00B6E8), Colors.white), Colors.black);
  });

  test('un trait de ligne reste visible sur fond blanc', () {
    for (final r in net.routes) {
      expect(contrastRatio(spineOn(hexColor(r.color)), Colors.white), greaterThanOrEqualTo(2.5),
          reason: 'ligne ${r.short} (${r.color})');
    }
  });
}
