// ---------------------------------------------------------------------------
// Datei:        lib/screens/db_updates_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
//
// Beschreibung: Datenbank-Updates mit Probelauf — Datenbank-Container der
//               Rechner sehen, Analyse + Sicherung + Probelauf starten, den
//               Bericht lesen (Tabellen/Zeilen alt gegen neu, Fehler, KI) und
//               freigeben. Hauptversions-Sprünge brauchen das Wort MIGRATE.
//               Quelle: /api/db-updates.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _active = {
  'analyzing', 'backing_up', 'dryrun', 'snapshotting', 'final_backup', 'archiving', 'updating',
  'restoring', 'verifying', 'rolling_back', 'approved',
};

Color _statusColor(String? s, ColorScheme cs) => switch (s) {
      'succeeded' => const Color(0xFF30A46C),
      'failed' || 'dryrun_failed' => const Color(0xFFE5484D),
      'awaiting_approval' || 'rolled_back' => RimTheme.gold,
      _ when _active.contains(s) => cs.primary,
      _ => cs.outline,
    };

class DbUpdatesPage extends StatefulWidget {
  const DbUpdatesPage({super.key});
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DbUpdatesPage()));
  @override
  State<DbUpdatesPage> createState() => _DbUpdatesPageState();
}

class _DbUpdatesPageState extends State<DbUpdatesPage> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<void> _start(Map<String, dynamic> c) async {
    final ok = await confirmDialog(
        context,
        '${c['container']} prüfen?',
        'Analyse → Sicherung → Probelauf mit dem neuen Image in einem Wegwerf-Container. '
            'Die laufende Datenbank wird dabei nicht verändert. Ausgeführt wird erst nach deiner Freigabe.',
        action: 'Starten');
    if (!ok || !mounted) return;
    try {
      final m = await context.session.api!
          .postJson('/api/db-updates', {'agent_uid': c['agent_uid'], 'container': c['container']});
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DbUpdateDetailPage(id: m['id'] as int)));
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return Scaffold(
      appBar: AppBar(title: const Text('DB-Updates')),
      body: AsyncView<Map<String, dynamic>>(
        key: _key,
        load: () => s.api!.getJson('/api/db-updates'),
        builder: (context, d, reload) {
          final cands = (d['candidates'] as List).cast<Map<String, dynamic>>();
          final items = (d['items'] as List).cast<Map<String, dynamic>>();
          final cs = context.cs;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                    'Datenbanken werden nie blind aktualisiert: Sicherung → Probelauf mit der neuen Version → Vergleich '
                    'jeder Tabelle → Freigabe → Ausführung mit automatischem Rückweg.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              if (items.isNotEmpty) const SectionHeader('Vorgänge'),
              for (final m in items)
                ListTile(
                  leading: Icon(Icons.storage_rounded, color: _statusColor(m['status'] as String?, cs)),
                  title: Text('${m['hostname']} / ${m['container']}'),
                  subtitle: Text('${m['status_label']} · ${m['old_version'] ?? '?'} → ${m['new_version'] ?? '?'}'),
                  trailing: m['can_approve'] == true
                      ? const Pill('Freigabe', color: RimTheme.gold)
                      : const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => DbUpdateDetailPage(id: m['id'] as int)));
                    _key.currentState?.reload();
                  },
                ),
              const SectionHeader('Datenbank-Container'),
              if (cands.isEmpty)
                const EmptyState(icon: Icons.storage_outlined, title: 'Keine Datenbank-Container gefunden'),
              for (final c in cands)
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text('${c['container']}'),
                  subtitle: Text('${c['hostname']} · ${c['image']}'),
                  trailing: c['migration'] != null
                      ? Pill('${c['migration']['status_label']}', color: _statusColor(c['migration']['status'] as String?, cs))
                      : (s.isAdmin
                          ? TextButton(
                              onPressed: () => _start(c),
                              child: Text(c['update_available'] == true ? 'Update prüfen' : 'Prüfen'))
                          : null),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class DbUpdateDetailPage extends StatefulWidget {
  final int id;
  const DbUpdateDetailPage({super.key, required this.id});
  @override
  State<DbUpdateDetailPage> createState() => _DbUpdateDetailPageState();
}

class _DbUpdateDetailPageState extends State<DbUpdateDetailPage> {
  Map<String, dynamic>? _m;
  Object? _error;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_m == null || _active.contains(_m!['status'])) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await context.session.api!.getJson('/api/db-updates/${widget.id}');
      if (mounted) setState(() => _m = m);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _post(String path, Object body, String ok) async {
    setState(() => _busy = true);
    try {
      final m = await context.session.api!.postJson('/api/db-updates/${widget.id}/$path', body);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _m = m);
      showInfo(context, ok);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve({bool force = false}) async {
    final m = _m!;
    final major = m['path'] == 'major';
    final text = major
        ? 'Hauptversions-Update ${m['old_version']} → ${m['new_version']}. Andere Container im Compose-Projekt werden '
            'kurz angehalten. Abzug, Archiv des Datenverzeichnisses und Rückweg sind vorbereitet.'
        : 'Gleiche Hauptversion: frischer Abzug, dann Container-Update mit Gesundheitsprüfung.';
    final ok = major
        ? await confirmWord(context, '${m['container']} migrieren?', text, 'MIGRATE')
        : await confirmDialog(context, '${m['container']} aktualisieren?', text, action: 'Freigeben');
    if (!ok) return;
    await _post('approve', {'force': force, 'confirm': major ? 'MIGRATE' : ''}, 'Freigegeben – die Ausführung läuft.');
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final cs = context.cs;
    final s = context.session;
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: Text('DB-Update #${widget.id}')),
        body: _error != null ? ErrorState(error: _error, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final rep = (m['report'] as Map?)?.cast<String, dynamic>() ?? const {};
    final log = ((m['log'] as List?) ?? const []).cast<Map>();
    final ai = (rep['ai'] as Map?)?.cast<String, dynamic>();
    return Scaffold(
      appBar: AppBar(title: Text('${m['container']}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.storage_rounded, color: _statusColor(m['status'] as String?, cs)),
              title: Text('${m['status_label']}'),
              subtitle: Text('${m['hostname']} · ${m['engine']} ${m['old_version'] ?? '?'} → ${m['new_version'] ?? '?'}'
                  '${m['path'] == 'major' ? ' · Hauptversion' : m['path'] == 'minor' ? ' · gleiche Hauptversion' : ''}'),
              trailing: _active.contains(m['status'])
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
          ),
          if (m['error'] != null) ...[
            const SizedBox(height: 8),
            Text('${m['error']}', style: TextStyle(color: cs.error)),
          ],
          for (final (key, label) in [('dryrun', 'Probelauf'), ('verify', 'Prüfung nach dem Update')])
            if (rep[key] is Map) ..._section(context, label, (rep[key] as Map).cast<String, dynamic>()),
          if (ai != null) ...[
            const SectionHeader('KI-Einschätzung'),
            if (ai['error'] != null)
              Text('${ai['error']}', style: TextStyle(color: cs.outline))
            else ...[
              Pill(
                  switch (ai['recommendation']) {
                    'go' => 'unbedenklich',
                    'caution' => 'mit Vorsicht',
                    'stop' => 'nicht ausführen',
                    _ => '${ai['recommendation']}'
                  },
                  color: switch (ai['recommendation']) {
                    'go' => const Color(0xFF30A46C),
                    'stop' => const Color(0xFFE5484D),
                    _ => RimTheme.gold
                  }),
              const SizedBox(height: 6),
              Text('${ai['summary'] ?? ''}'),
              for (final r in (ai['risks'] as List? ?? const [])) Text('• $r'),
              if ((ai['fixups'] as List?)?.isNotEmpty == true)
                Text('${(ai['fixups'] as List).length} Anpassung(en) vorgeschlagen.', style: TextStyle(color: cs.primary)),
            ],
          ],
          if (s.isAdmin) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (m['can_approve'] == true && m['status'] == 'awaiting_approval')
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy ? null : () => _approve(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Freigeben & ausführen'),
                ),
              if (m['can_rerun'] == true && (ai?['fixups'] as List?)?.isNotEmpty == true)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy ? null : () => _post('adopt-ai', const {}, 'KI-Anpassungen übernommen, Probelauf läuft.'),
                  child: const Text('KI-Anpassungen + Probelauf'),
                ),
              if (m['can_rerun'] == true)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy ? null : () => _post('dryrun', const {}, 'Probelauf läuft.'),
                  child: const Text('Probelauf wiederholen'),
                ),
              if (m['status'] == 'dryrun_failed')
                TextButton(
                  onPressed: _busy ? null : () => _approve(force: true),
                  child: Text('Trotzdem freigeben', style: TextStyle(color: cs.error)),
                ),
              if (m['can_rollback'] == true)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await confirmWord(context, 'Rückweg?',
                              'Datenverzeichnis und Image auf den Stand vor dem Update zurücksetzen.', 'ROLLBACK')) {
                            await _post('rollback', {'confirm': 'ROLLBACK'}, 'Rückweg läuft.');
                          }
                        },
                  child: Text('Rückweg', style: TextStyle(color: cs.error)),
                ),
              if (m['can_cancel'] == true)
                TextButton(
                    onPressed: _busy ? null : () => _post('cancel', const {}, 'Abgebrochen.'), child: const Text('Abbrechen')),
            ]),
            if (m['can_rerun'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Eigene Anpassungen (SQL/JS) setzt du in der Weboberfläche unter Patchmanagement → DB-Updates.',
                    style: TextStyle(color: cs.outline, fontSize: 12)),
              ),
          ],
          const SectionHeader('Verlauf'),
          for (final l in log.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('${clockTime(l['ts'] as String?)}  ${l['text']}',
                  style: TextStyle(
                      fontSize: 13,
                      color: l['level'] == 'error'
                          ? cs.error
                          : l['level'] == 'warning'
                              ? const Color(0xFFF5A524)
                              : cs.onSurface)),
            ),
        ]),
      ),
    );
  }

  List<Widget> _section(BuildContext context, String label, Map<String, dynamic> r) {
    final cs = context.cs;
    final cmp = (r['compare'] as Map?)?.cast<String, dynamic>();
    final real = (r['real_errors'] as List? ?? const []);
    return [
      SectionHeader(label),
      if (r['fail'] != null) Text('${r['fail']}', style: TextStyle(color: cs.error)),
      if (cmp != null)
        Card(
          child: ListTile(
            leading: Icon(cmp['ok'] == true ? Icons.verified_rounded : Icons.report_problem_rounded,
                color: cmp['ok'] == true ? const Color(0xFF30A46C) : const Color(0xFFE5484D)),
            title: Text(cmp['ok'] == true ? 'Alle Tabellen identisch' : 'Abweichungen gefunden'),
            subtitle: Text('Tabellen ${cmp['tables_before']} → ${cmp['tables_after']} · '
                'Zeilen ${fmtInt(cmp['rows_before'])} → ${fmtInt(cmp['rows_after'])}'
                '${(cmp['missing'] as List?)?.isNotEmpty == true ? '\nFehlt: ${(cmp['missing'] as List).take(5).join(', ')}' : ''}'
                '${(cmp['diffs'] as List?)?.isNotEmpty == true ? '\nAbweichend: ${(cmp['diffs'] as List).take(5).map((d) => '${d['table']} ${d['before']}→${d['after']}').join(', ')}' : ''}'),
          ),
        ),
      if (real.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('${real.length} Fehler beim Einspielen:', style: TextStyle(color: cs.error)),
        for (final e in real.take(8)) Text('• $e', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      ],
    ];
  }
}
