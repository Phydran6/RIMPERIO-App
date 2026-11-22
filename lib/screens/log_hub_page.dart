// ---------------------------------------------------------------------------
// Datei:        lib/screens/log_hub_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
//
// Beschreibung: Der Bereich „Logs“ unter Mehr — alles zu Logs an einer
//               Stelle: ansehen (nur Probleme), suchen (alle Stufen),
//               Themenbereiche, Rauschen & Sperren, Aufbewahrung.
//               Quellen: /api/app/logs, /api/log-handling/*.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'logs_page.dart';

class LogHubPage extends StatelessWidget {
  const LogHubPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogHubPage()));

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final handling = s.hasCapability('log-handling');
    return Scaffold(
      appBar: AppBar(title: const Text('Logs')),
      body: AsyncView<Map<String, dynamic>?>(
        load: () async => handling ? await s.api!.getJson('/api/log-handling/overview') : null,
        builder: (context, ov, reload) {
          final by = ((ov?['last_24h'] as Map?) ?? const {}).cast<String, dynamic>();
          int sum(List<String> keys) => keys.fold(0, (a, k) => a + ((by[k] as num?)?.toInt() ?? 0));
          final problems = sum(['emergency', 'alert', 'critical', 'error', 'warning']);
          final low = sum(['notice', 'info', 'informational', 'debug']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              if (ov != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.error_outline_rounded,
                        label: 'Probleme (24 h)',
                        value: fmtInt(problems),
                        color: problems > 0 ? const Color(0xFFF2555A) : const Color(0xFF30A46C),
                        onTap: () => LogsPage.open(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: Icons.blur_on_rounded,
                        label: 'Info/Hinweis (24 h)',
                        value: fmtInt(low),
                        color: context.cs.outline,
                        onTap: () => _NoisePage.open(context),
                      ),
                    ),
                  ]),
                ),
              _HubTile(
                icon: Icons.receipt_long_rounded,
                title: 'Logs ansehen',
                text: 'Warnungen, Fehler und Kritisches – ohne Info und Hinweise',
                onTap: () => LogsPage.open(context),
              ),
              _HubTile(
                icon: Icons.manage_search_rounded,
                title: 'Logs suchen',
                text: 'Alle Stufen, auch Info und Hinweise · Text, Gerät, Zeitraum',
                onTap: () => LogsPage.open(context, mode: LogMode.search),
              ),
              if (handling) ...[
                _HubTile(
                  icon: Icons.category_outlined,
                  title: 'Themenbereiche',
                  text: 'Anmeldung, Dienste, Netzwerk, Hardware … – was ist wo los?',
                  onTap: () => _CategoriesPage.open(context),
                ),
                _HubTile(
                  icon: Icons.filter_alt_outlined,
                  title: 'Rauschen & Sperren',
                  text: 'Was frisst den Platz? Unnötiges mit einem Tipp sperren',
                  onTap: () => _NoisePage.open(context),
                ),
                _HubTile(
                  icon: Icons.block_rounded,
                  title: 'Sperrregeln',
                  text: '${(ov?['rules'] as List?)?.length ?? 0} Regel(n) – an/aus, löschen',
                  onTap: () => _RulesPage.open(context),
                ),
                _HubTile(
                  icon: Icons.history_toggle_off_rounded,
                  title: 'Aufbewahrung',
                  text: _tiersText(ov),
                  onTap: () => _RetentionPage.open(context),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }

  static String _tiersText(Map<String, dynamic>? ov) {
    final t = (ov?['tiers'] as Map?)?.cast<String, dynamic>();
    if (t == null) return 'Fristen je Stufe';
    return 'Info ${t['info']} T · Hinweis ${t['notice']} T · Fehler ${t['error']} T';
  }
}

class _HubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  const _HubTile({required this.icon, required this.title, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            leading: Icon(icon, color: context.cs.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(text),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Themenbereiche
// ---------------------------------------------------------------------------
class _CategoriesPage extends StatefulWidget {
  const _CategoriesPage();
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _CategoriesPage()));
  @override
  State<_CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<_CategoriesPage> {
  bool _all = false;
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return Scaffold(
      appBar: AppBar(title: const Text('Themenbereiche'), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilterChip(
            label: const Text('auch Info'),
            selected: _all,
            onSelected: (v) {
              setState(() => _all = v);
              _key.currentState?.reload();
            },
          ),
        ),
      ]),
      body: AsyncView<Map<String, dynamic>>(
        key: _key,
        load: () => api.getJson('/api/log-handling/categories', {'hours': 24, 'problems_only': !_all}),
        builder: (context, d, reload) {
          final items = (d['items'] as List).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: reload,
            child: items.isEmpty
                ? ListView(children: const [
                    EmptyState(icon: Icons.verified_rounded, title: 'Nichts los', text: 'Keine Zeilen in den letzten 24 h.')
                  ])
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = items[i];
                      final latest = (c['latest'] as Map?)?.cast<String, dynamic>();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: context.cs.primaryContainer,
                          child: Text('${c['count']}',
                              style: TextStyle(color: context.cs.onPrimaryContainer, fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                        title: Text('${c['label']}'),
                        subtitle: Text(latest?['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _CategoryItemsPage(keyName: c['key'] as String, label: '${c['label']}', all: _all))),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _CategoryItemsPage extends StatelessWidget {
  final String keyName;
  final String label;
  final bool all;
  const _CategoryItemsPage({required this.keyName, required this.label, required this.all});

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: AsyncView<Map<String, dynamic>>(
        load: () => api.getJson('/api/log-handling/category/$keyName', {'hours': 72, 'problems_only': !all}),
        builder: (context, d, reload) {
          final items = (d['items'] as List).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: reload,
            child: items.isEmpty
                ? ListView(children: const [EmptyState(icon: Icons.inbox_outlined, title: 'Keine Zeilen')])
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                    itemBuilder: (context, i) => LogTile(item: items[i]),
                  ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rauschen
// ---------------------------------------------------------------------------
class _NoisePage extends StatefulWidget {
  const _NoisePage();
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _NoisePage()));
  @override
  State<_NoisePage> createState() => _NoisePageState();
}

class _NoisePageState extends State<_NoisePage> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  int _hours = 24;

  Future<void> _block(Map<String, dynamic> g) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(g['title']?.toString().isNotEmpty == true ? '${g['title']}' : '${g['template']}'),
            subtitle: Text('≈ ${fmtInt(g['estimated_rows'])} Zeilen · ${g['share_percent']} % der Info/Hinweise'),
          ),
          ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text('Sperren für ${g['hostname']}'),
              subtitle: const Text('nicht mehr speichern, vorhandene löschen'),
              onTap: () => Navigator.pop(ctx, 'host')),
          ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Sperren für alle Geräte'),
              onTap: () => Navigator.pop(ctx, 'all')),
          ListTile(
              leading: const Icon(Icons.timelapse_rounded),
              title: const Text('Nur kurz behalten (Debug, 1 Tag)'),
              onTap: () => Navigator.pop(ctx, 'downgrade')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final r = await context.session.api!.postJson('/api/log-handling/rules/from-log', {
        'log_id': g['sample_id'],
        'scope': choice == 'all' ? 'all' : 'host',
        'action': choice == 'downgrade' ? 'downgrade' : 'drop',
        'purge_existing': choice != 'downgrade',
      });
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showInfo(context, 'Gesperrt${(r['purged'] ?? 0) > 0 ? ' · ${fmtInt(r['purged'])} Zeilen gelöscht' : ''}.');
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Rauschen & Sperren'), actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.schedule),
          initialValue: _hours,
          onSelected: (h) {
            setState(() => _hours = h);
            _key.currentState?.reload();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 6, child: Text('6 Stunden')),
            PopupMenuItem(value: 24, child: Text('24 Stunden')),
            PopupMenuItem(value: 168, child: Text('7 Tage')),
          ],
        ),
      ]),
      body: AsyncView<Map<String, dynamic>>(
        key: _key,
        load: () => s.api!.getJson('/api/log-handling/noise', {'hours': _hours}),
        builder: (context, d, reload) {
          final groups = (d['groups'] as List).cast<Map<String, dynamic>>();
          final cs = context.cs;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                    '${d['low_share_percent']} % aller Zeilen sind Info/Hinweis/Debug. Darunter, was am häufigsten '
                    'vorkommt – nach Vorlage gruppiert (Zahlen und IPs egal). Fehler und Warnungen erscheinen hier nie.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              if (groups.isEmpty) const EmptyState(icon: Icons.verified_rounded, title: 'Kein Rauschen'),
              for (final g in groups)
                ListTile(
                  leading: SizedBox(
                    width: 48,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${g['share_percent']}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('≈${_short(g['estimated_rows'])}', style: TextStyle(fontSize: 11, color: cs.outline)),
                    ]),
                  ),
                  title: Text(g['title']?.toString().isNotEmpty == true ? '${g['title']}' : '${g['sample']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      Text('${g['hostname']} · ${g['source'] ?? ''}', style: TextStyle(color: cs.outline, fontSize: 12)),
                      if (g['blocked'] == true) const Pill('gesperrt', color: Color(0xFF30A46C)),
                      if (g['blocked'] != true && g['suggestion'] == 'sperren')
                        const Pill('sperren empfohlen', color: Color(0xFFF5A524)),
                      if (g['known_noise'] == true) Pill('Grundrauschen', color: cs.outline),
                    ]),
                  ),
                  trailing: s.isAdmin && g['blocked'] != true
                      ? IconButton(tooltip: 'Sperren', icon: const Icon(Icons.block_rounded), onPressed: () => _block(g))
                      : null,
                ),
            ]),
          );
        },
      ),
    );
  }

  static String _short(Object? n) {
    final v = (n as num?)?.toInt() ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return '$v';
  }
}

// ---------------------------------------------------------------------------
// Sperrregeln
// ---------------------------------------------------------------------------
class _RulesPage extends StatefulWidget {
  const _RulesPage();
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _RulesPage()));
  @override
  State<_RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<_RulesPage> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<void> _toggle(Map<String, dynamic> r) async {
    try {
      await context.session.api!.putJson('/api/log-handling/rules/${r['id']}', {...r, 'enabled': !(r['enabled'] == true)});
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await confirmDialog(context, 'Regel löschen?', 'Meldungen dieser Art werden dann wieder gespeichert.',
        action: 'Löschen');
    if (!ok || !mounted) return;
    try {
      await context.session.api!.delete('/api/log-handling/rules/${r['id']}');
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Sperrregeln')),
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _key,
        load: () async => ((await s.api!.getJson('/api/log-handling/rules'))['items'] as List).cast<Map<String, dynamic>>(),
        builder: (context, items, reload) => RefreshIndicator(
          onRefresh: reload,
          child: items.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.rule_rounded,
                      title: 'Noch keine Regeln',
                      text: 'Unter „Rauschen & Sperren“ oder in einer Logzeile mit einem Tipp anlegen.')
                ])
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = items[i];
                    return ListTile(
                      title: Text('${r['name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        r['hostname']?.toString().isNotEmpty == true ? r['hostname'] : 'alle Geräte',
                        r['action'] == 'drop' ? 'nicht speichern' : 'nur kurz',
                        '${fmtInt(r['hits'])} Treffer',
                      ].join(' · ')),
                      leading: Switch(value: r['enabled'] == true, onChanged: s.isAdmin ? (_) => _toggle(r) : null),
                      trailing: s.isAdmin
                          ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(r))
                          : null,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aufbewahrung
// ---------------------------------------------------------------------------
class _RetentionPage extends StatefulWidget {
  const _RetentionPage();
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _RetentionPage()));
  @override
  State<_RetentionPage> createState() => _RetentionPageState();
}

class _RetentionPageState extends State<_RetentionPage> {
  Map<String, int>? _tiers;
  bool _busy = false;
  static const _order = ['debug', 'info', 'notice', 'warning', 'error', 'critical'];

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final r = await context.session.api!.putJson('/api/log-handling/tiers', {'tiers': _tiers});
      if (!mounted) return;
      setState(() => _tiers = (r['tiers'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt())));
      showInfo(context, 'Gespeichert – greift beim nächsten stündlichen Lauf.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Aufbewahrung')),
      body: AsyncView<Map<String, dynamic>>(
        load: () => s.api!.getJson('/api/log-handling/overview'),
        builder: (context, d, reload) {
          _tiers ??= ((d['tiers'] as Map)).map((k, v) => MapEntry('$k', (v as num).toInt()));
          final defaults = (d['default_tiers'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(
                'Je unwichtiger, desto kürzer. Die allgemeine Aufbewahrung (${d['global_days']} Tage) bleibt die '
                'Obergrenze. Wiederholungen von Info/Hinweis werden ohnehin zu einer Zeile zusammengefasst.',
                style: TextStyle(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final lv in _order)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: SeverityDot(lv),
                  title: Text(Severity.label(lv)),
                  subtitle: Text('${_tiers![lv]} Tage · Empfehlung ${defaults[lv]}'),
                  trailing: s.isAdmin
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => setState(() => _tiers![lv] = (_tiers![lv]! - _step(_tiers![lv]!)).clamp(0, 3650))),
                          IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setState(() => _tiers![lv] = (_tiers![lv]! + _step(_tiers![lv]!)).clamp(0, 3650))),
                        ])
                      : null,
                ),
              ),
            if (s.isAdmin) ...[
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Speichern')),
              TextButton(onPressed: () => setState(() => _tiers = Map.of(defaults)), child: const Text('Empfehlung übernehmen')),
            ],
          ]);
        },
      ),
    );
  }

  static int _step(int v) => v < 14 ? 1 : (v < 90 ? 7 : 30);
}
