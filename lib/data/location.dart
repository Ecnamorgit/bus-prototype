// Position de l'usager, isolée derrière une interface testable.
//
// La géolocalisation a six états et non deux : l'écran doit savoir dire, pour chacun, ce que
// l'usager peut faire ensuite. Le plugin est enfermé ici pour que l'écran se teste sans lui.
//
// La position ne sert qu'à trier les arrêts embarqués par distance. Elle n'est enregistrée nulle
// part et n'est envoyée nulle part.
//
// Testé dans test/location_test.dart.

import 'package:geolocator/geolocator.dart';

enum LocationStatus {
  /// Rien n'a encore été demandé : l'écran propose un bouton.
  idle,

  /// Recherche en cours.
  searching,

  /// Position obtenue.
  found,

  /// Refusée cette fois : on peut redemander.
  denied,

  /// Refusée définitivement : il faut passer par les réglages du téléphone.
  deniedForever,

  /// La localisation est coupée sur l'appareil.
  serviceDisabled,

  /// Position introuvable (pas de signal, délai dépassé).
  unavailable,
}

class LocationResult {
  const LocationResult(this.status, {this.lat, this.lon});
  final LocationStatus status;
  final double? lat;
  final double? lon;

  bool get hasPosition => lat != null && lon != null;

  static const idle = LocationResult(LocationStatus.idle);
  static const searching = LocationResult(LocationStatus.searching);

  /// Message affiché à l'usager : il dit ce qui s'est passé ET ce qu'il peut faire.
  String get message {
    switch (status) {
      case LocationStatus.idle:
        return 'Votre position reste sur le téléphone : elle sert seulement à trier les arrêts.';
      case LocationStatus.searching:
        return 'Recherche de votre position…';
      case LocationStatus.found:
        return '';
      case LocationStatus.denied:
        return 'Position refusée. Vous pouvez réessayer, ou chercher un arrêt par son nom.';
      case LocationStatus.deniedForever:
        return 'La position est bloquée pour cette application. Autorisez-la dans les réglages du téléphone, ou cherchez un arrêt par son nom.';
      case LocationStatus.serviceDisabled:
        return 'La localisation est désactivée sur ce téléphone. Activez-la, ou cherchez un arrêt par son nom.';
      case LocationStatus.unavailable:
        return 'Position introuvable. Réessayez dehors, ou cherchez un arrêt par son nom.';
    }
  }

  /// Un nouvel essai a-t-il une chance d'aboutir ? (inutile de proposer « Réessayer » sinon)
  bool get canRetry => status == LocationStatus.denied || status == LocationStatus.unavailable || status == LocationStatus.idle;
}

/// Ce que l'écran appelle pour obtenir une position.
typedef LocationProbe = Future<LocationResult> Function();

/// Implémentation réelle, par le plugin.
Future<LocationResult> deviceLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult(LocationStatus.serviceDisabled);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return const LocationResult(LocationStatus.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      return const LocationResult(LocationStatus.denied);
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)),
    );
    return LocationResult(LocationStatus.found, lat: p.latitude, lon: p.longitude);
  } catch (_) {
    // Délai dépassé, pas de capteur, refus côté navigateur : rien d'exploitable.
    return const LocationResult(LocationStatus.unavailable);
  }
}

/// Distance écrite pour un humain : « 240 m », « 1,3 km ».
String formatDistance(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
