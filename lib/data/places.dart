// Informations pratiques : boutiques, transport à la demande, liens officiels.
// Chargé depuis assets/data/places.json, qui porte sa source et la date du relevé.
//
// Ce sont les seules informations de l'application que quelqu'un va utiliser pour AGIR :
// composer un numéro, se déplacer jusqu'à un guichet. D'où la date de relevé affichée à l'écran.
//
// Testé dans test/places_test.dart.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class Shop {
  const Shop({required this.name, required this.address, required this.hours, required this.phone});
  final String name;
  final String address;
  final List<String> hours;
  final String phone;

  static Shop? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final name = (j['name'] as Object?)?.toString().trim() ?? '';
    final address = (j['address'] as Object?)?.toString().trim() ?? '';
    if (name.isEmpty || address.isEmpty) return null;
    return Shop(
      name: name,
      address: address,
      hours: _lines(j['hours']),
      phone: (j['phone'] as Object?)?.toString().trim() ?? '',
    );
  }
}

class OnDemand {
  const OnDemand({required this.title, required this.intro, required this.phone, required this.hours, required this.rules});
  final String title;
  final String intro;
  final String phone;
  final List<String> hours;
  final List<String> rules;

  static OnDemand? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final title = (j['title'] as Object?)?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    return OnDemand(
      title: title,
      intro: (j['intro'] as Object?)?.toString().trim() ?? '',
      phone: (j['phone'] as Object?)?.toString().trim() ?? '',
      hours: _lines(j['hours']),
      rules: _lines(j['rules']),
    );
  }
}

class ExternalLink {
  const ExternalLink({required this.label, required this.url});
  final String label;
  final String url;

  static ExternalLink? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final label = (j['label'] as Object?)?.toString().trim() ?? '';
    final url = (j['url'] as Object?)?.toString().trim() ?? '';
    // Un lien affiché doit être un vrai lien http(s) : rien d'autre ne s'ouvre dans un navigateur.
    if (label.isEmpty || !(url.startsWith('https://') || url.startsWith('http://'))) return null;
    return ExternalLink(label: label, url: url);
  }
}

class PracticalInfo {
  const PracticalInfo({
    required this.shops,
    required this.onDemand,
    required this.links,
    required this.email,
    this.source,
    this.fetched,
  });

  final List<Shop> shops;
  final OnDemand? onDemand;
  final List<ExternalLink> links;
  final String email;

  /// Page d'où viennent ces informations, et date du relevé : affichées à l'écran.
  final String? source;
  final String? fetched;

  static const asset = 'assets/data/places.json';

  factory PracticalInfo.fromJsonString(String s) {
    final j = jsonDecode(s);
    if (j is! Map) throw const FormatException('places.json : objet attendu à la racine');
    return PracticalInfo(
      shops: [
        for (final x in (j['shops'] is List ? j['shops'] as List : const []))
          if (Shop.tryFromJson(x) != null) Shop.tryFromJson(x)!,
      ],
      onDemand: OnDemand.tryFromJson(j['on_demand']),
      links: [
        for (final x in (j['links'] is List ? j['links'] as List : const []))
          if (ExternalLink.tryFromJson(x) != null) ExternalLink.tryFromJson(x)!,
      ],
      email: (j['email'] as Object?)?.toString().trim() ?? '',
      source: j['source']?.toString(),
      fetched: j['fetched']?.toString(),
    );
  }

  static Future<PracticalInfo> load([String path = asset]) async =>
      PracticalInfo.fromJsonString(await rootBundle.loadString(path));
}

List<String> _lines(Object? raw) => [
      for (final l in (raw is List ? raw : const []))
        if (l.toString().trim().isNotEmpty) l.toString().trim(),
    ];

/// Numéro composable : « 03 85 73 01 10 » devient « +33385730110 ».
String telUri(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+')) return 'tel:$digits';
  if (digits.startsWith('0') && digits.length == 10) return 'tel:+33${digits.substring(1)}';
  return 'tel:$digits';
}
