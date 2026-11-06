// Point d'entrée du MVP. Les cinq écrans du périmètre (voir CLAUDE.md) sont implémentés :
// Passages et Lignes sur le vrai GTFS, Infos trafic sur des alertes d'exemple étiquetées,
// Mes titres sur les tarifs publics avec un achat simulé, Plan et infos sur le plan tracé
// depuis les données et les coordonnées réelles des boutiques.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/alerts.dart';
import 'data/location.dart';
import 'data/network.dart';
import 'data/places.dart';
import 'data/tickets.dart';
import 'data/schedule.dart';

const kInk = Color(0xFF0F2A4F);
const kTeal = Color(0xFF12B1A0);

void main() => runApp(const MonRezoApp());

class MonRezoApp extends StatelessWidget {
  const MonRezoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus — prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kTeal, primary: kTeal),
        scaffoldBackgroundColor: const Color(0xFFF5F7F9),
        appBarTheme: const AppBarTheme(backgroundColor: kInk, foregroundColor: Colors.white),
      ),
      home: const Bootstrap(),
    );
  }
}

/// Charge le réseau embarqué puis affiche l'application.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late final Future<Network> _net = Network.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Network>(
      future: _net,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Impossible de charger les horaires embarqués.\n${snap.error}', textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Shell(net: snap.data!);
      },
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.net});
  final Network net;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  late final Schedule sched = Schedule(widget.net);
  final Favorites favorites = Favorites();

  @override
  void initState() {
    super.initState();
    favorites.load().then((_) { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DeparturesScreen(net: widget.net, sched: sched, favorites: favorites, onChanged: () => setState(() {})),
      LinesScreen(net: widget.net, sched: sched, favorites: favorites, onChanged: () => setState(() {})),
      AlertsScreen(net: widget.net),
      const TicketsScreen(),
      PlacesScreen(net: widget.net),
    ];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Passages'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Lignes'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Infos'),
          NavigationDestination(icon: Icon(Icons.confirmation_number_outlined), selectedIcon: Icon(Icons.confirmation_number), label: 'Titres'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Plus'),
        ],
      ),
    );
  }
}

/// Arrêts favoris, persistés sur le téléphone (pas de compte).
class Favorites {
  static const _key = 'favorite_stops';
  final List<String> ids = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    ids
      ..clear()
      ..addAll(p.getStringList(_key) ?? const []);
  }

  Future<void> toggle(String id) async {
    if (!ids.remove(id)) ids.add(id);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, ids);
  }

  bool contains(String id) => ids.contains(id);
}

// ---------------------------------------------------------------------------------------------
// Écran 1 : prochains passages à mes arrêts
// ---------------------------------------------------------------------------------------------

class DeparturesScreen extends StatefulWidget {
  const DeparturesScreen({
    super.key,
    required this.net,
    required this.sched,
    required this.favorites,
    required this.onChanged,
    this.probe,
  });
  final Network net;
  final Schedule sched;
  final Favorites favorites;
  final VoidCallback onChanged;

  /// Comment obtenir la position. Par défaut le capteur du téléphone ; injectable pour que
  /// les tests passent les six états de la géolocalisation, dont ceux qu'on ne peut pas
  /// provoquer à la main.
  final LocationProbe? probe;

  @override
  State<DeparturesScreen> createState() => _DeparturesScreenState();
}

class _DeparturesScreenState extends State<DeparturesScreen> {
  Timer? _tick;
  DateTime now = DateTime.now();
  LocationResult _loc = LocationResult.idle;
  List<(Stop, double)> _nearby = const [];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() => now = DateTime.now()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _addStop() async {
    final stop = await showSearch<Stop?>(context: context, delegate: StopSearch(widget.sched));
    if (stop != null && !widget.favorites.contains(stop.id)) {
      await widget.favorites.toggle(stop.id);
      widget.onChanged();
    }
  }

  /// La position n'est jamais demandée toute seule : un usager qui la voit surgir au lancement
  /// refuse, et un refus définitif est difficile à rattraper.
  Future<void> _locate() async {
    setState(() => _loc = LocationResult.searching);
    final r = await (widget.probe ?? deviceLocation)();
    if (!mounted) return;
    setState(() {
      _loc = r;
      _nearby = r.hasPosition ? widget.sched.nearestStops(r.lat!, r.lon!, limit: 3) : const [];
    });
  }

  Future<void> _toggle(String id) async {
    await widget.favorites.toggle(id);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final favs = widget.favorites.ids.map((id) => widget.net.stopById[id]).whereType<Stop>().toList();
    final rienAMontrer = favs.isEmpty && _nearby.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prochains passages'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Semantics(
                label: 'il est ${_hhmm(now)}',
                child: Text(_hhmm(now), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStop,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Ajouter un arrêt'),
      ),
      body: rienAMontrer
          ? _EmptyState(onAdd: _addStop, onLocate: _locate, loc: _loc)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                for (final s in favs)
                  _StopCard(
                    stop: s,
                    departures: widget.sched.nextDepartures(s.id, now, limit: 6),
                    now: now,
                    isFavorite: true,
                    onToggleFavorite: () => _toggle(s.id),
                  ),
                _NearbyBlock(
                  loc: _loc,
                  nearby: _nearby,
                  sched: widget.sched,
                  now: now,
                  favorites: widget.favorites,
                  onLocate: _locate,
                  onToggleFavorite: _toggle,
                  onSearch: _addStop,
                ),
                const SizedBox(height: 14),
                Text(
                  'Horaires prévus, issus des données ouvertes de la collectivité (${widget.net.generated}). '
                  'Aucun temps réel n’existe sur ce réseau.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
    );
  }
}

/// Aucun favori et aucune position : les deux portes d'entrée, côte à côte.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.onLocate, required this.loc});
  final VoidCallback onAdd;
  final VoidCallback onLocate;
  final LocationResult loc;

  @override
  Widget build(BuildContext context) {
    final chercher = OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.search), label: const Text('Chercher un arrêt'));
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bus_outlined, size: 64, color: kInk),
            const SizedBox(height: 16),
            const Text('Vos arrêts, vos prochains bus',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Ajoutez l’arrêt que vous prenez tous les jours : les prochains passages s’affichent ici, même sans réseau.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 22),
            if (loc.status == LocationStatus.searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Recherche de votre position…'),
                  ],
                ),
              )
            else if (loc.canRetry)
              FilledButton.icon(
                onPressed: onLocate,
                icon: const Icon(Icons.my_location),
                label: Text(loc.status == LocationStatus.idle ? 'Arrêts près de moi' : 'Réessayer la position'),
              ),
            if (loc.status != LocationStatus.searching) ...[
              const SizedBox(height: 10),
              Text(loc.message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            const SizedBox(height: 14),
            chercher,
          ],
        ),
      ),
    );
  }
}

/// « Autour de vous » : l'arrêt le plus proche avec ses départs, puis les deux suivants.
class _NearbyBlock extends StatelessWidget {
  const _NearbyBlock({
    required this.loc,
    required this.nearby,
    required this.sched,
    required this.now,
    required this.favorites,
    required this.onLocate,
    required this.onToggleFavorite,
    required this.onSearch,
  });

  final LocationResult loc;
  final List<(Stop, double)> nearby;
  final Schedule sched;
  final DateTime now;
  final Favorites favorites;
  final VoidCallback onLocate;
  final void Function(String stopId) onToggleFavorite;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final titre = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.my_location, size: 18, color: kTeal),
          const SizedBox(width: 8),
          const Expanded(child: Text('Autour de vous', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kInk))),
          if (loc.status == LocationStatus.found)
            TextButton(onPressed: onLocate, child: const Text('Actualiser')),
        ],
      ),
    );

    // Un arrêt déjà en favori est affiché juste au-dessus : le reproposer ici n'apprend rien.
    final restants = nearby.where((e) => !favorites.contains(e.$1.id)).toList();

    if (loc.status == LocationStatus.found && restants.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titre,
          const Text('Les arrêts autour de vous sont déjà dans vos favoris.',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      );
    }

    if (loc.status == LocationStatus.found && restants.isNotEmpty) {
      final (proche, distance) = restants.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titre,
          _StopCard(
            stop: proche,
            departures: sched.nextDepartures(proche.id, now, limit: 4),
            now: now,
            isFavorite: favorites.contains(proche.id),
            onToggleFavorite: () => onToggleFavorite(proche.id),
            distanceMeters: distance,
            label: 'Le plus proche de vous',
          ),
          for (final (s, d) in restants.skip(1))
            Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
              child: ListTile(
                leading: const Icon(Icons.place_outlined, color: kTeal),
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, color: kInk)),
                subtitle: Text('${formatDistance(d)} · ${sched.net.routesAtStop(s.id).map((r) => r.short).join(' · ')}'),
                trailing: IconButton(
                  tooltip: favorites.contains(s.id) ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  icon: Icon(favorites.contains(s.id) ? Icons.star : Icons.star_border,
                      color: favorites.contains(s.id) ? const Color(0xFFFFB300) : Colors.black38),
                  onPressed: () => onToggleFavorite(s.id),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titre,
        Card(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loc.status == LocationStatus.searching)
                  const Row(
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Expanded(child: Text('Recherche de votre position…')),
                    ],
                  )
                else ...[
                  Text(loc.message, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 12),
                  if (loc.canRetry)
                    FilledButton.tonalIcon(
                      onPressed: onLocate,
                      icon: const Icon(Icons.my_location),
                      label: Text(loc.status == LocationStatus.idle ? 'Arrêts près de moi' : 'Réessayer'),
                    )
                  else
                    OutlinedButton.icon(onPressed: onSearch, icon: const Icon(Icons.search), label: const Text('Chercher un arrêt')),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.stop,
    required this.departures,
    required this.now,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.distanceMeters,
    this.label,
  });

  final Stop stop;
  final List<Departure> departures;
  final DateTime now;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final double? distanceMeters;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(label!, style: const TextStyle(fontSize: 12, color: kTeal, fontWeight: FontWeight.w700)),
              ),
            Row(
              children: [
                const Icon(Icons.place, color: kTeal, size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text(stop.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kInk))),
                IconButton(
                  tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  onPressed: onToggleFavorite,
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border,
                      color: isFavorite ? const Color(0xFFFFB300) : Colors.black38),
                ),
              ],
            ),
            // Badge demandé par le brief : il accompagne chaque arrêt, pas seulement le bas de page.
            // Un horaire théorique présenté sans réserve se lit comme un temps réel.
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFEFF3F6), borderRadius: BorderRadius.circular(6)),
                    child: const Text('horaires prévus',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kInk)),
                  ),
                  if (distanceMeters != null)
                    Text('à ${formatDistance(distanceMeters!)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            if (departures.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 2, bottom: 4),
                child: Text('Pas de passage prévu dans les 3 prochaines heures.', style: TextStyle(color: Colors.black54)),
              ),
            for (final d in departures) _DepartureRow(d: d, now: now),
          ],
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({required this.d, required this.now});
  final Departure d;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final mins = d.minutesFrom(now);
    final label = mins <= 0 ? 'à quai' : (mins < 60 ? '$mins min' : _hhmm(d.scheduled));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          RouteBadge(route: d.route),
          const SizedBox(width: 10),
          Expanded(child: Text('vers ${d.headsign}', style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          // Le délai au-dessus de l'heure, et non à côté : à 1,6× de texte, les deux côte à côte
          // débordent de la largeur d'un téléphone.
          Semantics(
            label: 'départ prévu à ${_hhmm(d.scheduled)}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: mins < 10 ? kTeal : const Color(0xFFEFF3F6), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: mins < 10 ? Colors.white : kInk)),
                ),
                if (mins < 60) Text(_hhmm(d.scheduled), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RouteBadge extends StatelessWidget {
  const RouteBadge({super.key, required this.route, this.size = 1.0});
  final BusLine route;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: 36 * size),
      height: 28 * size,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: hexColor(route.color), borderRadius: BorderRadius.circular(8)),
      // Center(widthFactor: 1) plutôt que `alignment` : avec alignment, le badge s'étire sur
      // toute la largeur disponible dès qu'il n'est pas dans une Row (cas du Wrap des alertes).
      child: Center(
        widthFactor: 1,
        child: Semantics(
        label: 'ligne ${route.short}',
        excludeSemantics: true,
        child: Text(route.short,
            style: TextStyle(color: readableOn(hexColor(route.color), hexColor(route.textColor)), fontWeight: FontWeight.w900, fontSize: 14 * size)),
        ),
      ),
    );
  }
}

/// Recherche d'arrêt (barre de recherche Material).
class StopSearch extends SearchDelegate<Stop?> {
  StopSearch(this.sched) : super(searchFieldLabel: 'Nom de l’arrêt');
  final Schedule sched;

  @override
  List<Widget> buildActions(BuildContext context) => [if (query.isNotEmpty) IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];

  @override
  Widget buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back));

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = sched.searchStops(query);
    if (query.trim().isEmpty) {
      return const Center(child: Text('Tapez le nom d’un arrêt, par exemple « Gare » ou « Mairie ».'));
    }
    if (results.isEmpty) return const Center(child: Text('Aucun arrêt ne correspond.'));
    return ListView(
      children: [
        for (final s in results)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(s.name),
            subtitle: Text(sched.net.routesAtStop(s.id).map((r) => r.short).join(' · ')),
            onTap: () => close(context, s),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Écran 2 : lignes → arrêts d'un sens → grille horaire
// ---------------------------------------------------------------------------------------------

class LinesScreen extends StatelessWidget {
  const LinesScreen({super.key, required this.net, required this.sched, required this.favorites, required this.onChanged});
  final Network net;
  final Schedule sched;
  final Favorites favorites;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Lignes')),
      body: net.routes.isEmpty
          ? const _Notice(
              icon: Icons.error_outline,
              title: 'Aucune ligne',
              text: 'Les données embarquées ne contiennent aucune ligne. Régénérez assets/data/network.json.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: net.routes.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == net.routes.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      'Horaires prévus du ${_frDate(today)}, données ouvertes de la collectivité. Pas de temps réel.',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  );
                }
                final r = net.routes[i];
                final courses = sched.routeTripCount(r.id, today);
                final nbStops = {
                  for (final d in net.directionsOfRoute(r.id))
                    for (final ds in net.directionStops(r.id, d)) ds.stop.id
                }.length;
                return _LineCard(
                  route: r,
                  title: _lineName(r),
                  subtitle: courses == 0 ? 'Pas de bus aujourd’hui' : '$nbStops arrêts · $courses courses aujourd’hui',
                  warn: courses == 0,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RouteScreen(net: net, sched: sched, route: r, favorites: favorites, onChanged: onChanged),
                  )),
                );
              },
            ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.route, required this.title, required this.subtitle, required this.warn, required this.onTap});
  final BusLine route;
  final String title;
  final String subtitle;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              RouteBadge(route: route, size: 1.15),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kInk)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: warn ? const Color(0xFF9A5B00) : Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne, un sens : les arrêts dans l'ordre, puis la grille horaire d'un arrêt.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.net, required this.sched, required this.route, required this.favorites, required this.onChanged});
  final Network net;
  final Schedule sched;
  final BusLine route;
  final Favorites favorites;
  final VoidCallback onChanged;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  late int direction = widget.net.directionsOfRoute(widget.route.id).firstOrNull ?? 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// En changeant de sens, on revient en haut : sinon l'usager retombe au milieu de la ligne,
  /// à un arrêt qui n'a rien à voir avec celui qu'il regardait.
  void _swap(List<int> dirs) {
    setState(() => direction = dirs.firstWhere((d) => d != direction, orElse: () => direction));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final net = widget.net;
    final dirs = net.directionsOfRoute(widget.route.id);
    final main = net.mainPatternOfDirection(widget.route.id, direction);
    final stops = net.directionStops(widget.route.id, direction);
    final today = DateTime.now();
    final courses = main == null ? 0 : widget.sched.directionTripCount(widget.route.id, direction, today);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          RouteBadge(route: widget.route),
          const SizedBox(width: 10),
          Expanded(child: Text(_lineName(widget.route), style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: main == null
          ? const _Notice(
              icon: Icons.schedule_outlined,
              title: 'Aucun horaire',
              text: 'Cette ligne n’a aucun parcours dans les données embarquées.',
            )
          : Column(
              children: [
                _DirectionHeader(
                  headsign: main.headsign,
                  canSwap: dirs.length > 1,
                  onSwap: () => _swap(dirs),
                ),
                if (courses == 0)
                  const _Banner(text: 'Aucun bus dans ce sens aujourd’hui. Les arrêts ci-dessous restent le tracé de la ligne.'),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 6, 8, 28),
                    itemCount: stops.length + 1,
                    itemBuilder: (context, i) {
                      if (i == stops.length) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(10, 16, 10, 0),
                          child: Text('Touchez un arrêt pour voir tous les horaires du jour dans ce sens.',
                              style: TextStyle(fontSize: 12, color: Colors.black54)),
                        );
                      }
                      final ds = stops[i];
                      return _StopRow(
                        stop: ds.stop,
                        everyTrip: ds.everyTrip,
                        isFirst: i == 0,
                        isLast: i == stops.length - 1,
                        color: spineOn(hexColor(widget.route.color)),
                        favorite: widget.favorites.contains(ds.stop.id),
                        onToggleFavorite: () async {
                          await widget.favorites.toggle(ds.stop.id);
                          widget.onChanged();
                          if (mounted) setState(() {});
                        },
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (_) => TimetableSheet(
                            sched: widget.sched,
                            route: widget.route,
                            direction: direction,
                            headsign: main.headsign,
                            stop: ds.stop,
                            everyTrip: ds.everyTrip,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// Le sens courant, avec le bouton pour passer à l'autre. Pas de bouton segmenté : à 1,6×,
/// « vers LE BREUIL CENTRE COMMERCIAL » ne tient pas sur la largeur d'un téléphone.
class _DirectionHeader extends StatelessWidget {
  const _DirectionHeader({required this.headsign, required this.canSwap, required this.onSwap});
  final String headsign;
  final bool canSwap;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.arrow_forward, color: kTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Direction', style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text(headsign, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kInk)),
              ],
            ),
          ),
          if (canSwap)
            IconButton.filledTonal(
              tooltip: 'Changer de sens',
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz),
            ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.everyTrip,
    required this.isFirst,
    required this.isLast,
    required this.color,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onTap,
  });
  final Stop stop;
  final bool everyTrip;
  final bool isFirst;
  final bool isLast;
  final Color color;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          stop.name,
          style: TextStyle(fontSize: 15, color: kInk, fontWeight: isFirst || isLast ? FontWeight.w800 : FontWeight.w500),
        ),
        if (!everyTrip) const Text('Certains bus seulement', style: TextStyle(fontSize: 12, color: Color(0xFF9A5B00))),
      ],
    );
    // IntrinsicHeight : le jalon doit faire la hauteur exacte de la rangée, qui dépend de la
    // taille de texte choisie par l'usager (jusqu'à 1,6×) et du sous-titre de variante.
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: CustomPaint(painter: _TimelinePainter(color: color, isFirst: isFirst, isLast: isLast, hollow: !everyTrip)),
              ),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: label)),
              IconButton(
                tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                onPressed: onToggleFavorite,
                icon: Icon(favorite ? Icons.star : Icons.star_border, color: favorite ? const Color(0xFFFFB300) : Colors.black38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.color, required this.isFirst, required this.isLast, required this.hollow});
  final Color color;
  final bool isFirst;
  final bool isLast;
  final bool hollow;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final cy = size.height / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (!isFirst) canvas.drawLine(Offset(x, 0), Offset(x, cy), line);
    if (!isLast) canvas.drawLine(Offset(x, cy), Offset(x, size.height), line);
    final r = isFirst || isLast ? 7.0 : 5.0;
    canvas.drawCircle(Offset(x, cy), r, Paint()..color = color);
    if (hollow || !(isFirst || isLast)) {
      canvas.drawCircle(Offset(x, cy), r - 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.color != color || old.isFirst != isFirst || old.isLast != isLast || old.hollow != hollow;
}

/// Grille horaire du jour à un arrêt, pour un sens entier : toutes les variantes de la ligne.
class TimetableSheet extends StatelessWidget {
  const TimetableSheet({
    super.key,
    required this.sched,
    required this.route,
    required this.direction,
    required this.headsign,
    required this.stop,
    required this.everyTrip,
  });
  final Schedule sched;
  final BusLine route;
  final int direction;
  final String headsign;
  final Stop stop;
  final bool everyTrip;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final deps = sched.directionTimetable(route.id, direction, stop.id, today);
    final nowMin = today.hour * 60 + today.minute;
    final next = deps.where((d) => d.minutes >= nowMin).map((d) => d.minutes).firstOrNull;

    // Les variantes d'un même sens n'ont pas toujours la même destination (HOPITAL J. BOUVERI
    // ou LES GAUTHERETS sur M3) : on sépare les groupes plutôt que de mélanger les heures.
    final byHead = <String, List<DirectionDeparture>>{};
    for (final d in deps) {
      (byHead[d.headsign] ??= <DirectionDeparture>[]).add(d);
    }
    final heads = byHead.keys.toList()..sort((a, b) => byHead[b]!.length.compareTo(byHead[a]!.length));

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              RouteBadge(route: route),
              const SizedBox(width: 10),
              Expanded(child: Text(stop.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: kInk))),
            ]),
            const SizedBox(height: 6),
            Text('Direction $headsign · ${_frDate(today)}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFEFF3F6), borderRadius: BorderRadius.circular(6)),
                child: const Text('horaires prévus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('aucun temps réel', style: TextStyle(fontSize: 12, color: Colors.black54))),
            ]),
            if (!everyTrip) ...[
              const SizedBox(height: 10),
              const Text('Tous les bus de ce sens ne desservent pas cet arrêt.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9A5B00))),
            ],
            const SizedBox(height: 14),
            if (deps.isEmpty)
              const Text('Pas de passage aujourd’hui à cet arrêt dans ce sens.', style: TextStyle(fontSize: 15))
            else
              for (final h in heads) ...[
                if (heads.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('vers $h  (${byHead[h]!.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kInk)),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in byHead[h]!)
                      Semantics(
                        label: 'passage prévu à ${formatMinutes(d.minutes)}${d.minutes == next ? ', prochain' : ''}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: d.minutes == next ? kTeal : const Color(0xFFEFF3F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            formatMinutes(d.minutes),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: d.minutes == next ? Colors.white : kInk,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
          ],
        ),
      ),
    );
  }
}

/// Bandeau d'information (pas de service, donnée simulée…).
class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4E0),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF9A5B00)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF7A4800)))),
        ],
      ),
    );
  }
}

/// État vide ou en erreur, plein écran.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Défilable : à 1,6× de texte, un état vide avec son bouton dépasse la hauteur d'un téléphone.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: kInk),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Écran 3 : infos trafic (données d'exemple, étiquetées comme telles)
// ---------------------------------------------------------------------------------------------

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.net, this.loader});
  final Network net;

  /// D'où viennent les alertes. Par défaut l'asset embarqué ; le jour où un back-office les
  /// publie, c'est ici qu'on branche sa lecture — et c'est ce qui permet de tester à l'écran
  /// les trois états (chargement, erreur, liste vide) sans toucher au fichier livré.
  final Future<AlertFeed> Function()? loader;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // Chargé à part du réseau : demain ces alertes viendront d'un back-office, pas des assets.
  late Future<AlertFeed> _feed = _load();

  Future<AlertFeed> _load() => (widget.loader ?? AlertFeed.load)();

  void _reload() {
    // Corps explicite : une flèche renverrait le Future, et setState refuse une valeur asynchrone.
    setState(() {
      _feed = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Infos trafic')),
      body: FutureBuilder<AlertFeed>(
        future: _feed,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Notice(
              icon: Icons.cloud_off_outlined,
              title: 'Informations indisponibles',
              text: 'Les informations trafic n’ont pas pu être lues.\n${snap.error}',
              action: FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
            );
          }
          if (!snap.hasData) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
          }
          final feed = snap.data!;
          final today = DateTime.now();
          final current = feed.current(today);
          final soon = feed.upcoming(today);

          return Column(
            children: [
              if (feed.allExamples)
                const _Banner(
                  text: 'Démonstration : ces informations sont des exemples. Elles ne viennent pas du réseau.',
                ),
              Expanded(
                child: current.isEmpty && soon.isEmpty
                    ? const _Notice(
                        icon: Icons.check_circle_outline,
                        title: 'Aucune perturbation',
                        text: 'Aucune information trafic aujourd’hui sur le réseau.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        children: [
                          if (current.isNotEmpty) ...[
                            _SectionTitle(label: 'En cours', count: current.length),
                            for (final a in current) _AlertCard(alert: a, net: widget.net, today: today),
                          ],
                          if (soon.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _SectionTitle(label: 'À venir', count: soon.length),
                            for (final a in soon) _AlertCard(alert: a, net: widget.net, today: today),
                          ],
                          const SizedBox(height: 10),
                          const Text(
                            'Les perturbations terminées disparaissent d’elles-mêmes de cette liste.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text('$label ($count)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kInk)),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.net, required this.today});
  final TrafficAlert alert;
  final Network net;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final sev = _severityStyle(alert.severity);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _AlertSheet(alert: alert, net: net, today: today),
        ),
        child: Semantics(
          label: '${sev.label} : ${alert.title}',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: sev.background, shape: BoxShape.circle),
                  child: Icon(sev.icon, size: 20, color: sev.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kInk)),
                      const SizedBox(height: 3),
                      Text(_periodLabel(alert, today), style: TextStyle(fontSize: 13, color: sev.color, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ..._lineBadges(net, alert.lines),
                          if (alert.example) const _ExampleTag(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertSheet extends StatelessWidget {
  const _AlertSheet({required this.alert, required this.net, required this.today});
  final TrafficAlert alert;
  final Network net;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final sev = _severityStyle(alert.severity);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: sev.background, shape: BoxShape.circle),
                  child: Icon(sev.icon, size: 20, color: sev.color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: kInk))),
              ],
            ),
            const SizedBox(height: 8),
            Text(_periodLabel(alert, today), style: TextStyle(fontSize: 14, color: sev.color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ..._lineBadges(net, alert.lines),
                if (alert.example) const _ExampleTag(),
              ],
            ),
            const SizedBox(height: 16),
            Text(alert.body, style: const TextStyle(fontSize: 15, height: 1.4)),
            if (alert.updated != null) ...[
              const SizedBox(height: 16),
              Text('Mis à jour le ${_frDayMonth(alert.updated!)} à ${_hhmm(alert.updated!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            if (alert.example) ...[
              const SizedBox(height: 14),
              const Text(
                'Information d’exemple, écrite pour la maquette. Un back-office de l’exploitant alimentera cette liste.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A4800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Étiquette « exemple » : elle accompagne chaque donnée simulée, carte par carte.
/// Le bandeau en haut de l'écran ne suffit pas — une capture d'une seule carte circulera.
class _ExampleTag extends StatelessWidget {
  const _ExampleTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF9A5B00)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('exemple', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A5B00))),
    );
  }
}

/// Badges des lignes concernées. Une alerte désigne les lignes par leur nom public (« M2 ») :
/// l'identifiant interne du GTFS est un compteur et ne survit pas à une régénération.
List<Widget> _lineBadges(Network net, List<String> lines) {
  if (lines.isEmpty) {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFEFF3F6), borderRadius: BorderRadius.circular(6)),
        child: const Text('Tout le réseau', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
      ),
    ];
  }
  final out = <Widget>[];
  for (final name in lines) {
    final route = net.routes.where((r) => r.short.toUpperCase() == name.toUpperCase()).firstOrNull;
    if (route != null) {
      out.add(RouteBadge(route: route, size: 0.9));
    } else {
      // Ligne inconnue du GTFS embarqué : on l'affiche quand même plutôt que de la perdre.
      out.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFEFF3F6), borderRadius: BorderRadius.circular(6)),
        child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
      ));
    }
  }
  return out;
}

({Color color, Color background, IconData icon, String label}) _severityStyle(AlertSeverity s) {
  switch (s) {
    case AlertSeverity.severe:
      return (color: const Color(0xFFB3261E), background: const Color(0xFFFCE8E6), icon: Icons.report_outlined, label: 'Perturbation');
    case AlertSeverity.warning:
      return (color: const Color(0xFF9A5B00), background: const Color(0xFFFFF4E0), icon: Icons.warning_amber_rounded, label: 'Modification');
    case AlertSeverity.info:
      return (color: kInk, background: const Color(0xFFEFF3F6), icon: Icons.info_outline, label: 'Information');
  }
}

String _periodLabel(TrafficAlert a, DateTime today) {
  final from = a.from, to = a.to;
  if (from != null && a.isUpcomingOn(today)) {
    return to != null ? 'Du ${_frDayMonth(from)} au ${_frDayMonth(to)}' : 'À partir du ${_frDayMonth(from)}';
  }
  if (to != null) return 'Jusqu’au ${_frDayMonth(to)}';
  return 'En cours';
}

// ---------------------------------------------------------------------------------------------
// Écran 4 : mes titres — parcours d'achat maquetté, aucun paiement réel
// ---------------------------------------------------------------------------------------------

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key, this.catalogLoader});

  /// D'où vient le catalogue tarifaire. Par défaut l'asset embarqué.
  final Future<FareCatalog> Function()? catalogLoader;

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final TicketWallet wallet = TicketWallet();
  bool _ready = false;

  Future<FareCatalog> _loadCatalog() => (widget.catalogLoader ?? FareCatalog.load)();

  @override
  void initState() {
    super.initState();
    wallet.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  Future<void> _buy() async {
    final ticket = await Navigator.of(context).push<Ticket>(MaterialPageRoute(
      builder: (_) => _BuyPage(catalog: _loadCatalog(), wallet: wallet),
    ));
    if (!mounted) return;
    setState(() {});
    if (ticket != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _TicketPage(ticket: ticket, wallet: wallet),
      ));
      if (mounted) setState(() {});
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer les titres de démonstration ?'),
        content: const Text('Ils ne sont enregistrés que sur ce téléphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Effacer')),
        ],
      ),
    );
    if (ok == true) {
      await wallet.clear();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final usable = wallet.usable(now);
    final spent = wallet.spent(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes titres'),
        actions: [
          if (wallet.tickets.isNotEmpty)
            IconButton(
              tooltip: 'Effacer les titres de démonstration',
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      // Pas de bouton flottant quand le portefeuille est vide : l'état vide porte déjà l'action,
      // et deux boutons identiques à l'écran font hésiter.
      floatingActionButton: _ready && wallet.tickets.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _buy,
              icon: const Icon(Icons.add_card_outlined),
              label: const Text('Acheter un titre'),
            )
          : null,
      body: Column(
        children: [
          const _Banner(text: 'Démonstration : aucun paiement réel. Ces titres ne sont pas valables à bord.'),
          Expanded(
            child: !_ready
                ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                : wallet.tickets.isEmpty
                    ? _Notice(
                        icon: Icons.confirmation_number_outlined,
                        title: 'Aucun titre',
                        text: 'Achetez un titre pour le présenter à la montée. Tout se passe sur le téléphone, sans compte.',
                        action: FilledButton.icon(
                          onPressed: _buy,
                          icon: const Icon(Icons.add_card_outlined),
                          label: const Text('Acheter un titre'),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        children: [
                          for (final t in usable)
                            _TicketCard(
                              ticket: t,
                              now: now,
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => _TicketPage(ticket: t, wallet: wallet),
                                ));
                                if (mounted) setState(() {});
                              },
                            ),
                          if (spent.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text('Titres épuisés', style: TextStyle(fontWeight: FontWeight.w800, color: kInk)),
                            const SizedBox(height: 8),
                            for (final t in spent) _TicketCard(ticket: t, now: now, onTap: null),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.now, required this.onTap});
  final Ticket ticket;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final st = _ticketStyle(ticket, now);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: st.background, shape: BoxShape.circle),
                child: Icon(st.icon, size: 20, color: st.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticket.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kInk)),
                    const SizedBox(height: 3),
                    Text(st.label, style: TextStyle(fontSize: 13, color: st.color, fontWeight: FontWeight.w600)),
                    if (!ticket.allDay && ticket.tripsLeft > 0) ...[
                      const SizedBox(height: 2),
                      Text('${ticket.tripsLeft} voyage${ticket.tripsLeft > 1 ? 's' : ''} restant${ticket.tripsLeft > 1 ? 's' : ''}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                    const SizedBox(height: 8),
                    const _ExampleTag(),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choix du titre, puis paiement simulé. Aucun champ de paiement n'est demandé : une maquette
/// ne doit pas entraîner les gens à taper un numéro de carte dans une application d'essai.
class _BuyPage extends StatefulWidget {
  const _BuyPage({required this.catalog, required this.wallet});
  final Future<FareCatalog> catalog;
  final TicketWallet wallet;

  @override
  State<_BuyPage> createState() => _BuyPageState();
}

class _BuyPageState extends State<_BuyPage> {
  bool _paying = false;

  Future<void> _confirm(Fare fare) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _CheckoutSheet(fare: fare),
    );
    if (go != true || !mounted) return;

    setState(() => _paying = true);
    // Attente volontaire : un paiement instantané donnerait l'illusion d'un vrai débit immédiat.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final ticket = await widget.wallet.buy(fare, DateTime.now());
    if (!mounted) return;
    setState(() => _paying = false);
    Navigator.of(context).pop(ticket);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acheter un titre')),
      body: FutureBuilder<FareCatalog>(
        future: widget.catalog,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Notice(
              icon: Icons.cloud_off_outlined,
              title: 'Tarifs indisponibles',
              text: 'La grille tarifaire n’a pas pu être lue.\n${snap.error}',
              action: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Revenir'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
          }
          final cat = snap.data!;
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  for (final f in cat.fares)
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _paying ? null : () => _confirm(f),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kInk)),
                                    const SizedBox(height: 3),
                                    Text(f.description, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                    if (f.note.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(f.note, style: const TextStyle(fontSize: 12, color: Color(0xFF7A4800))),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(formatPrice(f.priceCents),
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: kInk)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    cat.source == null
                        ? 'Tarifs publics du réseau.'
                        : 'Tarifs publics du réseau, relevés le ${_frJjMmAaaa(cat.fetched)} sur ${cat.source}.',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              if (_paying)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('Paiement simulé…', style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CheckoutSheet extends StatelessWidget {
  const _CheckoutSheet({required this.fare});
  final Fare fare;

  @override
  Widget build(BuildContext context) {
    // Défilable : à 1,6× de texte, le récapitulatif dépasse la hauteur d'une feuille.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Récapitulatif', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: kInk)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text(fare.name, style: const TextStyle(fontSize: 16, color: kInk))),
              Text(formatPrice(fare.priceCents), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: kInk)),
            ],
          ),
          const SizedBox(height: 4),
          Text(fare.description, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 18),
          const _Banner(text: 'Aucun paiement ne sera effectué. Aucun numéro de carte n’est demandé, ici ou ailleurs dans l’application.'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Payer (simulation)'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          ),
        ],
      ),
      ),
    );
  }
}

/// Le titre lui-même : ce qu'on montre à la montée. Compte à rebours vivant, QR factice.
class _TicketPage extends StatefulWidget {
  const _TicketPage({required this.ticket, required this.wallet});
  final Ticket ticket;
  final TicketWallet wallet;

  @override
  State<_TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<_TicketPage> {
  late Ticket ticket = widget.ticket;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startTicking();
  }

  /// La seconde ne tourne que pendant un voyage : un titre en attente n'a rien à décompter,
  /// et un écran qui se redessine chaque seconde pour rien use la batterie.
  void _startTicking() {
    if (_tick != null || !ticket.runningAt(DateTime.now())) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (!ticket.runningAt(DateTime.now())) {
        t.cancel();
        _tick = null;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _validate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Commencer le voyage ?'),
        content: Text(ticket.allDay
            ? 'Le titre sera valable jusqu’à la fin de la journée.'
            : 'Un voyage sera décompté, avec ${ticket.validityMinutes} minutes de correspondance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pas encore')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok != true) return;
    final updated = await widget.wallet.validate(ticket.id, DateTime.now());
    if (updated != null && mounted) {
      setState(() => ticket = updated);
      _startTicking();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final st = _ticketStyle(ticket, now);
    final reste = ticket.remainingAt(now);

    return Scaffold(
      appBar: AppBar(title: Text(ticket.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const _Banner(text: 'Titre de démonstration. Il n’est pas valable à bord d’un bus.'),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: st.color, width: 2),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(st.icon, color: st.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(st.label,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: st.color)),
                    ),
                  ],
                ),
                if (reste != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    label: 'il reste ${_countdownWords(reste)}',
                    child: Text(_countdown(reste),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 40, color: kInk)),
                  ),
                  const Text('avant la fin du voyage', style: TextStyle(fontSize: 13, color: Colors.black54)),
                ],
                const SizedBox(height: 18),
                _FakeQr(seed: ticket.id),
                const SizedBox(height: 14),
                Text(ticket.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kInk)),
                Text(
                  'Acheté le ${_frDayMonth(ticket.purchasedAt)} à ${_hhmm(ticket.purchasedAt)} · ${formatPrice(ticket.priceCents)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                if (!ticket.allDay) ...[
                  const SizedBox(height: 4),
                  Text('${ticket.tripsLeft} voyage${ticket.tripsLeft > 1 ? 's' : ''} restant${ticket.tripsLeft > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 13, color: kInk, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (ticket.canValidateAt(now))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _validate,
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Valider mon voyage'),
              ),
            )
          else if (ticket.stateAt(now) == TicketState.epuise)
            const Text('Ce titre est épuisé.', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

/// QR dessiné, volontairement faux : « DÉMONSTRATION » en travers, et aucun encodeur derrière.
/// Un vrai QR demanderait une dépendance que le brief n'autorise pas — et un faux QR crédible
/// serait pire qu'un faux QR assumé.
class _FakeQr extends StatelessWidget {
  const _FakeQr({required this.seed});
  final String seed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'code QR de démonstration, sans valeur',
      child: SizedBox(
        width: 190,
        height: 190,
        child: CustomPaint(painter: _FakeQrPainter(seed: seed)),
      ),
    );
  }
}

class _FakeQrPainter extends CustomPainter {
  _FakeQrPainter({required this.seed});
  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 25;
    final cell = size.width / n;
    final black = Paint()..color = kInk;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Suite déterministe : le même titre dessine toujours le même motif.
    var x = seed.hashCode == 0 ? 42 : seed.hashCode.abs();
    int next() {
      x ^= x << 13;
      x ^= x >> 17;
      x ^= x << 5;
      return x.abs();
    }

    bool inFinder(int r, int c) =>
        (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (inFinder(r, c)) continue;
        if (next() % 100 < 46) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), black);
        }
      }
    }

    void finder(int r, int c) {
      canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, 7 * cell, 7 * cell), black);
      canvas.drawRect(Rect.fromLTWH((c + 1) * cell, (r + 1) * cell, 5 * cell, 5 * cell), Paint()..color = Colors.white);
      canvas.drawRect(Rect.fromLTWH((c + 2) * cell, (r + 2) * cell, 3 * cell, 3 * cell), black);
    }

    finder(0, 0);
    finder(0, n - 7);
    finder(n - 7, 0);

    // Bandeau « DÉMONSTRATION » : le code ne doit jamais pouvoir passer pour un vrai titre.
    final bandeau = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: size.width, height: 30);
    canvas.drawRect(bandeau, Paint()..color = Colors.white.withValues(alpha: 0.94));
    final tp = TextPainter(
      text: const TextSpan(
        text: 'DÉMONSTRATION',
        style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_FakeQrPainter old) => old.seed != seed;
}

({Color color, Color background, IconData icon, String label}) _ticketStyle(Ticket t, DateTime now) {
  switch (t.stateAt(now)) {
    case TicketState.enCours:
      return (color: const Color(0xFF0B7A6E), background: const Color(0xFFDFF5F2), icon: Icons.check_circle_outline, label: 'Voyage en cours');
    case TicketState.aValider:
      return (color: kInk, background: const Color(0xFFEFF3F6), icon: Icons.confirmation_number_outlined, label: 'À valider à la montée');
    case TicketState.epuise:
      return (color: const Color(0xFF6B7280), background: const Color(0xFFF1F3F5), icon: Icons.history, label: 'Épuisé');
  }
}

String _countdown(Duration d) {
  if (d.inHours >= 1) return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

String _countdownWords(Duration d) {
  if (d.inHours >= 1) return '${d.inHours} heures et ${d.inMinutes % 60} minutes';
  if (d.inMinutes >= 1) return '${d.inMinutes} minutes';
  return '${d.inSeconds} secondes';
}

String _frJjMmAaaa(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  return d == null ? (iso ?? '') : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ---------------------------------------------------------------------------------------------
// Écran 5 : plan du réseau, boutiques, transport à la demande, liens officiels
// ---------------------------------------------------------------------------------------------

/// Ouvre un lien (page web, numéro de téléphone, courriel). Renvoie false si rien ne s'est ouvert.
typedef LinkOpener = Future<bool> Function(String url);

Future<bool> _defaultOpener(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, required this.net, this.loader, this.opener});
  final Network net;
  final Future<PracticalInfo> Function()? loader;

  /// Comment ouvrir un lien. Injectable : les tests vérifient ce qui serait composé,
  /// sans rien ouvrir pour de vrai.
  final LinkOpener? opener;

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  late Future<PracticalInfo> _info = (widget.loader ?? PracticalInfo.load)();
  String? _selectedRoute;

  void _reload() {
    setState(() {
      _info = (widget.loader ?? PracticalInfo.load)();
    });
  }

  Future<void> _open(String url, {required String copyIfFailed}) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await (widget.opener ?? _defaultOpener)(url);
    if (ok) return;
    // Repli : si rien ne s'ouvre, au moins l'information part dans le presse-papiers.
    await Clipboard.setData(ClipboardData(text: copyIfFailed));
    messenger.showSnackBar(SnackBar(content: Text('Copié : $copyIfFailed')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan et infos')),
      body: FutureBuilder<PracticalInfo>(
        future: _info,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Notice(
              icon: Icons.cloud_off_outlined,
              title: 'Informations indisponibles',
              text: 'Les informations pratiques n’ont pas pu être lues.\n${snap.error}',
              action: FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
            );
          }
          if (!snap.hasData) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
          }
          final info = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              const _SectionHeader(icon: Icons.map_outlined, title: 'Plan du réseau'),
              const SizedBox(height: 8),
              _MapCard(
                net: widget.net,
                selected: _selectedRoute,
                onSelect: (id) => setState(() => _selectedRoute = _selectedRoute == id ? null : id),
                onExpand: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _MapPage(net: widget.net, selected: _selectedRoute),
                )),
              ),
              const SizedBox(height: 22),
              const _SectionHeader(icon: Icons.storefront_outlined, title: 'Boutiques'),
              const SizedBox(height: 8),
              for (final s in info.shops)
                _ShopCard(shop: s, onCall: () => _open(telUri(s.phone), copyIfFailed: s.phone)),
              if (info.shops.isEmpty) const Text('Aucune boutique renseignée.', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 22),
              if (info.onDemand != null) ...[
                _SectionHeader(icon: Icons.phone_in_talk_outlined, title: info.onDemand!.title),
                const SizedBox(height: 8),
                _OnDemandCard(
                  info: info.onDemand!,
                  onCall: () => _open(telUri(info.onDemand!.phone), copyIfFailed: info.onDemand!.phone),
                ),
                const SizedBox(height: 22),
              ],
              const _SectionHeader(icon: Icons.link_outlined, title: 'Liens officiels'),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: Colors.white,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
                child: Column(
                  children: [
                    for (final l in info.links)
                      ListTile(
                        leading: const Icon(Icons.open_in_new, color: kTeal),
                        title: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600, color: kInk)),
                        onTap: () => _open(l.url, copyIfFailed: l.url),
                      ),
                    if (info.email.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.mail_outline, color: kTeal),
                        title: const Text('Écrire au service client', style: TextStyle(fontWeight: FontWeight.w600, color: kInk)),
                        subtitle: Text(info.email, style: const TextStyle(fontSize: 12)),
                        onTap: () => _open('mailto:${info.email}', copyIfFailed: info.email),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SectionHeader(icon: Icons.info_outline, title: 'D’où viennent ces informations'),
              const SizedBox(height: 8),
              Text(
                [
                  'Horaires du réseau « ${widget.net.name} » : données ouvertes de la collectivité, converties le ${widget.net.generated}, valables du ${_frAaaammjj(widget.net.validFrom)} au ${_frAaaammjj(widget.net.validTo)}.',
                  if (info.source != null)
                    'Boutiques et transport à la demande : relevés le ${_frJjMmAaaa(info.fetched)} sur ${info.source}.',
                  'Tout est embarqué dans l’application : elle fonctionne sans réseau et n’envoie aucune donnée.',
                ].join('\n\n'),
                style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kTeal),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kInk))),
      ],
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.net, required this.selected, required this.onSelect, required this.onExpand});
  final Network net;
  final String? selected;
  final void Function(String routeId) onSelect;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  maxScale: 8,
                  child: NetworkMap(net: net, selected: selected),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in net.routes)
                  GestureDetector(
                    onTap: () => onSelect(r.id),
                    child: Opacity(
                      opacity: selected == null || selected == r.id ? 1 : 0.35,
                      child: RouteBadge(route: r, size: 0.95),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              selected == null
                  ? 'Touchez une ligne pour l’isoler. Pincez pour zoomer.'
                  : 'Ligne isolée. Touchez-la de nouveau pour tout réafficher.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            const Text(
              'Schéma tracé depuis les données ouvertes, d’arrêt à arrêt : les parcours réels suivent les rues.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: onExpand, icon: const Icon(Icons.open_in_full), label: const Text('Agrandir')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPage extends StatefulWidget {
  const _MapPage({required this.net, required this.selected});
  final Network net;
  final String? selected;

  @override
  State<_MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<_MapPage> {
  late String? selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan du réseau')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.white,
              child: InteractiveViewer(maxScale: 12, child: NetworkMap(net: widget.net, selected: selected)),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in widget.net.routes)
                      GestureDetector(
                        onTap: () => setState(() => selected = selected == r.id ? null : r.id),
                        child: Opacity(
                          opacity: selected == null || selected == r.id ? 1 : 0.35,
                          child: RouteBadge(route: r),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Schéma d’arrêt à arrêt, tracé depuis les données ouvertes.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Le réseau dessiné depuis les coordonnées des arrêts et l'ordre des parcours.
/// Rien n'est repris du plan publié par l'exploitant : tout vient des données ouvertes.
class NetworkMap extends StatelessWidget {
  const NetworkMap({super.key, required this.net, this.selected});
  final Network net;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    if (net.stops.isEmpty) {
      return const Center(child: Text('Aucun arrêt à afficher.', style: TextStyle(color: Colors.black54)));
    }
    return Semantics(
      label: 'plan schématique du réseau',
      child: SizedBox.expand(child: CustomPaint(painter: _NetworkMapPainter(net: net, selected: selected))),
    );
  }
}

class _NetworkMapPainter extends CustomPainter {
  _NetworkMapPainter({required this.net, required this.selected});
  final Network net;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (net.stops.isEmpty) return;
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final s in net.stops) {
      if (s.lat < minLat) minLat = s.lat;
      if (s.lat > maxLat) maxLat = s.lat;
      if (s.lon < minLon) minLon = s.lon;
      if (s.lon > maxLon) maxLon = s.lon;
    }
    // Projection suffisante pour 30 km de côté : on corrige la longitude par la latitude.
    final kx = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanX = (maxLon - minLon) * kx, spanY = maxLat - minLat;
    if (spanX <= 0 || spanY <= 0) return;
    const pad = 10.0;
    final scale = math.min((size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanY);
    final dx = (size.width - spanX * scale) / 2, dy = (size.height - spanY * scale) / 2;
    Offset at(Stop s) => Offset(dx + (s.lon - minLon) * kx * scale, dy + (maxLat - s.lat) * scale);

    void drawRoutes({required bool wanted}) {
      for (final p in net.patterns) {
        final isSelected = selected == null || p.routeId == selected;
        if (isSelected != wanted) continue;
        final route = net.routeById[p.routeId];
        if (route == null) continue;
        final pts = [
          for (final id in p.stopIds)
            if (net.stopById[id] != null) at(net.stopById[id]!),
        ];
        if (pts.length < 2) continue;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = wanted ? 2.6 : 1.4
          ..color = wanted ? spineOn(hexColor(route.color)) : const Color(0xFFD7DEE5);
        canvas.drawPoints(PointMode.polygon, pts, paint);
      }
    }

    // Les lignes non retenues passent d'abord, en gris : le réseau reste lisible autour.
    if (selected != null) drawRoutes(wanted: false);
    drawRoutes(wanted: true);

    final dot = Paint()..color = const Color(0xFF64748B);
    for (final s in net.stops) {
      canvas.drawCircle(at(s), 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(_NetworkMapPainter old) => old.net != net || old.selected != selected;
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop, required this.onCall});
  final Shop shop;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kInk)),
            const SizedBox(height: 4),
            Text(shop.address, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            for (final h in shop.hours) Text(h, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            if (shop.phone.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call),
                  label: Text(shop.phone),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OnDemandCard extends StatelessWidget {
  const _OnDemandCard({required this.info, required this.onCall});
  final OnDemand info;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.intro.isNotEmpty) ...[
              Text(info.intro, style: const TextStyle(fontSize: 14, height: 1.35)),
              const SizedBox(height: 12),
            ],
            if (info.phone.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call),
                  label: Text('Réserver au ${info.phone}'),
                ),
              ),
            const SizedBox(height: 12),
            for (final h in info.hours) Text(h, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            if (info.rules.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final r in info.rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 8),
                        child: Icon(Icons.circle, size: 5, color: kTeal),
                      ),
                      Expanded(child: Text(r, style: const TextStyle(fontSize: 13, height: 1.35))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _frAaaammjj(String yyyymmdd) {
  if (yyyymmdd.length != 8) return yyyymmdd;
  return '${yyyymmdd.substring(6, 8)}/${yyyymmdd.substring(4, 6)}/${yyyymmdd.substring(0, 4)}';
}

String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Nom de ligne lisible : le GTFS ecrit « Le Creusot < > Torcy ».
String _lineName(BusLine r) {
  final long = r.long.replaceAll(RegExp(r'\s*<\s*>\s*'), ' \u2194 ').trim();
  return long.isEmpty ? 'Ligne ${r.short}' : long;
}

const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

String _frDate(DateTime d) => '${_jours[d.weekday - 1]} ${_frDayMonth(d)}';

String _frDayMonth(DateTime d) => '${d.day == 1 ? '1er' : d.day} ${_mois[d.month - 1]}';

/// Couleur de texte lisible sur un fond : la valeur declaree si elle passe le contraste AA
/// (4,5:1), sinon le noir ou le blanc, selon ce que le fond supporte.
Color readableOn(Color background, Color declared) {
  if (contrastRatio(background, declared) >= 4.5) return declared;
  return contrastRatio(background, Colors.black) >= contrastRatio(background, Colors.white) ? Colors.black : Colors.white;
}

/// Couleur de ligne assombrie juste assez pour rester visible sur fond blanc.
/// Le jaune de la navette TGV (#FFEE00) disparaît sinon : un trait que personne ne voit
/// n'est pas un repère. On garde la teinte, on baisse la luminosité.
Color spineOn(Color c) {
  var out = c;
  for (var i = 0; i < 20 && contrastRatio(out, Colors.white) < 2.5; i++) {
    out = Color.fromARGB(255, (out.r * 255 * 0.88).round(), (out.g * 255 * 0.88).round(), (out.b * 255 * 0.88).round());
  }
  return out;
}

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Convertit « #RRGGBB » en couleur. Public : les tests vérifient le contraste des badges
/// sur les vraies couleurs du réseau.
Color hexColor(String h) {
  final v = int.tryParse(h.replaceFirst('#', ''), radix: 16) ?? 0x0F2A4F;
  return Color(0xFF000000 | v);
}
