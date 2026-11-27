// ---------------------------------------------------------------------------
// Datei:        lib/screens/backups_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.26.22.00.00
//
// Beschreibung: Backup-Bereich — Aufträge (was, wohin, wann, letzter Lauf,
//               überfällig), „Jetzt sichern“, Verlauf mit Ort, Größe und
//               Protokoll, Probe-Wiederherstellung („Prüfen“).
//               Quelle: /api/backups. Anlegen geht in der Weboberfläche.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'nas_page.dart' show fmtBytes;

Color _runColor(String? s, ColorScheme cs) => switch (s) {
      'done' => const Color(0xFF30A46C),
      'error' => const Color(0xFFE5484D),
      'running' || 'waiting' => cs.primary,
      _ => cs.outline,
    };

String _runText(String? s) => switch (s) {
      'done' => 'ok',
      'error' => 'Fehler',
      'running' => 'läuft',
      'waiting' => 'wartet auf Rechner',
      'deleted' => 'entfernt',
      _ => s ?? '–',
    };

class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key});
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupsPage()));
  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final api = context.session.api!;
    final ov = await api.getJson('/api/backups/overview');
    final jobs = ((await api.getRaw('/api/backups/jobs')) as List).cast<Map<String, dynamic>>();
    _timer?.cancel();
    if (jobs.any((j) => j['running'] == true || ['running', 'waiting'].contains((j['last_run'] as Map?)?['status']))) {
      _timer = Timer(const Duration(seconds: 5), () => _key.currentState?.reload());
    }
    return {'overview': ov, 'jobs': jobs};
  }

  Future<void> _run(Map<String, dynamic> j) async {
    final ok = await confirmDialog(context, '„${j['name']}“ jetzt sichern?', '${j['source_label'] ?? ''}', action: 'Sichern');
    if (!ok || !mounted) return;
    try {
      await context.session.api!.postJson('/api/backups/jobs/${j['id']}/run', {});
      if (mounted) showInfo(context, 'Gestartet.');
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.session.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup'), actions: [
        IconButton(
          tooltip: 'Verlauf',
          icon: const Icon(Icons.history_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupRunsPage())),
        ),
      ]),
      body: AsyncView<Map<String, dynamic>>(
        key: _key,
        load: _load,
        builder: (context, d, reload) {
          final cs = context.cs;
          final ov = d['overview'] as Map<String, dynamic>;
          final jobs = (d['jobs'] as List).cast<Map<String, dynamic>>();
          final key = ov['key'] as Map?;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                  children: [
                    StatTile(icon: Icons.backup_outlined, label: 'Aufträge', value: '${ov['jobs'] ?? 0}'),
                    StatTile(
                        icon: Icons.error_outline,
                        label: 'Fehlgeschlagen',
                        value: '${ov['failed'] ?? 0}',
                        color: (ov['failed'] ?? 0) as int > 0 ? const Color(0xFFE5484D) : cs.outline),
                    StatTile(
                        icon: Icons.schedule_rounded,
                        label: 'Überfällig',
                        value: '${ov['overdue'] ?? 0}',
                        color: (ov['overdue'] ?? 0) as int > 0 ? RimTheme.gold : cs.outline),
                    StatTile(icon: Icons.storage_rounded, label: 'Belegt', value: fmtBytes(ov['stored_bytes'])),
                  ],
                ),
              ),
              if (key != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                      'Verschlüsselt mit „${key['name']}“ – liegt ${key['backend'] == 'vaultwarden' ? 'in Vaultwarden' : 'lokal verschlüsselt'}.',
                      style: TextStyle(color: cs.outline, fontSize: 12)),
                ),
              const SectionHeader('Aufträge'),
              if (jobs.isEmpty)
                const EmptyState(
                    icon: Icons.backup_outlined,
                    title: 'Noch keine Aufträge',
                    text: 'Anlegen in der Weboberfläche: Backup → Aufträge.'),
              for (final j in jobs)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Card(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ListTile(
                        title: Text('${j['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${j['kind_label']}\n${j['source_label'] ?? ''}'),
                        isThreeLine: true,
                        trailing: admin
                            ? IconButton.filledTonal(
                                tooltip: 'Jetzt sichern',
                                icon: j['running'] == true
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.play_arrow_rounded),
                                onPressed: j['running'] == true ? null : () => _run(j),
                              )
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [
                          if ((j['target'] as Map?) != null) Pill('→ ${(j['target'] as Map)['name']}', color: cs.primary),
                          if (j['encrypt'] == true) const Pill('verschlüsselt', color: Color(0xFF30A46C), icon: Icons.lock_outline),
                          if (j['overdue'] == true) const Pill('überfällig', color: RimTheme.gold),
                          if (j['last_run'] != null)
                            Pill(
                                '${_runText((j['last_run'] as Map)['status'] as String?)} · ${relativeTime((j['last_run'] as Map)['started_at'] as String?)}',
                                color: _runColor((j['last_run'] as Map)['status'] as String?, cs))
                          else
                            Pill('noch nie', color: cs.outline),
                          if (j['next_run_at'] != null) Pill('nächster ${_when(j['next_run_at'] as String?)}', color: cs.outline),
                        ]),
                      ),
                      if ((j['last_run'] as Map?)?['error'] != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text('${(j['last_run'] as Map)['error']}',
                              style: const TextStyle(color: Color(0xFFE5484D), fontSize: 12)),
                        ),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  static String _when(String? iso) {
    final t = parseServerTime(iso);
    if (t == null) return '–';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
  }
}

class BackupRunsPage extends StatefulWidget {
  const BackupRunsPage({super.key});
  @override
  State<BackupRunsPage> createState() => _BackupRunsPageState();
}

class _BackupRunsPageState extends State<BackupRunsPage> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<void> _verify(Map<String, dynamic> r) async {
    showInfo(context, 'Prüfe – Datei wird geholt und entschlüsselt …');
    try {
      final res = await context.session.api!.postJson('/api/backups/runs/${r['id']}/verify', {});
      if (!mounted) return;
      if (res['ok'] == true) {
        showInfo(context, 'In Ordnung: ${res['name']} lässt sich vollständig zurückholen.');
      } else {
        showError(context, '${res['message']}');
      }
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.session.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup-Verlauf')),
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _key,
        load: () async => ((await context.session.api!.getRaw('/api/backups/runs', {'limit': 100})) as List)
            .cast<Map<String, dynamic>>(),
        builder: (context, runs, reload) {
          final cs = context.cs;
          return RefreshIndicator(
            onRefresh: reload,
            child: runs.isEmpty
                ? ListView(children: const [EmptyState(icon: Icons.history_rounded, title: 'Noch keine Läufe')])
                : ListView.builder(
                    itemCount: runs.length,
                    itemBuilder: (context, i) {
                      final r = runs[i];
                      final canVerify = admin && r['status'] == 'done' && (r['file_name'] ?? '') != '' &&
                          (r['detail'] as Map?)?['target_id'] != null;
                      return ExpansionTile(
                        leading: Icon(
                            r['status'] == 'done'
                                ? Icons.check_circle_outline
                                : r['status'] == 'error'
                                    ? Icons.error_outline
                                    : Icons.hourglass_top_rounded,
                            color: _runColor(r['status'] as String?, cs)),
                        title: Text('${r['job_name']}'),
                        subtitle: Text(
                            '${relativeTime(r['started_at'] as String?)} · ${_runText(r['status'] as String?)} · ${fmtBytes(r['size_bytes'])}'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if ((r['location'] ?? '') != '')
                                SelectableText('${r['location']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                              if (r['error'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text('${r['error']}', style: const TextStyle(color: Color(0xFFE5484D))),
                                ),
                              const SizedBox(height: 6),
                              Text(((r['log'] as List?) ?? const []).map((l) => '${(l as Map)['text']}').join('\n'),
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                              if (canVerify)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: OutlinedButton.icon(
                                    onPressed: () => _verify(r),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: const Text('Prüfen (Probe-Wiederherstellung)'),
                                  ),
                                ),
                            ]),
                          ),
                        ],
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
