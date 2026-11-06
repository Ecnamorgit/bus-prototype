// Point d'entrée du MVP. Deux écrans sont réellement implémentés (Passages, Lignes) sur le vrai GTFS ;
// Infos trafic, Mes titres et Plus sont des coquilles à compléter (voir CLAUDE.md, périmètre).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/network.dart';
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
      const PlaceholderScreen(title: 'Infos trafic', hint: 'Alertes par ligne (assets/data/alerts.json), étiquetées « exemple ».'),
      const PlaceholderScreen(title: 'Mes titres', hint: 'Parcours d’achat maquetté, QR factice, bandeau « démonstration ».'),
      const PlaceholderScreen(title: 'Plus', hint: 'Plan du réseau, boutiques, TAD, mentions.'),
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
  const DeparturesScreen({super.key, required this.net, required this.sched, required this.favorites, required this.onChanged});
  final Network net;
  final Schedule sched;
  final Favorites favorites;
  final VoidCallback onChanged;

  @override
  State<DeparturesScreen> createState() => _DeparturesScreenState();
}

class _DeparturesScreenState extends State<DeparturesScreen> {
  Timer? _tick;
  DateTime now = DateTime.now();

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

  @override
  Widget build(BuildContext context) {
    final favs = widget.favorites.ids.map((id) => widget.net.stopById[id]).whereType<Stop>().toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.net.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text(_hhmm(now), style: const TextStyle(fontWeight: FontWeight.w700))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStop,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Ajouter un arrêt'),
      ),
      body: favs.isEmpty
          ? _EmptyState(onAdd: _addStop)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: favs.length + 1,
              itemBuilder: (context, i) {
                if (i == favs.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Horaires prévus (données ouvertes de la collectivité, ${widget.net.generated}). Pas de temps réel.',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  );
                }
                final s = favs[i];
                final deps = widget.sched.nextDepartures(s.id, now, limit: 6);
                return _StopCard(
                  stop: s,
                  departures: deps,
                  now: now,
                  onRemove: () async {
                    await widget.favorites.toggle(s.id);
                    widget.onChanged();
                  },
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bus_outlined, size: 64, color: kInk),
            const SizedBox(height: 16),
            const Text('Vos arrêts, vos prochains bus', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Ajoutez l’arrêt que vous prenez tous les jours : les prochains passages s’affichent ici, même sans réseau.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.search), label: const Text('Chercher un arrêt')),
            // TODO(geoloc) : proposer les 3 arrêts les plus proches avec geolocator (Schedule.nearestStops).
          ],
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.stop, required this.departures, required this.now, required this.onRemove});
  final Stop stop;
  final List<Departure> departures;
  final DateTime now;
  final VoidCallback onRemove;

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
            Row(
              children: [
                const Icon(Icons.place, color: kTeal, size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text(stop.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kInk))),
                IconButton(
                  tooltip: 'Retirer des favoris',
                  onPressed: onRemove,
                  icon: const Icon(Icons.star, color: Color(0xFFFFB300)),
                ),
              ],
            ),
            if (departures.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 4),
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
          Semantics(
            label: 'départ prévu à ${_hhmm(d.scheduled)}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: mins < 10 ? kTeal : const Color(0xFFEFF3F6), borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: mins < 10 ? Colors.white : kInk)),
            ),
          ),
          const SizedBox(width: 8),
          Text(_hhmm(d.scheduled), style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _hex(route.color), borderRadius: BorderRadius.circular(8)),
      child: Semantics(
        label: 'ligne ${route.short}',
        excludeSemantics: true,
        child: Text(route.short,
            style: TextStyle(color: _readableOn(_hex(route.color), _hex(route.textColor)), fontWeight: FontWeight.w900, fontSize: 14 * size)),
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
                        color: _onWhite(_hex(widget.route.color)),
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
  const _Notice({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: kInk),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Coquilles à compléter
// ---------------------------------------------------------------------------------------------

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('À construire : $hint', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        ),
      ),
    );
  }
}

String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Nom de ligne lisible : le GTFS ecrit « Le Creusot < > Torcy ».
String _lineName(BusLine r) {
  final long = r.long.replaceAll(RegExp(r'\s*<\s*>\s*'), ' \u2194 ').trim();
  return long.isEmpty ? 'Ligne ${r.short}' : long;
}

const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _mois = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'];

String _frDate(DateTime d) => '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]}';

/// Couleur de texte lisible sur un fond : la valeur declaree si elle passe le contraste AA
/// (4,5:1), sinon le noir ou le blanc, selon ce que le fond supporte.
Color _readableOn(Color background, Color declared) {
  if (_contrast(background, declared) >= 4.5) return declared;
  return _contrast(background, Colors.black) >= _contrast(background, Colors.white) ? Colors.black : Colors.white;
}

/// Couleur de ligne assombrie juste assez pour rester visible sur fond blanc.
/// Le jaune de la navette TGV (#FFEE00) disparaît sinon : un trait que personne ne voit
/// n'est pas un repère. On garde la teinte, on baisse la luminosité.
Color _onWhite(Color c) {
  var out = c;
  for (var i = 0; i < 20 && _contrast(out, Colors.white) < 2.5; i++) {
    out = Color.fromARGB(255, (out.r * 255 * 0.88).round(), (out.g * 255 * 0.88).round(), (out.b * 255 * 0.88).round());
  }
  return out;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Color _hex(String h) {
  final v = int.tryParse(h.replaceFirst('#', ''), radix: 16) ?? 0x0F2A4F;
  return Color(0xFF000000 | v);
}
