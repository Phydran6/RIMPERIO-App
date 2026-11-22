// ---------------------------------------------------------------------------
// Datei:        lib/screens/patches_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
//
// Beschreibung: Patchmanagement unterwegs — offene Freigaben samt
//               KI-Einschätzung freigeben/ablehnen/zurückstellen; alle
//               offenen Updates je Rechner und Container sehen und die
//               freigegebenen sofort installieren (ein Lauf je Rechner mit
//               Snapshot, Vorher/Nachher, Neustart und Prüfung); Läufe
//               ansehen und im Notfall zurückrollen. Entscheiden dürfen nur
//               Admins (der Server prüft das ohnehin).
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class PatchesPage extends StatelessWidget {
  final int initialTab;
  const PatchesPage({super.key, this.initialTab = 0});

  static Future<void> open(BuildContext context, {int initialTab = 0}) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PatchesPage(initialTab: initialTab)));

  @override
  Widget build(BuildContext context) {
    final installable = context.session.hasCapability('patch-installable');
    return DefaultTabController(
      length: installable ? 3 : 2,
      initialIndex: installable ? initialTab : (initialTab == 2 ? 1 : initialTab.clamp(0, 1)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Updates'),
          bottom: TabBar(tabs: [
            const Tab(text: 'Freigaben'),
            if (installable) const Tab(text: 'Installieren'),
            const Tab(text: 'Läufe'),
          ]),
        ),
        body: TabBarView(children: [const _Approvals(), if (installable) const _Install(), const _Runs()]),
      ),
    );
  }
}

class _Approvals extends StatefulWidget {
  const _Approvals();
  @override
  State<_Approvals> createState() => _ApprovalsState();
}

class _ApprovalsState extends State<_Approvals> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  final _selected = <int>{};
  bool _busy = false;

  Future<void> _decide(String decision, {int deferDays = 7}) async {
    if (_selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await context.session.api!.postJson('/api/app/patching/decide', {
        'ids': _selected.toList(),
        'decision': decision,
        'defer_days': deferDays,
      });
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final word = switch (decision) { 'approve' => 'freigegeben', 'reject' => 'abgelehnt', _ => 'zurückgestellt' };
      showInfo(context, '${r['changed'] ?? _selected.length} Updates $word.');
      _selected.clear();
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return AsyncView<List<Map<String, dynamic>>>(
      key: _key,
      load: () async =>
          ((await s.api!.getJson('/api/app/patching/approvals'))['items'] as List).cast<Map<String, dynamic>>(),
      builder: (context, items, reload) {
        _selected.retainAll(items.map((e) => e['id'] as int));
        return Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: reload,
              child: items.isEmpty
                  ? ListView(children: const [
                      EmptyState(
                          icon: Icons.verified_rounded,
                          title: 'Nichts freizugeben',
                          text: 'Alle Updates sind entschieden.'),
                    ])
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final id = it['id'] as int;
                        return _PatchTile(
                          item: it,
                          selectable: s.isAdmin,
                          selected: _selected.contains(id),
                          onSelect: (v) => setState(() => v ? _selected.add(id) : _selected.remove(id)),
                        );
                      },
                    ),
            ),
          ),
          if (s.isAdmin && items.isNotEmpty)
            SafeArea(
              top: false,
              child: Material(
                color: context.cs.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(children: [
                    TextButton(
                      onPressed: () => setState(() => _selected.length == items.length
                          ? _selected.clear()
                          : _selected.addAll(items.map((e) => e['id'] as int))),
                      child: Text(_selected.length == items.length ? 'Keine' : 'Alle'),
                    ),
                    const Spacer(),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else ...[
                      IconButton(
                        tooltip: 'Zurückstellen (7 Tage)',
                        onPressed: _selected.isEmpty ? null : () => _decide('defer'),
                        icon: const Icon(Icons.snooze_rounded),
                      ),
                      IconButton(
                        tooltip: 'Ablehnen',
                        onPressed: _selected.isEmpty ? null : () => _decide('reject'),
                        icon: const Icon(Icons.block_rounded),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: _selected.isEmpty ? null : () => _decide('approve'),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(_selected.isEmpty ? 'Freigeben' : '${_selected.length} freigeben'),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _PatchTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool> onSelect;
  const _PatchTile({required this.item, required this.selectable, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final ai = item['ai'] as Map?;
    final risk = ai?['risk'] as String?;
    final cs = context.cs;
    return ListTile(
      leading: selectable
          ? Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false))
          : const Icon(Icons.system_update_alt_rounded),
      title: Text('${item['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          Text('${item['host'] ?? ''}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          if (item['urgent'] == true) const Pill('dringend', color: Color(0xFFE5484D)),
          if (item['security'] == true) const Pill('Sicherheit', color: Color(0xFFF5A524), icon: Icons.shield),
          if (item['reboot'] == true) Pill('Neustart', color: cs.outline, icon: Icons.restart_alt),
          if (risk != null) Pill('KI: ${_riskLabel(risk)}', color: _riskColor(risk)),
        ]),
      ),
      onTap: () => _showDetail(context),
      onLongPress: selectable ? () => onSelect(!selected) : null,
    );
  }

  void _showDetail(BuildContext context) {
    final ai = item['ai'] as Map?;
    final adv = (item['advisories'] as List?)?.cast<Map>() ?? const [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
          Text('${item['title']}', style: ctx.tt.titleLarge),
          const SizedBox(height: 8),
          Text([
            item['host'],
            if (item['kb'] != null) item['kb'],
            if (item['from'] != null || item['to'] != null) '${item['from'] ?? '?'} → ${item['to'] ?? '?'}',
            item['platform'],
          ].whereType<Object>().join(' · '), style: TextStyle(color: ctx.cs.onSurfaceVariant)),
          if (item['reason'] != null) ...[
            const SizedBox(height: 12),
            Text('${item['reason']}'),
          ],
          if (ai != null) ...[
            const SectionHeader('KI-Einschätzung'),
            if (ai['risk'] != null)
              Row(children: [
                Pill('Risiko: ${_riskLabel(ai['risk'] as String)}', color: _riskColor(ai['risk'] as String)),
                const SizedBox(width: 8),
                if (ai['recommendation'] != null) Pill('${ai['recommendation']}', color: ctx.cs.primary),
              ]),
            if (ai['summary'] != null) ...[const SizedBox(height: 10), Text('${ai['summary']}')],
            for (final k in (ai['known_issues'] as List? ?? const []))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  '),
                  Expanded(child: Text('$k')),
                ]),
              ),
            if (ai['error'] != null)
              Text('${ai['error']}', style: TextStyle(color: ctx.cs.error)),
          ],
          if (adv.isNotEmpty) ...[
            const SectionHeader('Hinweise'),
            for (final a in adv)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.article_outlined),
                title: Text('${a['title']}'),
                subtitle: Text('${a['source'] ?? ''}'),
                onLongPress: a['link'] == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: '${a['link']}'));
                        showInfo(ctx, 'Link kopiert.');
                      },
              ),
          ],
        ]),
      ),
    );
  }

  static String _riskLabel(String r) =>
      switch (r) { 'low' => 'gering', 'medium' => 'mittel', 'high' => 'hoch', _ => r };
  static Color _riskColor(String r) => switch (r) {
        'low' => const Color(0xFF30A46C),
        'medium' => const Color(0xFFF5A524),
        'high' => const Color(0xFFE5484D),
        _ => RimTheme.gold,
      };
}

class _Runs extends StatelessWidget {
  const _Runs();

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
    return AsyncView<List<Map<String, dynamic>>>(
      key: key,
      load: () async =>
          ((await s.api!.getJson('/api/app/patching/runs'))['items'] as List).cast<Map<String, dynamic>>(),
      builder: (context, items, reload) => RefreshIndicator(
        onRefresh: reload,
        child: items.isEmpty
            ? ListView(children: const [EmptyState(icon: Icons.history_rounded, title: 'Noch keine Läufe')])
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                itemBuilder: (context, i) {
                  final r = items[i];
                  final status = r['status'] as String? ?? '';
                  return ListTile(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => _RunDetailPage(id: r['id'] as int))),
                    leading: _RunIcon(status),
                    title: Text('${r['host']} · ${r['items']} Updates'),
                    subtitle: Text([
                      _statusLabel(status),
                      relativeTime((r['finished_at'] ?? r['started_at']) as String?),
                      if (r['last'] != null) r['last'],
                    ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: s.isAdmin && r['can_rollback'] == true
                        ? IconButton(
                            tooltip: 'Zurückrollen',
                            icon: const Icon(Icons.settings_backup_restore_rounded),
                            onPressed: () => _rollback(context, r, reload),
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }

  Future<void> _rollback(BuildContext context, Map<String, dynamic> r, Future<void> Function() reload) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zurückrollen?'),
        content: Text('${r['host']} wird auf den Snapshot „${r['snapshot']}“ zurückgesetzt. '
            'Alles seit dem Lauf geht auf dieser Maschine verloren.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D), minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zurückrollen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.session.api!.postJson('/api/app/patching/runs/${r['id']}/rollback', const {});
      if (context.mounted) showInfo(context, 'Rücksprung gestartet.');
      await reload();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static String _statusLabel(String s) => switch (s) {
        'succeeded' => 'erfolgreich',
        'failed' => 'fehlgeschlagen',
        'pending' => 'wartet',
        'snapshotting' => 'Snapshot',
        'baseline' || 'installing' => 'installiert',
        'rebooting' => 'startet neu',
        'settling' || 'verifying' => 'prüft',
        'rolling_back' => 'rollt zurück',
        'rolled_back' => 'zurückgerollt',
        _ => s,
      };
}

class _RunIcon extends StatelessWidget {
  final String status;
  const _RunIcon(this.status);
  @override
  Widget build(BuildContext context) {
    final (IconData i, Color c) = switch (status) {
      'succeeded' => (Icons.check_circle_rounded, const Color(0xFF30A46C)),
      'failed' => (Icons.cancel_rounded, const Color(0xFFE5484D)),
      'rolled_back' => (Icons.settings_backup_restore_rounded, const Color(0xFFF5A524)),
      _ => (Icons.autorenew_rounded, context.cs.primary),
    };
    return Icon(i, color: c, size: 32);
  }
}


// ---------------------------------------------------------------------------
// Installieren: alles Offene je Rechner, freigegebene sofort einspielen
// ---------------------------------------------------------------------------
class _Install extends StatefulWidget {
  const _Install();
  @override
  State<_Install> createState() => _InstallState();
}

class _InstallState extends State<_Install> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _busy = false;

  Future<void> _installHost(Map<String, dynamic> h, {List<int>? only}) async {
    final s = context.session;
    final items = (h['items'] as List).cast<Map<String, dynamic>>();
    final ids = only ?? items.where((i) => i['installable'] == true).map((i) => i['id'] as int).toList();
    if (ids.isEmpty) return;
    final dbItems = items.where((i) => ids.contains(i['id']) && i['db'] == true).length;
    final ok = await confirmDialog(
      context,
      '${h['host']}: ${ids.length} Update(s) installieren?',
      [
        'Ein Lauf mit allem, was dazugehört: ${h['snapshot_possible'] == true ? 'Proxmox-Snapshot, ' : ''}'
            'Zustand vorher, Installation, Neustart falls nötig, Prüfung danach.',
        if (dbItems > 0) '$dbItems Datenbank-Container laufen als DB-Update mit Sicherung und Probelauf.',
        if (h['online'] != true) 'Achtung: der Rechner ist gerade offline – der Lauf startet, sobald er sich meldet.',
      ].join('\n\n'),
      action: 'Installieren',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await s.api!.postJson('/api/app/patching/install', {'agent_uid': h['agent_uid'], 'item_ids': ids});
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showInfo(context, r['id'] == null ? '${r['message'] ?? 'DB-Update gestartet.'}' : 'Lauf #${r['id']} gestartet.');
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installAll(Map<String, dynamic> d) async {
    final n = (d['totals'] as Map)['installable'] ?? 0;
    final ok = await confirmDialog(context, 'Alle freigegebenen Updates installieren?',
        '$n Update(s) auf allen Rechnern – je Rechner ein Lauf mit Snapshot, Prüfung und Rückweg.',
        action: 'Alle installieren');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await context.session.api!.postJson('/api/app/patching/install-all', const {});
      if (!mounted) return;
      final started = (r['started'] as List).length;
      final skipped = (r['skipped'] as List).cast<Map>();
      showInfo(context,
          '$started Lauf/Läufe gestartet${skipped.isEmpty ? '' : ' · ${skipped.length} übersprungen (${skipped.first['reason']})'}');
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan([String? uid]) async {
    try {
      final r = await context.session.api!.postJson('/api/app/patching/scan', {'agent_uid': uid});
      if (mounted) showInfo(context, '${r['queued']} Suche(n) eingereiht – Ergebnisse in ein paar Minuten.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return AsyncView<Map<String, dynamic>>(
      key: _key,
      load: () => s.api!.getJson('/api/app/patching/open'),
      builder: (context, d, reload) {
        final hosts = (d['hosts'] as List).cast<Map<String, dynamic>>();
        final totals = (d['totals'] as Map).cast<String, dynamic>();
        final cs = context.cs;
        return Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                      '${fmtInt(totals['installable'])} installierbar · ${fmtInt(totals['needs_approval'])} brauchen eine Freigabe'
                      '${(totals['reviewing'] ?? 0) > 0 ? ' · ${totals['reviewing']} in KI-Prüfung' : ''}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                if (hosts.isEmpty)
                  const EmptyState(
                      icon: Icons.verified_rounded, title: 'Alles aktuell', text: 'Keine offenen Updates auf den Rechnern.'),
                for (final h in hosts) _hostCard(context, h),
              ]),
            ),
          ),
          if (s.isAdmin)
            SafeArea(
              top: false,
              child: Material(
                color: cs.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(children: [
                    TextButton.icon(onPressed: _busy ? null : () => _scan(), icon: const Icon(Icons.refresh), label: const Text('Suchen')),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: _busy || (totals['installable'] ?? 0) == 0 ? null : () => _installAll(d),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: Text('Alle installieren (${totals['installable']})'),
                    ),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Widget _hostCard(BuildContext context, Map<String, dynamic> h) {
    final s = context.session;
    final cs = context.cs;
    final items = (h['items'] as List).cast<Map<String, dynamic>>();
    final run = h['active_run'] as Map?;
    final installable = (h['installable'] as int?) ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: installable > 0 && items.length <= 8,
          leading: Icon(
              (h['platform'] ?? '') == 'windows' ? Icons.computer_rounded : Icons.dns_rounded,
              color: h['online'] == true ? const Color(0xFF30A46C) : cs.outline),
          title: Text('${h['host']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text([
            '${items.length} offen',
            if (installable > 0) '$installable installierbar',
            if (run != null) 'Lauf #${run['id']} läuft',
            if (h['online'] != true) 'offline',
          ].join(' · ')),
          children: [
            for (final it in items)
              ListTile(
                dense: true,
                leading: Icon(it['kind'] == 'docker' ? Icons.view_in_ar_rounded : Icons.system_update_alt_rounded, size: 20),
                title: Text('${it['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Wrap(spacing: 6, runSpacing: 4, children: [
                  Pill('${it['status_label']}', color: _statusColor(it['status'] as String?, cs)),
                  if (it['security'] == true) const Pill('Sicherheit', color: Color(0xFFF5A524), icon: Icons.shield),
                  if (it['urgent'] == true) const Pill('dringend', color: Color(0xFFE5484D)),
                  if (it['db'] == true) Pill('DB mit Probelauf', color: cs.tertiary),
                  if (it['reboot'] == true) Pill('Neustart', color: cs.outline),
                  if (it['to'] != null) Text('→ ${it['to']}', style: TextStyle(color: cs.outline, fontSize: 12)),
                ]),
                trailing: s.isAdmin && it['installable'] == true && run == null && it['kind'] == 'docker'
                    ? IconButton(
                        tooltip: 'Nur diesen Container',
                        icon: const Icon(Icons.play_circle_outline_rounded),
                        onPressed: _busy ? null : () => _installHost(h, only: [it['id'] as int]))
                    : null,
              ),
            if (s.isAdmin)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(children: [
                  TextButton(onPressed: () => _scan(h['agent_uid'] as String?), child: const Text('Jetzt suchen')),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: _busy || installable == 0 || run != null ? null : () => _installHost(h),
                    child: Text(run != null ? 'Lauf läuft' : 'Installieren ($installable)'),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  static Color _statusColor(String? s, ColorScheme cs) => switch (s) {
        'needs_approval' => RimTheme.gold,
        'approved' || 'auto' => const Color(0xFF30A46C),
        'failed' => const Color(0xFFE5484D),
        'installing' => cs.primary,
        _ => cs.outline,
      };
}

class _RunDetailPage extends StatelessWidget {
  final int id;
  const _RunDetailPage({required this.id});

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return Scaffold(
      appBar: AppBar(title: Text('Lauf #$id')),
      body: AsyncView<Map<String, dynamic>>(
        load: () => api.getJson('/api/app/patching/runs/$id'),
        builder: (context, r, reload) {
          final cs = context.cs;
          final log = (r['log'] as List? ?? const []).cast<Map>();
          final items = (r['item_list'] as List? ?? const []).cast<Map>();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: ListTile(
                  leading: _RunIcon('${r['status']}'),
                  title: Text('${r['hostname']}'),
                  subtitle: Text('${_Runs._statusLabel('${r['status']}')} · ${r['trigger']} · ${r['created_by']}'),
                ),
              ),
              if (r['error'] != null) ...[
                const SizedBox(height: 8),
                Text('${r['error']}', style: TextStyle(color: cs.error)),
              ],
              const SectionHeader('Updates'),
              for (final i in items)
                ListTile(
                  dense: true,
                  title: Text('${i['title']}'),
                  subtitle: Text('${i['status_label']}${i['error'] != null ? ' · ${i['error']}' : ''}'),
                ),
              const SectionHeader('Verlauf'),
              for (final l in log)
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
          );
        },
      ),
    );
  }
}
