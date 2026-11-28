// ---------------------------------------------------------------------------
// Datei:        lib/screens/nas_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.27.21.00.00
//
// Beschreibung: NAS (Synology DSM, TrueNAS) per HTTPS — Zustand, Speicher,
//               Platten, Probleme; DSM- und Paket-Updates anstoßen (DSM nur mit
//               dem Wort UPDATE, das NAS startet neu); Vorgänge mit Protokoll.
//               Quelle: /api/nas. Einrichten geht in der Weboberfläche.
//               NAS an einem anderen Standort: der Weg über den Agent dort
//               (via_agent, ab Server 0.3.0) steht an Liste und Detail.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

String _statusLevel(String? s) => switch (s) {
      'ok' => 'info',
      'warning' => 'warning',
      'critical' || 'down' => 'critical',
      _ => 'notice',
    };

String _statusText(String? s) => switch (s) {
      'ok' => 'in Ordnung',
      'warning' => 'Warnung',
      'critical' => 'kritisch',
      'down' => 'nicht erreichbar',
      _ => 'ungeprüft',
    };

String fmtBytes(Object? v) {
  final n = (v is num) ? v.toDouble() : double.tryParse('$v');
  if (n == null || n <= 0) return '–';
  const u = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var x = n;
  var i = 0;
  while (x >= 1024 && i < u.length - 1) {
    x /= 1024;
    i++;
  }
  return '${i >= 3 ? x.toStringAsFixed(1) : x.round()} ${u[i]}';
}

class NasPage extends StatelessWidget {
  const NasPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NasPage()));

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return Scaffold(
      appBar: AppBar(title: const Text('NAS')),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => ((await api.getRaw('/api/nas')) as List).cast<Map<String, dynamic>>(),
        builder: (context, items, reload) => RefreshIndicator(
          onRefresh: reload,
          child: items.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.storage_rounded,
                      title: 'Kein NAS verbunden',
                      text: 'Einrichten in der Weboberfläche: Geräte → NAS → NAS verbinden.'),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _NasCard(items[i], onChanged: reload),
                ),
        ),
      ),
    );
  }
}

class _NasCard extends StatelessWidget {
  final Map<String, dynamic> n;
  final Future<void> Function() onChanged;
  const _NasCard(this.n, {required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final upd = (n['updates_summary'] as Map?) ?? const {};
    final vols = ((n['volumes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final problems = ((n['problems'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NasDetailPage(id: n['id'] as int)));
            await onChanged();
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              leading: SeverityDot(_statusLevel(n['status'] as String?)),
              title: Text('${n['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([n['model'], n['firmware']].where((e) => e != null && '$e'.isNotEmpty).join(' · ')),
              trailing: Text(_statusText(n['status'] as String?),
                  style: TextStyle(color: severityColor(context, _statusLevel(n['status'] as String?)), fontSize: 12)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (upd['dsm'] != null) Pill('DSM ${upd['dsm']}', color: RimTheme.gold, icon: Icons.system_update_alt_rounded),
                  if ((upd['packages'] ?? 0) as int > 0) Pill('${upd['packages']} Pakete', color: cs.primary),
                  if (n['temperature'] != null) Pill('${n['temperature']} °C', color: cs.outline),
                  Pill('gelesen ${relativeTime(n['last_ok_at'] as String?)}', color: cs.outline),
                  if (n['via_agent'] is Map)
                    Pill(_viaText(n['via_agent'] as Map),
                        color: (n['via_agent'] as Map)['ready'] == true ? cs.primary : const Color(0xFFE5484D),
                        icon: Icons.hub_rounded),
                ]),
                for (final v in vols) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(flex: 2, child: Text('${v['name']}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
                    Expanded(
                      flex: 5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ((v['percent'] as num?) ?? 0) / 100,
                          minHeight: 7,
                          color: ((v['percent'] as num?) ?? 0) >= 90
                              ? const Color(0xFFE5484D)
                              : ((v['percent'] as num?) ?? 0) >= 80
                                  ? RimTheme.gold
                                  : const Color(0xFF30A46C),
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(v['percent'] == null ? '–' : '${(v['percent'] as num).round()} %', style: const TextStyle(fontSize: 12)),
                  ]),
                ],
                for (final p in problems.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('• ${p['text']}',
                        style: TextStyle(color: severityColor(context, p['level'] as String?), fontSize: 13)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class NasDetailPage extends StatefulWidget {
  final int id;
  const NasDetailPage({super.key, required this.id});
  @override
  State<NasDetailPage> createState() => _NasDetailPageState();
}

class _NasDetailPageState extends State<NasDetailPage> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  Timer? _timer;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final d = await context.session.api!.getJson('/api/nas/${widget.id}');
    _timer?.cancel();
    final jobs = ((d['jobs'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (d['busy'] == true || jobs.any((j) => j['status'] == 'running')) {
      _timer = Timer(const Duration(seconds: 5), () => _key.currentState?.reload());
    }
    return d;
  }

  Future<void> _refresh(bool updates) async {
    try {
      await context.session.api!.postJson('/api/nas/${widget.id}/refresh${updates ? '?updates=true' : ''}', {});
      if (mounted) showInfo(context, updates ? 'Zustand und Updates gelesen.' : 'Zustand gelesen.');
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _dsm(Map<String, dynamic> d, Map dsm) async {
    final ok = await confirmWord(
        context,
        'DSM ${dsm['version']} installieren?',
        '„${d['name']}“ lädt das Update, installiert es und startet neu – einige Minuten nicht erreichbar. '
            'Vorher wird die Konfiguration gesichert, falls ein Backup-Auftrag dafür besteht.',
        'UPDATE');
    if (!ok || !mounted) return;
    try {
      await context.session.api!.postJson('/api/nas/${widget.id}/update', {'what': 'dsm', 'confirm': 'UPDATE'});
      if (mounted) showInfo(context, 'DSM-Update gestartet – Fortschritt unter Vorgänge.');
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _packages(List<String> ids) async {
    final ok = await confirmDialog(context, '${ids.length} Paket(e) aktualisieren?',
        'Betroffene Dienste auf dem NAS starten dabei kurz neu.',
        action: 'Aktualisieren');
    if (!ok || !mounted) return;
    try {
      await context.session.api!.postJson('/api/nas/${widget.id}/update', {'what': 'packages', 'packages': ids});
      if (mounted) showInfo(context, 'Paket-Updates gestartet.');
      _selected.clear();
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.session.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('NAS'), actions: [
        if (admin)
          PopupMenuButton<String>(
            onSelected: (v) => _refresh(v == 'updates'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'state', child: Text('Neu lesen')),
              PopupMenuItem(value: 'updates', child: Text('Updates prüfen')),
            ],
          ),
      ]),
      body: AsyncView<Map<String, dynamic>>(
        key: _key,
        load: _load,
        builder: (context, d, reload) {
          final cs = context.cs;
          final st = (d['state'] as Map?) ?? const {};
          final sys = (st['system'] as Map?) ?? const {};
          final load = (st['load'] as Map?) ?? const {};
          final upd = (d['updates'] as Map?) ?? const {};
          final dsm = (upd['dsm'] as Map?) ?? const {};
          final pkgs = ((upd['packages'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final disks = ((st['disks'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final vols = ((st['volumes'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final problems = ((d['problems'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final jobs = ((d['jobs'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final tasks = ((st['backup_tasks'] as List?) ?? const []).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              ListTile(
                leading: SeverityDot(_statusLevel(d['status'] as String?)),
                title: Text('${d['name']}', style: Theme.of(context).textTheme.titleLarge),
                subtitle: Text('${sys['model'] ?? d['vendor_label']} · ${sys['firmware'] ?? '–'}\n${d['url']}'
                    '${d['via_agent'] is Map ? '\n${_viaText(d['via_agent'] as Map)}'
                        '${(d['via_agent'] as Map)['ready'] == true ? '' : ' – Agent nicht verbunden'}' : ''}'),
                isThreeLine: true,
              ),
              if (d['last_error'] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('${d['last_error']}', style: const TextStyle(color: Color(0xFFE5484D))),
                ),
              if (problems.isNotEmpty) ...[
                const SectionHeader('Probleme'),
                for (final p in problems)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.warning_amber_rounded, color: severityColor(context, p['level'] as String?)),
                    title: Text('${p['text']}'),
                  ),
              ],
              const SectionHeader('System'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  Pill('CPU ${load['cpu'] == null ? '–' : '${(load['cpu'] as num).round()} %'}', color: cs.primary),
                  Pill('RAM ${load['mem'] == null ? '–' : '${(load['mem'] as num).round()} %'}', color: cs.primary),
                  if (sys['temperature'] != null) Pill('${sys['temperature']} °C', color: cs.outline),
                  if (sys['uptime'] != null && '${sys['uptime']}'.isNotEmpty) Pill('läuft ${sys['uptime']}', color: cs.outline),
                  Pill(d['snmp_device_id'] != null ? 'SNMP überwacht' : 'ohne SNMP', color: cs.outline),
                ]),
              ),
              const SectionHeader('Speicher'),
              for (final v in vols)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${v['name']}  ·  ${v['status'] ?? ''}')),
                      Text('${fmtBytes(v['used'])} / ${fmtBytes(v['total'])}', style: const TextStyle(fontSize: 12)),
                    ]),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: ((v['percent'] as num?) ?? 0) / 100,
                      minHeight: 7,
                      color: ((v['percent'] as num?) ?? 0) >= 90 ? const Color(0xFFE5484D) : const Color(0xFF30A46C),
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ]),
                ),
              for (final x in disks)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.album_outlined),
                  title: Text('${x['name']} · ${x['model'] ?? ''}'),
                  subtitle: Text('${x['status'] ?? '–'} · S.M.A.R.T. ${x['smart'] ?? '–'} · ${fmtBytes(x['size'])}'),
                  trailing: Text(x['temp'] == null ? '' : '${x['temp']} °C'),
                ),
              SectionHeader('Updates', trailing: Text('geprüft ${relativeTime(upd['checked_at'] as String?)}',
                  style: TextStyle(color: cs.outline, fontSize: 12))),
              ListTile(
                leading: const Icon(Icons.system_update_rounded),
                title: Text(dsm['available'] == true ? 'DSM ${dsm['version']}' : 'DSM aktuell'),
                subtitle: Text(dsm['available'] == true ? 'Installation mit Neustart' : '${sys['firmware'] ?? ''}'),
                trailing: admin && dsm['available'] == true && d['busy'] != true
                    ? FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: () => _dsm(d, dsm),
                        child: const Text('Installieren'))
                    : null,
              ),
              for (final p in pkgs)
                CheckboxListTile(
                  dense: true,
                  value: _selected.contains(p['id']),
                  onChanged: admin ? (v) => setState(() => v == true ? _selected.add('${p['id']}') : _selected.remove(p['id'])) : null,
                  title: Text('${p['name']}'),
                  subtitle: Text('${p['installed']} → ${p['available']}'),
                ),
              if (admin && pkgs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.tonal(
                    onPressed: d['busy'] == true
                        ? null
                        : () => _packages(_selected.isEmpty ? pkgs.map((p) => '${p['id']}').toList() : _selected.toList()),
                    child: Text(_selected.isEmpty ? 'Alle ${pkgs.length} Pakete aktualisieren' : '${_selected.length} Paket(e) aktualisieren'),
                  ),
                ),
              if (tasks.isNotEmpty) ...[
                const SectionHeader('Hyper Backup'),
                for (final t in tasks)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.backup_outlined),
                    title: Text('${t['name']}'),
                    subtitle: Text('letzter Lauf: ${t['last_time'] ?? '–'} · ${t['last_result'] ?? '–'}'),
                  ),
              ],
              if (jobs.isNotEmpty) ...[
                const SectionHeader('Vorgänge'),
                for (final j in jobs.take(8))
                  ExpansionTile(
                    leading: Icon(
                        j['status'] == 'done'
                            ? Icons.check_circle_outline
                            : j['status'] == 'error'
                                ? Icons.error_outline
                                : Icons.hourglass_top_rounded,
                        color: j['status'] == 'done'
                            ? const Color(0xFF30A46C)
                            : j['status'] == 'error'
                                ? const Color(0xFFE5484D)
                                : cs.primary),
                    title: Text(switch (j['kind']) {
                      'dsm_update' => 'DSM-Update',
                      'package_update' => 'Paket-Updates',
                      'snmp_enable' => 'SNMP einschalten',
                      _ => '${j['kind']}',
                    }),
                    subtitle: Text('${relativeTime(j['started_at'] as String?)}${j['error'] != null ? ' · ${j['error']}' : ''}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SelectableText(
                          ((j['log'] as List?) ?? const []).map((l) => '${(l as Map)['text']}').join('\n'),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ],
                  ),
              ],
            ]),
          );
        },
      ),
    );
  }
}

/// "über Agent pc-empfang" bzw. "über Agent auf dem NAS" – mit Standort.
String _viaText(Map a) {
  final who = a['on_nas'] == true ? 'Agent auf dem NAS' : 'Agent ${a['hostname'] ?? '?'}';
  final site = '${a['site'] ?? ''}';
  return 'über $who${site.isNotEmpty ? ' · $site' : ''}';
}
