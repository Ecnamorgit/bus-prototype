// Le moteur d'alarme d'arrivée, sans GPS ni téléphone : seulement des distances.

import 'package:flutter_test/flutter_test.dart';
import 'package:monrezo_mvp/data/wake_alarm.dart';

void main() {
  group('phases', () {
    test('au-delà du double du rayon, on est loin', () {
      final t = WakeTracker(rayonMetres: 300);
      expect(t.mesure(2000), isNull, reason: 'première mesure au loin : rien à annoncer');
      expect(t.phase, WakePhase.loin);
    });

    test('entre le rayon et son double : on prévient', () {
      final t = WakeTracker(rayonMetres: 300)..mesure(2000);
      expect(t.mesure(450), WakePhase.approche);
      expect(t.phase, WakePhase.approche);
    });

    test('sous le rayon : il faut descendre', () {
      final t = WakeTracker(rayonMetres: 300)..mesure(2000);
      t.mesure(450);
      expect(t.mesure(120), WakePhase.arrivee);
    });

    test('une phase ne se joue qu’une fois', () {
      final t = WakeTracker(rayonMetres: 300)..mesure(2000);
      expect(t.mesure(400), WakePhase.approche);
      expect(t.mesure(380), isNull, reason: 'toujours en approche : le téléphone ne doit pas revibrer');
      expect(t.mesure(350), isNull);
    });

    test('un passage direct de loin à arrivée reste annoncé', () {
      // Relevés espacés : le bus a traversé la zone d'approche entre deux positions.
      final t = WakeTracker(rayonMetres: 300)..mesure(5000);
      expect(t.mesure(80), WakePhase.arrivee);
    });
  });

  group('alarme armée alors qu’on est déjà sur place', () {
    test('ne sonne pas tant qu’on n’a pas vu l’usager s’éloigner', () {
      final t = WakeTracker(rayonMetres: 300);
      expect(t.mesure(50), isNull, reason: 'sinon elle hurle à l’instant où on l’arme');
      expect(t.armeeSurPlace, isTrue);
      expect(t.phase, WakePhase.arrivee, reason: 'l’écran doit quand même savoir où on est');
    });

    test('et sonne normalement une fois le bus reparti', () {
      final t = WakeTracker(rayonMetres: 300)..mesure(50);
      expect(t.mesure(3000), WakePhase.loin);
      expect(t.armeeSurPlace, isFalse);
      expect(t.mesure(100), WakePhase.arrivee);
    });
  });

  group('ligne en boucle : l’arrêt est dépassé puis revu', () {
    test('la deuxième approche se joue de nouveau', () {
      final t = WakeTracker(rayonMetres: 300)..mesure(4000);
      expect(t.mesure(100), WakePhase.arrivee);
      expect(t.mesure(2500), WakePhase.loin, reason: 'le bus s’éloigne');
      expect(t.mesure(100), WakePhase.arrivee, reason: 'il repasse : on réavertit');
    });
  });

  group('ce qui est annoncé', () {
    test('chaque phase dit à l’usager quoi faire, pas seulement où il est', () {
      expect(WakeTracker.annonce(WakePhase.approche, 'MONTCEAU GARE'),
          'Vous approchez de MONTCEAU GARE. Préparez-vous à descendre.');
      expect(WakeTracker.annonce(WakePhase.arrivee, 'MONTCEAU GARE'),
          'Vous êtes arrivé à MONTCEAU GARE. Descendez ici.');
      expect(WakeTracker.annonce(WakePhase.loin, 'MONTCEAU GARE'), contains('MONTCEAU GARE'));
    });
  });

  test('la zone d’approche vaut le double du rayon', () {
    expect(WakeTracker(rayonMetres: 250).rayonApproche, 500);
  });
}
