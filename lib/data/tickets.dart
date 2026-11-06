// Titres de transport : catalogue tarifaire (assets/data/fares.json) et portefeuille local.
//
// L'ACHAT EST UNE DÉMONSTRATION. Aucun paiement n'est effectué, aucune donnée ne sort du
// téléphone, aucun compte n'est créé. Les prix, eux, sont les tarifs publics du réseau.
// Tout titre produit ici porte `demo: true` : l'écran s'en sert pour l'étiqueter, et rien
// dans ce fichier ne sait produire un titre qui ne le soit pas.
//
// Testé dans test/tickets_test.dart.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class Fare {
  const Fare({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.description,
    required this.trips,
    required this.validityMinutes,
    required this.allDay,
    required this.note,
  });

  final String id;
  final String name;
  final int priceCents;
  final String description;

  /// Nombre de voyages portés par le titre (1 pour un ticket, 10 pour un carnet).
  /// 0 avec [allDay] : le nombre de voyages n'est pas limité.
  final int trips;

  /// Durée de validité d'un voyage après validation, en minutes.
  final int validityMinutes;

  /// Valable jusqu'à la fin de la journée de validation, sans limite de voyages.
  final bool allDay;

  /// Précision sur la vente réelle aujourd'hui (« vendu auprès du conducteur »).
  final String note;

  static Fare? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final id = (j['id'] as Object?)?.toString().trim() ?? '';
    final name = (j['name'] as Object?)?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final price = j['price_cents'];
    if (price is! num || price < 0) return null;
    return Fare(
      id: id,
      name: name,
      priceCents: price.round(),
      description: (j['description'] as Object?)?.toString().trim() ?? '',
      trips: (j['trips'] as num?)?.round() ?? 1,
      validityMinutes: (j['validity_minutes'] as num?)?.round() ?? 0,
      allDay: j['all_day'] == true,
      note: (j['note'] as Object?)?.toString().trim() ?? '',
    );
  }
}

class FareCatalog {
  const FareCatalog({required this.fares, this.source, this.fetched});
  final List<Fare> fares;

  /// Page publique d'où viennent les prix, et date du relevé : un tarif s'affiche avec sa source.
  final String? source;
  final String? fetched;

  static const asset = 'assets/data/fares.json';

  factory FareCatalog.fromJsonString(String s) {
    final j = jsonDecode(s);
    if (j is! Map) throw const FormatException('fares.json : objet attendu à la racine');
    final raw = j['fares'];
    if (raw is! List) throw const FormatException('fares.json : champ « fares » manquant ou non valide');
    final list = <Fare>[];
    for (final f in raw) {
      final fare = Fare.tryFromJson(f);
      if (fare != null) list.add(fare);
    }
    if (list.isEmpty) throw const FormatException('fares.json : aucun tarif lisible');
    return FareCatalog(fares: list, source: j['source']?.toString(), fetched: j['fetched']?.toString());
  }

  static Future<FareCatalog> load([String path = asset]) async =>
      FareCatalog.fromJsonString(await rootBundle.loadString(path));

  Fare? byId(String id) => fares.where((f) => f.id == id).firstOrNull;
}

enum TicketState {
  /// Acheté, jamais validé : il attend le premier voyage.
  aValider,

  /// Validé, le voyage en cours court encore.
  enCours,

  /// Plus de voyage utilisable (durée écoulée et aucun voyage restant).
  epuise,
}

class Ticket {
  const Ticket({
    required this.id,
    required this.fareId,
    required this.name,
    required this.priceCents,
    required this.purchasedAt,
    required this.validatedAt,
    required this.tripsLeft,
    required this.validityMinutes,
    required this.allDay,
    this.demo = true,
  });

  final String id;
  final String fareId;
  final String name;
  final int priceCents;
  final DateTime purchasedAt;

  /// Début du voyage en cours ; null tant que le titre n'a jamais été validé.
  final DateTime? validatedAt;

  /// Voyages restants après le voyage en cours. Ignoré si [allDay].
  final int tripsLeft;
  final int validityMinutes;
  final bool allDay;

  /// Toujours vrai dans cette maquette : ce titre ne vaut rien dans un bus.
  final bool demo;

  /// Fin du voyage en cours, s'il y en a un.
  DateTime? get expiresAt {
    final v = validatedAt;
    if (v == null) return null;
    if (allDay) return DateTime(v.year, v.month, v.day, 23, 59, 59);
    return v.add(Duration(minutes: validityMinutes));
  }

  bool runningAt(DateTime now) {
    final e = expiresAt;
    return e != null && now.isBefore(e);
  }

  Duration? remainingAt(DateTime now) {
    final e = expiresAt;
    if (e == null || !now.isBefore(e)) return null;
    return e.difference(now);
  }

  TicketState stateAt(DateTime now) {
    if (runningAt(now)) return TicketState.enCours;
    if (allDay) {
      // Un titre à la journée ne se valide qu'une fois : passé minuit, il est fini.
      return validatedAt == null ? TicketState.aValider : TicketState.epuise;
    }
    return tripsLeft > 0 ? TicketState.aValider : TicketState.epuise;
  }

  /// Peut-on commencer un voyage maintenant ? (un voyage en cours n'a pas à être revalidé)
  bool canValidateAt(DateTime now) => stateAt(now) == TicketState.aValider;

  /// Démarre un voyage : consomme une unité et ouvre la fenêtre de correspondance.
  Ticket validate(DateTime now) {
    if (!canValidateAt(now)) return this;
    return copyWith(validatedAt: now, tripsLeft: allDay ? tripsLeft : tripsLeft - 1);
  }

  Ticket copyWith({DateTime? validatedAt, int? tripsLeft}) => Ticket(
        id: id,
        fareId: fareId,
        name: name,
        priceCents: priceCents,
        purchasedAt: purchasedAt,
        validatedAt: validatedAt ?? this.validatedAt,
        tripsLeft: tripsLeft ?? this.tripsLeft,
        validityMinutes: validityMinutes,
        allDay: allDay,
        demo: demo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fare': fareId,
        'name': name,
        'price_cents': priceCents,
        'purchased': purchasedAt.toIso8601String(),
        'validated': validatedAt?.toIso8601String(),
        'trips_left': tripsLeft,
        'validity_minutes': validityMinutes,
        'all_day': allDay,
        'demo': demo,
      };

  static Ticket? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final purchased = DateTime.tryParse(j['purchased']?.toString() ?? '');
    final id = j['id']?.toString() ?? '';
    if (purchased == null || id.isEmpty) return null;
    return Ticket(
      id: id,
      fareId: j['fare']?.toString() ?? '',
      name: j['name']?.toString() ?? 'Titre',
      priceCents: (j['price_cents'] as num?)?.round() ?? 0,
      purchasedAt: purchased,
      validatedAt: DateTime.tryParse(j['validated']?.toString() ?? ''),
      tripsLeft: (j['trips_left'] as num?)?.round() ?? 0,
      validityMinutes: (j['validity_minutes'] as num?)?.round() ?? 0,
      allDay: j['all_day'] == true,
      demo: j['demo'] != false,
    );
  }

  /// Titre issu d'un achat simulé. Seule façon d'en fabriquer un : il est donc toujours « demo ».
  factory Ticket.bought(Fare fare, DateTime now, {String? id}) => Ticket(
        id: id ?? 'T${now.microsecondsSinceEpoch}',
        fareId: fare.id,
        name: fare.name,
        priceCents: fare.priceCents,
        purchasedAt: now,
        validatedAt: null,
        tripsLeft: fare.allDay ? 0 : (fare.trips < 1 ? 1 : fare.trips),
        validityMinutes: fare.validityMinutes,
        allDay: fare.allDay,
      );
}

/// Les titres achetés, gardés sur le téléphone. Pas de compte, rien n'est envoyé nulle part.
class TicketWallet {
  TicketWallet({this.prefsKey = 'demo_tickets'});
  final String prefsKey;
  final List<Ticket> tickets = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(prefsKey);
    tickets.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final t in list) {
        final ticket = Ticket.tryFromJson(t);
        if (ticket != null) tickets.add(ticket);
      }
    } on FormatException {
      // Stockage abîmé : on repart d'un portefeuille vide plutôt que de bloquer l'écran.
      tickets.clear();
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(prefsKey, jsonEncode([for (final t in tickets) t.toJson()]));
  }

  Future<Ticket> buy(Fare fare, DateTime now) async {
    final t = Ticket.bought(fare, now);
    tickets.insert(0, t);
    await _save();
    return t;
  }

  Future<Ticket?> validate(String ticketId, DateTime now) async {
    final i = tickets.indexWhere((t) => t.id == ticketId);
    if (i < 0) return null;
    final updated = tickets[i].validate(now);
    tickets[i] = updated;
    await _save();
    return updated;
  }

  Future<void> clear() async {
    tickets.clear();
    await _save();
  }

  /// Titres encore utilisables, les voyages en cours d'abord.
  List<Ticket> usable(DateTime now) {
    final list = tickets.where((t) => t.stateAt(now) != TicketState.epuise).toList();
    list.sort((a, b) {
      final ra = a.runningAt(now) ? 0 : 1, rb = b.runningAt(now) ? 0 : 1;
      if (ra != rb) return ra - rb;
      return b.purchasedAt.compareTo(a.purchasedAt);
    });
    return list;
  }

  List<Ticket> spent(DateTime now) =>
      tickets.where((t) => t.stateAt(now) == TicketState.epuise).toList()
        ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
}

String formatPrice(int cents) {
  final euros = cents ~/ 100, c = cents % 100;
  return c == 0 ? '$euros €' : '$euros,${c.toString().padLeft(2, '0')} €';
}
