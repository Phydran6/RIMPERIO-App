// ---------------------------------------------------------------------------
// Datei:        lib/screens/patches_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Patchmanagement unterwegs — offene Freigaben samt
//               KI-Einschätzung freigeben/ablehnen/zurückstellen, Läufe
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
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Updates'),
          bottom: const TabBar(tabs: [Tab(text: 'Freigaben'), Tab(text: 'Läufe')]),
        ),
        body: const TabBarView(children: [_Approvals(), _Runs()]),
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
