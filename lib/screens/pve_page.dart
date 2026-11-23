// ---------------------------------------------------------------------------
// Datei:        lib/screens/pve_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
//
// Beschreibung: Proxmox in der App — Updates der Knoten selbst (Liste,
//               Paketlisten auffrischen, Upgrade mit Live-Ausgabe, Neustart),
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
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Proxmox'),
            bottom: const TabBar(tabs: [Tab(text: 'Knoten & Updates'), Tab(text: 'Gäste')]),
          ),
          body: const TabBarView(children: [_Nodes(), _Guests()]),
        ),
      );
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
