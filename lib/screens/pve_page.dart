// ---------------------------------------------------------------------------
// Datei:        lib/screens/pve_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.24.21.00.00
//
// Beschreibung: Proxmox in der App — Updates der Knoten selbst (Liste,
//               Paketlisten auffrischen, Upgrade mit Live-Ausgabe, Neustart),
//               rollierender Patch-Lauf über alle Knoten („Alle Knoten
//               patchen“) samt Zeitplan im Wartungsfenster und Verlauf,
//               Shell des Knotens, Konsole der Container/VMs und den
//               RIMPERIO-Agent per pct exec in einen Container bringen.
//               Quellen: /api/pve/*, /api/patching/pve/hosts.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'console_page.dart';

class PvePage extends StatelessWidget {
  const PvePage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PvePage()));

  @override
  Widget build(BuildContext context) {
    final patching = context.session.hasCapability('pve-patching');
    return DefaultTabController(
      length: patching ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Proxmox'),
          bottom: TabBar(isScrollable: patching, tabs: [
            const Tab(text: 'Knoten & Updates'),
            if (patching) const Tab(text: 'Patch-Lauf'),
            const Tab(text: 'Gäste'),
          ]),
        ),
        body: TabBarView(children: [const _Nodes(), if (patching) const _Patching(), const _Guests()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rollierend patchen: Knoten für Knoten, von Hand oder im Wartungsfenster.
// ---------------------------------------------------------------------------
const _rebootLabels = {'never': 'nie', 'kernel': 'bei neuem Kernel', 'always': 'immer'};
const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _runStatus(String? s) => switch (s) {
      'running' => 'läuft',
      'pending' => 'wartet',
      'done' => 'aktualisiert',
      'current' => 'aktuell',
      'succeeded' => 'erfolgreich',
      'failed' => 'fehlgeschlagen',
      'cancelled' => 'abgebrochen',
      'skipped' => 'übersprungen',
      _ => s ?? '',
    };

Color _runColor(BuildContext context, String? s) => switch (s) {
      'succeeded' => const Color(0xFF30A46C),
      'failed' => const Color(0xFFE5484D),
      'running' => context.cs.primary,
      _ => context.cs.outline,
    };

class _Patching extends StatefulWidget {
  const _Patching();
  @override
  State<_Patching> createState() => _PatchingState();
}

class _PatchingState extends State<_Patching> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Solange ein Lauf aktiv ist, alle 5 s nachsehen.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_running) _key.currentState?.reload();
    });
  }

  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _patchAll(Map h) async {
    final cfg = ((h['config'] as Map?) ?? const {}).cast<String, dynamic>();
    var reboot = '${cfg['reboot'] ?? 'kernel'}';
    var refresh = cfg['refresh'] != false;
    var onlySecurity = cfg['only_security'] == true;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Alle Knoten von ${h['host']} patchen', style: ctx.tt.titleMedium),
              const SizedBox(height: 6),
              Text('Knoten für Knoten: apt update, pveupgrade, bei Bedarf Neustart und warten, bis er wieder da ist. '
                  'Beim ersten Fehler hört der Lauf auf.',
                  style: TextStyle(color: ctx.cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              const Text('Neustart danach'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  for (final e in _rebootLabels.entries) ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {reboot},
                onSelectionChanged: (v) => set(() => reboot = v.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vorher Paketlisten auffrischen'),
                value: refresh,
                onChanged: (v) => set(() => refresh = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Nur wenn Sicherheitsupdates dabei sind'),
                value: onlySecurity,
                onChanged: (v) => set(() => onlySecurity = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: const Text('Weiter'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    final ok = await confirmWord(context, 'Alle Knoten patchen?',
        'Startet den Patch-Lauf auf ${h['host']} jetzt. Neustart: ${_rebootLabels[reboot]}.', 'UPGRADE');
    if (!ok || !mounted) return;
    try {
      final run = await context.session.api!.postJson('/api/pve/hosts/${h['host_id']}/patch', {
        'confirm': 'UPGRADE',
        'reboot': reboot,
        'refresh': refresh,
        'only_security': onlySecurity,
      });
      if (!mounted) return;
      showInfo(context, 'Patch-Lauf gestartet.');
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PatchRunPage(id: '${run['id']}')));
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editSchedule(Map h) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _ScheduleEditPage(hostId: h['host_id'] as int, host: '${h['host']}',
            config: ((h['config'] as Map?) ?? const {}).cast<String, dynamic>())));
    if (saved == true) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return AsyncView<Map<String, dynamic>>(
      key: _key,
      load: () => s.api!.getJson('/api/pve/patching'),
      builder: (context, d, reload) {
        final cs = context.cs;
        final hosts = ((d['hosts'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final runs = ((d['runs'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final history = ((d['history'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final seen = runs.map((r) => r['id']).toSet();
        final all = [...runs, ...history.where((r) => !seen.contains(r['id']))];
        _running = hosts.any((h) => h['running'] != null);
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            if (hosts.isEmpty)
              const EmptyState(
                  icon: Icons.dns_outlined, title: 'Kein Proxmox verbunden', text: 'Einrichten in der Weboberfläche unter Geräte → Proxmox VE.'),
            for (final h in hosts)
              Builder(builder: (context) {
                final cfg = ((h['config'] as Map?) ?? const {}).cast<String, dynamic>();
                final running = (h['running'] as Map?)?.cast<String, dynamic>();
                final days = ((cfg['days'] as List?) ?? const []).map((e) => e as int).toList();
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.hub_rounded),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${h['host']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (h['window_open'] == true) const Pill('Fenster offen', color: Color(0xFFF5A524)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        cfg['enabled'] == true
                            ? 'Zeitplan an: ${days.map((i) => _dayLabels[i.clamp(0, 6)]).join(', ')} ab ${cfg['start']} '
                                '(${cfg['duration_minutes']} min) · Neustart ${_rebootLabels[cfg['reboot']] ?? cfg['reboot']}'
                            : 'Zeitplan aus – nur von Hand',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      if (cfg['enabled'] == true && h['next_window'] != null)
                        Text('Nächstes Fenster: ${fullTime(h['next_window'] as String?)}',
                            style: TextStyle(color: cs.outline, fontSize: 12)),
                      if (running != null) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          title: const Text('Patch-Lauf läuft'),
                          subtitle: Text(((running['nodes'] as List?) ?? const [])
                              .cast<Map>()
                              .map((n) => '${n['node']}: ${_runStatus('${n['status']}')}')
                              .join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => _PatchRunPage(id: '${running['id']}'))),
                        ),
                      ],
                      if (s.isAdmin) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: () => _editSchedule(h),
                            icon: const Icon(Icons.schedule_rounded, size: 18),
                            label: const Text('Zeitplan'),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: running != null ? null : () => _patchAll(h),
                            icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                            label: const Text('Alle Knoten patchen'),
                          ),
                        ]),
                      ],
                    ]),
                  ),
                );
              }),
            if (all.isNotEmpty) ...[
              const SectionHeader('Verlauf'),
              for (final r in all.take(30))
                ListTile(
                  leading: Icon(
                      r['status'] == 'succeeded'
                          ? Icons.check_circle_rounded
                          : r['status'] == 'failed'
                              ? Icons.cancel_rounded
                              : Icons.autorenew_rounded,
                      color: _runColor(context, r['status'] as String?)),
                  title: Text('${r['host']} · ${_runStatus(r['status'] as String?)}'),
                  subtitle: Text('${relativeTime(r['started_at'] as String?)} · '
                      '${r['trigger'] == 'schedule' ? 'Zeitplan' : (r['user'] ?? 'von Hand')}'
                      '${r['error'] != null ? '\n${r['error']}' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PatchRunPage(id: '${r['id']}'))),
                ),
            ],
          ]),
        );
      },
    );
  }
}

class _ScheduleEditPage extends StatefulWidget {
  final int hostId;
  final String host;
  final Map<String, dynamic> config;
  const _ScheduleEditPage({required this.hostId, required this.host, required this.config});
  @override
  State<_ScheduleEditPage> createState() => _ScheduleEditPageState();
}

class _ScheduleEditPageState extends State<_ScheduleEditPage> {
  late bool _enabled = widget.config['enabled'] == true;
  late final Set<int> _days = {...((widget.config['days'] as List?) ?? const [5]).map((e) => e as int)};
  late String _start = '${widget.config['start'] ?? '03:00'}';
  late int _duration = (widget.config['duration_minutes'] as int?) ?? 240;
  late String _reboot = '${widget.config['reboot'] ?? 'kernel'}';
  late bool _refresh = widget.config['refresh'] != false;
  late bool _onlySecurity = widget.config['only_security'] == true;
  bool _busy = false;

  Future<void> _pickTime() async {
    final parts = _start.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 3, minute: int.tryParse(parts.last) ?? 0),
    );
    if (t != null) {
      setState(() => _start = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (_enabled && _days.isEmpty) {
      showError(context, 'Für den Zeitplan mindestens einen Wochentag wählen.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.session.api!.putJson('/api/pve/patching/hosts/${widget.hostId}', {
        ...widget.config,
        'enabled': _enabled,
        'days': (_days.toList()..sort()),
        'start': _start,
        'duration_minutes': _duration,
        'reboot': _reboot,
        'refresh': _refresh,
        'only_security': _onlySecurity,
      });
      if (!mounted) return;
      showInfo(context, _enabled ? 'Zeitplan gespeichert.' : 'Zeitplan ausgeschaltet.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Zeitplan ${widget.host}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Automatisch im Wartungsfenster patchen'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SectionHeader('Wochentage'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < 7; i++)
            FilterChip(
              label: Text(_dayLabels[i]),
              selected: _days.contains(i),
              onSelected: (v) => setState(() => v ? _days.add(i) : _days.remove(i)),
            ),
        ]),
        const SectionHeader('Fenster'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_rounded),
          title: const Text('Beginn'),
          trailing: Text(_start, style: context.tt.titleMedium),
          onTap: _pickTime,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timelapse_rounded),
          title: const Text('Dauer'),
          trailing: DropdownButton<int>(
            value: const [60, 120, 180, 240, 360, 480].contains(_duration) ? _duration : 240,
            items: [
              for (final m in const [60, 120, 180, 240, 360, 480])
                DropdownMenuItem(value: m, child: Text('${m ~/ 60} h')),
            ],
            onChanged: (v) => setState(() => _duration = v ?? 240),
          ),
        ),
        const SectionHeader('Ablauf'),
        const Text('Neustart nach dem Upgrade'),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: [for (final e in _rebootLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {_reboot},
          onSelectionChanged: (v) => setState(() => _reboot = v.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vorher Paketlisten auffrischen'),
          value: _refresh,
          onChanged: (v) => setState(() => _refresh = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Nur wenn Sicherheitsupdates dabei sind'),
          value: _onlySecurity,
          onChanged: (v) => setState(() => _onlySecurity = v),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded),
          label: const Text('Speichern'),
        ),
      ]),
    );
  }
}

class _PatchRunPage extends StatefulWidget {
  final String id;
  const _PatchRunPage({required this.id});
  @override
  State<_PatchRunPage> createState() => _PatchRunPageState();
}

class _PatchRunPageState extends State<_PatchRunPage> {
  Map<String, dynamic>? _run;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_run == null || _run!['status'] == 'running') _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.session.api!.getJson('/api/pve/patching/runs/${widget.id}');
      if (mounted) setState(() => _run = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _run;
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: Text(r == null ? 'Patch-Lauf' : '${r['host']}: ${_runStatus(r['status'] as String?)}')),
      body: r == null
          ? (_error != null ? ErrorState(error: _error, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : ListView(padding: const EdgeInsets.all(12), children: [
              if (r['error'] != null)
                Card(
                  color: const Color(0xFF5A1E1E),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('${r['error']}', style: const TextStyle(color: Colors.white)),
                  ),
                ),
              const SectionHeader('Knoten'),
              for (final n in ((r['nodes'] as List?) ?? const []).cast<Map<String, dynamic>>())
                ListTile(
                  leading: Icon(
                      switch (n['status']) {
                        'succeeded' || 'current' || 'done' => Icons.check_circle_rounded,
                        'failed' => Icons.cancel_rounded,
                        'running' => Icons.autorenew_rounded,
                        'skipped' => Icons.skip_next_rounded,
                        _ => Icons.hourglass_empty_rounded,
                      },
                      color: _runColor(context,
                          const ['current', 'done'].contains(n['status']) ? 'succeeded' : n['status'] as String?)),
                  title: Text('${n['node']}'),
                  subtitle: Text([
                    _runStatus(n['status'] as String?),
                    if ((n['count'] ?? 0) > 0) '${n['count']} Pakete',
                    if (n['rebooted'] == true) 'neu gestartet',
                    if (n['note'] != null) '${n['note']}',
                  ].join(' · ')),
                  trailing: n['job'] != null ? const Icon(Icons.chevron_right) : null,
                  onTap: n['job'] == null
                      ? null
                      : () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => _JobPage(id: '${n['job']}'))),
                ),
              const SectionHeader('Protokoll'),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF0B0F17), borderRadius: BorderRadius.circular(8)),
                child: SelectableText(
                  ((r['log'] as List?) ?? const [])
                      .cast<Map>()
                      .map((l) => '${clockTime(l['ts'] as String?)}  ${l['text']}')
                      .join('\n'),
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 12, color: r['status'] == 'failed' ? const Color(0xFFFFB4B4) : const Color(0xFFE5E7EB)),
                ),
              ),
              const SizedBox(height: 8),
              Text('Gestartet ${fullTime(r['started_at'] as String?)} · ${r['user'] ?? ''}',
                  style: TextStyle(color: cs.outline, fontSize: 12)),
            ]),
    );
  }
}

class _Nodes extends StatefulWidget {
  const _Nodes();
  @override
  State<_Nodes> createState() => _NodesState();
}

class _NodesState extends State<_Nodes> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _force = false;

  Future<void> _upgrade(Map h, Map n) async {
    final ok = await confirmWord(
        context,
        '${n['node']} aktualisieren?',
        '${n['count']} Paket(e) installieren (pveupgrade). Laufende VMs bleiben an.'
            '${n['kernel_update'] == true ? '\n\nEin neuer Kernel ist dabei – danach neu starten.' : ''}',
        'UPGRADE');
    if (!ok || !mounted) return;
    try {
      final j = await context.session.api!
          .postJson('/api/pve/hosts/${h['host_id']}/nodes/${n['node']}/upgrade', {'confirm': 'UPGRADE'});
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _JobPage(id: j['id'] as String)));
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _refresh(Map h, Map n) async {
    try {
      final r = await context.session.api!.postJson('/api/pve/hosts/${h['host_id']}/nodes/${n['node']}/updates/refresh', const {});
      if (mounted) showInfo(context, '${r['message']}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reboot(Map h, Map n) async {
    final ok = await confirmWord(context, '${n['node']} neu starten?',
        'Gäste werden je nach ihrer Einstellung heruntergefahren bzw. migriert.', 'REBOOT');
    if (!ok || !mounted) return;
    try {
      await context.session.api!.postJson('/api/pve/hosts/${h['host_id']}/nodes/${n['node']}/reboot', {'confirm': 'REBOOT'});
      if (mounted) showInfo(context, 'Neustart angestoßen.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return AsyncView<Map<String, dynamic>>(
      key: _key,
      load: () async {
        final d = await s.api!.getJson('/api/pve/updates', {'force': _force ? true : null});
        _force = false;
        return d;
      },
      builder: (context, d, reload) {
        final hosts = (d['hosts'] as List).cast<Map<String, dynamic>>();
        final jobs = (d['jobs'] as List).cast<Map<String, dynamic>>();
        final cs = context.cs;
        return RefreshIndicator(
          onRefresh: () {
            _force = true;
            return reload();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            if (hosts.isEmpty)
              const EmptyState(
                  icon: Icons.dns_outlined, title: 'Kein Proxmox verbunden', text: 'Einrichten in der Weboberfläche unter Integrationen.'),
            for (final h in hosts) ...[
              SectionHeader('${h['host']}'),
              if (h['error'] != null) Text('${h['error']}', style: TextStyle(color: cs.error)),
              for (final n in (h['nodes'] as List).cast<Map<String, dynamic>>())
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.dns_rounded, color: n['online'] == true ? const Color(0xFF30A46C) : cs.outline),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${n['node']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (n['online'] == true && n['error'] == null)
                          Pill((n['count'] ?? 0) > 0 ? '${n['count']} Updates' : 'aktuell',
                              color: (n['count'] ?? 0) > 0 ? const Color(0xFFF5A524) : const Color(0xFF30A46C)),
                      ]),
                      if (n['error'] != null) Text('${n['error']}', style: TextStyle(color: cs.error, fontSize: 12)),
                      if (n['kernel_update'] == true)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Pill('neuer Kernel – Neustart nötig', color: Color(0xFFF5A524)),
                        ),
                      if ((n['items'] as List?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        for (final p in (n['items'] as List).take(6).cast<Map>())
                          Text('• ${p['package']}  ${p['from']} → ${p['to']}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        if ((n['items'] as List).length > 6)
                          Text('… und ${(n['items'] as List).length - 6} weitere', style: TextStyle(fontSize: 12, color: cs.outline)),
                      ],
                      if (s.isAdmin && n['online'] == true)
                        Wrap(spacing: 4, children: [
                          TextButton(onPressed: () => _refresh(h, n), child: const Text('Auffrischen')),
                          TextButton(
                              onPressed: () => PveConsolePage.open(context,
                                  hostId: h['host_id'] as int, node: '${n['node']}', kind: 'node', title: 'Shell ${n['node']}'),
                              child: const Text('Shell')),
                          TextButton(onPressed: () => _reboot(h, n), child: const Text('Neustart')),
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: (n['count'] ?? 0) > 0 ? () => _upgrade(h, n) : null,
                            child: const Text('Aktualisieren'),
                          ),
                        ]),
                    ]),
                  ),
                ),
            ],
            if (jobs.isNotEmpty) ...[
              const SectionHeader('Upgrades'),
              for (final j in jobs)
                ListTile(
                  leading: Icon(
                      j['status'] == 'succeeded'
                          ? Icons.check_circle_rounded
                          : j['status'] == 'failed'
                              ? Icons.cancel_rounded
                              : Icons.autorenew_rounded,
                      color: j['status'] == 'succeeded'
                          ? const Color(0xFF30A46C)
                          : j['status'] == 'failed'
                              ? const Color(0xFFE5484D)
                              : cs.primary),
                  title: Text('${j['host']} / ${j['node']}'),
                  subtitle: Text('${relativeTime(j['started_at'] as String?)} · ${j['user']}'
                      '${j['reboot_recommended'] == true ? ' · Neustart empfohlen' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _JobPage(id: j['id'] as String))),
                ),
            ],
          ]),
        );
      },
    );
  }
}

class _JobPage extends StatefulWidget {
  final String id;
  const _JobPage({required this.id});
  @override
  State<_JobPage> createState() => _JobPageState();
}

class _JobPageState extends State<_JobPage> {
  Map<String, dynamic>? _job;
  Object? _error;
  Timer? _timer;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_job == null || _job!['status'] == 'running') _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await context.session.api!.getJson('/api/pve/jobs/${widget.id}');
      if (!mounted) return;
      setState(() => _job = j);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = _job;
    return Scaffold(
      appBar: AppBar(title: Text(j == null ? 'Upgrade' : '${j['node']}: ${_label(j['status'] as String?)}')),
      body: j == null
          ? (_error != null ? ErrorState(error: _error, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : Column(children: [
              if (j['error'] != null)
                Container(
                    width: double.infinity,
                    color: const Color(0xFF5A1E1E),
                    padding: const EdgeInsets.all(12),
                    child: Text('${j['error']}', style: const TextStyle(color: Colors.white))),
              if (j['reboot_recommended'] == true)
                Container(
                    width: double.infinity,
                    color: const Color(0xFF5A4A1E),
                    padding: const EdgeInsets.all(12),
                    child: const Text('Neuer Kernel installiert – Neustart empfohlen.', style: TextStyle(color: Colors.white))),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF0B0F17),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    child: SelectableText('${j['output'] ?? ''}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFE5E7EB))),
                  ),
                ),
              ),
            ]),
    );
  }

  static String _label(String? s) =>
      switch (s) { 'running' => 'läuft', 'succeeded' => 'erfolgreich', 'failed' => 'fehlgeschlagen', _ => s ?? '' };
}

class _Guests extends StatelessWidget {
  const _Guests();

  Future<void> _installAgent(BuildContext context, Map h, Map g) async {
    final ok = await confirmDialog(context, 'Agent in ${g['vmid']} ${g['name']} installieren?',
        'RIMPERIO öffnet die Shell von ${g['node']} und installiert den Agent per pct exec im Container – ohne SSH. '
            'Braucht einen Proxmox-Zugang mit Shell-Recht (root@pam).',
        action: 'Installieren');
    if (!ok || !context.mounted) return;
    final api = context.session.api!;
    showInfo(context, 'Installation läuft (bis zu einigen Minuten) …');
    try {
      final token = await api.postJson('/api/agent-tokens', {
        'name': 'App: ${g['name']}',
        'kind': 'enroll',
        'expires_in_hours': 24,
        'max_uses': 1,
        'note': 'Aus der App beim Einbinden eines Containers erzeugt.',
      });
      final r = await api.postJson('/api/pve/hosts/${h['id']}/lxc/${g['vmid']}/install-agent',
          {'node': g['node'], 'secret': token['token'], 'site': 'Standard'});
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(r['ok'] == true ? 'Agent installiert' : 'Installation fehlgeschlagen'),
          content: SingleChildScrollView(
              child: SelectableText('${r['output'] ?? ''}'.split('\n').reversed.take(20).toList().reversed.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    return AsyncView<List<Map<String, dynamic>>>(
      load: () async {
        final r = await s.api!.getRaw('/api/patching/pve/hosts');
        return (r is List ? r : const []).cast<Map<String, dynamic>>();
      },
      builder: (context, hosts, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [
          for (final h in hosts) ...[
            SectionHeader('${h['name']}'),
            for (final g in ((h['guests'] as List?) ?? const []).cast<Map<String, dynamic>>())
              ListTile(
                leading: Icon(g['type'] == 'lxc' ? Icons.view_in_ar_rounded : Icons.computer_rounded,
                    color: g['status'] == 'running' ? const Color(0xFF30A46C) : context.cs.outline),
                title: Text('${g['vmid']} · ${g['name']}'),
                subtitle: Text('${g['type'] == 'lxc' ? 'Container' : 'VM'} · ${g['node']} · ${g['status']}'
                    '${(g['ips'] as List?)?.isNotEmpty == true ? ' · ${(g['ips'] as List).first}' : ''}'),
                trailing: s.isAdmin && g['status'] == 'running'
                    ? PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'console') {
                            PveConsolePage.open(context,
                                hostId: h['id'] as int,
                                node: '${g['node']}',
                                kind: '${g['type']}',
                                vmid: int.tryParse('${g['vmid']}'),
                                title: '${g['vmid']} ${g['name']}');
                          } else if (v == 'install') {
                            _installAgent(context, h, g);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'console', child: Text(g['type'] == 'lxc' ? 'Konsole' : 'Serielle Konsole')),
                          if (g['type'] == 'lxc') const PopupMenuItem(value: 'install', child: Text('RIMPERIO-Agent installieren')),
                        ],
                      )
                    : null,
              ),
          ],
          if (hosts.isEmpty) const EmptyState(icon: Icons.dns_outlined, title: 'Kein Proxmox verbunden'),
        ]),
      ),
    );
  }
}
