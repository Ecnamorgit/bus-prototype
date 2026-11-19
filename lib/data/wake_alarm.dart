// Alarme d'arrivée : prévenir l'usager qu'il approche de l'arrêt où il veut descendre.
//
// Ce n'est pas un gadget pour dormeur. Savoir quand descendre est un problème quotidien
// pour qui ne voit pas défiler les arrêts : une personne malvoyante, quelqu'un qui ne
// connaît pas la ligne, un voyageur de nuit. L'alarme prévient par trois canaux à la fois
// — vibration, son, annonce au lecteur d'écran — parce qu'aucun des trois n'est disponible
// pour tout le monde.
//
// Aucun temps réel n'étant publié sur ce réseau, l'alarme se déclenche sur la POSITION et
// non sur l'horaire. C'est plus robuste : un bus en retard ne fait pas sonner trop tôt.
//
// Ce fichier ne connaît ni GPS, ni son, ni notification : seulement des distances. C'est ce
// qui le rend testable sans téléphone. Testé dans test/wake_alarm_test.dart.

/// Où en est l'usager par rapport à l'arrêt visé.
enum WakePhase {
  /// Hors de la zone d'approche : rien à dire.
  loin,

  /// Dans la zone d'approche, le double du rayon : on prévient, on ne réveille pas.
  /// Un usager en fauteuil ou avec une canne a besoin de ce délai pour se lever.
  approche,

  /// Dans le rayon : c'est maintenant qu'il faut descendre.
  arrivee,
}

/// Suit une alarme au fil des positions reçues, et dit quand il faut la jouer.
///
/// Le suivi est volontairement sourd à tout le reste : il ne sait pas quelle ligne
/// l'usager emprunte, ni dans quel sens. Un bus qui dépasse l'arrêt puis y revient
/// — cas réel d'une ligne en boucle — ne casse donc rien.
class WakeTracker {
  WakeTracker({required this.rayonMetres}) : assert(rayonMetres > 0);

  /// Distance à l'arrêt en dessous de laquelle il faut descendre.
  final double rayonMetres;

  /// La zone d'approche vaut le double du rayon : le temps de ranger ses affaires.
  double get rayonApproche => rayonMetres * 2;

  WakePhase _phase = WakePhase.loin;

  /// A-t-on vu l'usager au moins une fois hors de la zone d'approche ?
  ///
  /// Sans cette garde, une alarme armée alors qu'on est déjà devant l'arrêt hurle à
  /// l'instant où on l'arme. C'est exactement ce que fait quelqu'un qui règle son alarme
  /// en montant dans le bus, à l'arrêt d'où il part et qui est parfois le même.
  bool _vuDehors = false;

  WakePhase get phase => _phase;

  /// L'alarme a-t-elle été armée alors que l'usager était déjà sur place ?
  /// L'écran le dit plutôt que de rester muet sans qu'on sache pourquoi.
  bool get armeeSurPlace => !_vuDehors && _phase != WakePhase.loin;

  /// Nouvelle distance mesurée, en mètres.
  ///
  /// Renvoie la phase **si elle vient de changer** — c'est le signal à jouer — et `null`
  /// quand rien ne change, pour que l'écran ne fasse pas vibrer le téléphone à chaque
  /// relevé de position.
  WakePhase? mesure(double distanceMetres) {
    final avant = _phase;
    if (distanceMetres > rayonApproche) {
      _vuDehors = true;
      _phase = WakePhase.loin;
    } else if (distanceMetres > rayonMetres) {
      _phase = WakePhase.approche;
    } else {
      _phase = WakePhase.arrivee;
    }
    if (_phase == avant) return null;
    // Tant qu'on n'a pas vu l'usager s'éloigner, on ne joue rien : on se contente de
    // noter où il en est.
    if (!_vuDehors) return null;
    return _phase;
  }

  /// Ce que le lecteur d'écran doit annoncer, et ce que l'écran affiche en gros.
  static String annonce(WakePhase phase, String nomArret) {
    switch (phase) {
      case WakePhase.loin:
        return 'Alarme active pour $nomArret.';
      case WakePhase.approche:
        return 'Vous approchez de $nomArret. Préparez-vous à descendre.';
      case WakePhase.arrivee:
        return 'Vous êtes arrivé à $nomArret. Descendez ici.';
    }
  }
}
