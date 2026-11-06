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
      child: Text(route.short, style: TextStyle(color: _hex(route.textColor), fontWeight: FontWeight.w900, fontSize: 14 * size)),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Lignes')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: net.routes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final r = net.routes[i];
          return Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
            child: ListTile(
              leading: RouteBadge(route: r, size: 1.15),
              title: Text(r.long.isEmpty ? 'Ligne ${r.short}' : r.long, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RouteScreen(net: net, sched: sched, route: r, favorites: favorites, onChanged: onChanged),
              )),
            ),
          );
        },
      ),
    );
  }
}

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
  int direction = 0;

  @override
  Widget build(BuildContext context) {
    final patterns = widget.net.patternsOfRoute(widget.route.id);
    // Par sens, on garde le motif le plus long (les variantes courtes sont des sous-ensembles).
    StopPattern? longest(int dir) {
      StopPattern? best;
      for (final p in patterns.where((p) => p.direction == dir)) {
        if (best == null || p.stopIds.length > best.stopIds.length) best = p;
      }
      return best;
    }

    final p = longest(direction) ?? longest(1 - direction);
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Row(children: [RouteBadge(route: widget.route), const SizedBox(width: 10), Expanded(child: Text(widget.route.long, style: const TextStyle(fontSize: 16)))])),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text('vers ${longest(0)?.headsign ?? '—'}', overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: 1, label: Text('vers ${longest(1)?.headsign ?? '—'}', overflow: TextOverflow.ellipsis)),
              ],
              selected: {direction},
              onSelectionChanged: (s) => setState(() => direction = s.first),
            ),
          ),
          if (p == null)
            const Expanded(child: Center(child: Text('Aucun horaire pour cette ligne.')))
          else ...[
            if (widget.sched.tripCount(p.id, today) == 0)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Pas de service aujourd’hui sur ce sens.', style: TextStyle(color: Colors.black54)),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: p.stopIds.length,
                itemBuilder: (context, i) {
                  final s = widget.net.stopById[p.stopIds[i]]!;
                  final fav = widget.favorites.contains(s.id);
                  return ListTile(
                    dense: true,
                    leading: Icon(i == 0 || i == p.stopIds.length - 1 ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: _hex(widget.route.color)),
                    title: Text(s.name),
                    trailing: IconButton(
                      tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                      icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? const Color(0xFFFFB300) : null),
                      onPressed: () async {
                        await widget.favorites.toggle(s.id);
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => TimetableSheet(sched: widget.sched, pattern: p, stop: s, route: widget.route),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grille horaire du jour d'un sens à un arrêt.
class TimetableSheet extends StatelessWidget {
  const TimetableSheet({super.key, required this.sched, required this.pattern, required this.stop, required this.route});
  final Schedule sched;
  final StopPattern pattern;
  final Stop stop;
  final BusLine route;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final times = sched.timetable(pattern.id, stop.id, today);
    final nowMin = today.hour * 60 + today.minute;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [RouteBadge(route: route), const SizedBox(width: 10), Expanded(child: Text('${stop.name} → ${pattern.headsign}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))]),
          const SizedBox(height: 4),
          Text('Aujourd’hui · horaires prévus', style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 12),
          if (times.isEmpty) const Text('Pas de passage aujourd’hui.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in times)
                Chip(
                  label: Text(formatMinutes(t)),
                  backgroundColor: t >= nowMin && t < nowMin + 60 ? kTeal : null,
                  labelStyle: TextStyle(color: t >= nowMin && t < nowMin + 60 ? Colors.white : null, fontWeight: FontWeight.w700),
                  side: BorderSide.none,
                ),
            ],
          ),
        ],
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

Color _hex(String h) {
  final v = int.tryParse(h.replaceFirst('#', ''), radix: 16) ?? 0x0F2A4F;
  return Color(0xFF000000 | v);
}
