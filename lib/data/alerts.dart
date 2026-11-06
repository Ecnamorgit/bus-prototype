// Informations trafic : chargement de assets/data/alerts.json, tri et filtrage par date.
// Pur Dart hors du chargement d'asset, testé dans test/alerts_test.dart.
//
// Format du fichier (prévu pour un futur back-office, voir README.md) :
//   {
//     "_note": "...",
//     "alerts": [
//       {"id": "...", "severity": "info|warning|severe", "lines": ["M2", ...],
//        "title": "...", "body": "...",
//        "from": "AAAA-MM-JJ" | null, "to": "AAAA-MM-JJ" | null,
//        "updated": "AAAA-MM-JJTHH:MM" | null, "example": true}
//     ]
//   }
//
// Les lignes sont désignées par leur nom public (« M2 »), pas par l'identifiant interne du
// GTFS (« R5 ») : cet identifiant est un compteur, il se décale dès qu'une ligne est ajoutée.
// Un flux rédigé par un exploitant doit survivre à une régénération des données.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

enum AlertSeverity { info, warning, severe }

class TrafficAlert {
  const TrafficAlert({
    required this.id,
    required this.severity,
    required this.lines,
    required this.title,
    required this.body,
    required this.from,
    required this.to,
    required this.updated,
    required this.example,
  });

  final String id;
  final AlertSeverity severity;

  /// Noms publics des lignes concernées (« M2 »). Vide = tout le réseau.
  final List<String> lines;
  final String title;
  final String body;

  /// Début de la perturbation ; null = depuis toujours.
  final DateTime? from;

  /// Fin prévue, incluse ; null = sans fin annoncée.
  final DateTime? to;

  /// Dernière mise à jour par l'exploitant.
  final DateTime? updated;

  /// true = donnée d'exemple, à étiqueter comme telle à l'écran.
  final bool example;

  bool isActiveOn(DateTime day) {
    final d = _dayOf(day);
    if (from != null && d.isBefore(_dayOf(from!))) return false;
    if (to != null && d.isAfter(_dayOf(to!))) return false;
    return true;
  }

  bool isUpcomingOn(DateTime day) => from != null && _dayOf(day).isBefore(_dayOf(from!));

  bool isOverOn(DateTime day) => to != null && _dayOf(day).isAfter(_dayOf(to!));

  /// Une alerte mal formée ne doit pas vider l'écran : on l'ignore, les autres restent.
  /// Un titre vide ou une entrée qui n'est pas un objet sont les seuls cas rédhibitoires.
  static TrafficAlert? tryFromJson(Object? raw, {int index = 0}) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final title = (j['title'] as Object?)?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    return TrafficAlert(
      id: (j['id'] as Object?)?.toString().trim().isNotEmpty == true ? j['id'].toString().trim() : 'alerte-$index',
      severity: _severity(j['severity']),
      lines: [
        for (final l in (j['lines'] is List ? j['lines'] as List : const []))
          if (l.toString().trim().isNotEmpty) l.toString().trim(),
      ],
      title: title,
      body: (j['body'] as Object?)?.toString().trim() ?? '',
      from: _date(j['from']),
      to: _date(j['to']),
      updated: _date(j['updated']),
      example: j['example'] != false, // par défaut on suppose l'exemple : on n'annonce pas du vrai par erreur
    );
  }

  static AlertSeverity _severity(Object? v) {
    switch (v?.toString().trim().toLowerCase()) {
      case 'severe':
        return AlertSeverity.severe;
      case 'warning':
        return AlertSeverity.warning;
      default:
        return AlertSeverity.info; // inconnu : on n'invente pas une urgence
    }
  }

  static DateTime? _date(Object? v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

class AlertFeed {
  const AlertFeed({required this.alerts, this.note});
  final List<TrafficAlert> alerts;
  final String? note;

  static const asset = 'assets/data/alerts.json';

  factory AlertFeed.fromJsonString(String s) {
    final j = jsonDecode(s);
    if (j is! Map) throw const FormatException('alerts.json : objet attendu à la racine');
    final raw = j['alerts'];
    if (raw is! List) throw const FormatException('alerts.json : champ « alerts » manquant ou non valide');
    final list = <TrafficAlert>[];
    for (var i = 0; i < raw.length; i++) {
      final a = TrafficAlert.tryFromJson(raw[i], index: i);
      if (a != null) list.add(a);
    }
    return AlertFeed(alerts: list, note: j['_note']?.toString());
  }

  static Future<AlertFeed> load([String path = asset]) async => AlertFeed.fromJsonString(await rootBundle.loadString(path));

  /// Perturbations en cours ce jour-là : la plus grave d'abord, puis la plus récemment mise à jour.
  List<TrafficAlert> current(DateTime day) {
    final list = alerts.where((a) => a.isActiveOn(day)).toList();
    list.sort((a, b) {
      final s = b.severity.index.compareTo(a.severity.index);
      if (s != 0) return s;
      final ua = a.updated, ub = b.updated;
      if (ua != null && ub != null) return ub.compareTo(ua);
      if (ua != null) return -1;
      if (ub != null) return 1;
      return a.title.compareTo(b.title);
    });
    return list;
  }

  /// Annoncées mais pas encore commencées, dans l'ordre où elles arriveront.
  List<TrafficAlert> upcoming(DateTime day) {
    final list = alerts.where((a) => a.isUpcomingOn(day)).toList();
    list.sort((a, b) => a.from!.compareTo(b.from!));
    return list;
  }

  /// true si tout ce que contient le flux est une donnée d'exemple (cas de la maquette).
  bool get allExamples => alerts.isEmpty || alerts.every((a) => a.example);
}
