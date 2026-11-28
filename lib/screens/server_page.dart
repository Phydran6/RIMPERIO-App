// ---------------------------------------------------------------------------
// Datei:        lib/screens/server_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      0.2.0
//
// Beschreibung: RIMPERIO selbst aktualisieren — installierter und
//               verfügbarer Stand, Update starten (vorher Sicherung) und das
//               Protokoll mitlesen. Während des Updates ist der Server kurz
//               nicht erreichbar; die Seite fragt einfach weiter.
//               Quelle: /api/app/server/update.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServerPage()));
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  Map<String, dynamic>? _st;
  List<String> _log = const [];
  Object? _error;
  bool _busy = false;
  bool _following = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAuto();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final st = await context.session.api!.getJson('/api/app/server/update', {'force': force ? true : null});
      if (mounted) {
        setState(() {
          _st = st;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Map<String, dynamic>? _auto;

  Future<void> _loadAuto() async {
    try {
      final a = await context.session.api!.getJson('/api/app/server/autopilot');
      if (mounted) setState(() => _auto = a);
    } catch (_) {
      // aelterer Server ohne Autopilot
    }
  }

  Future<void> _decide(String decision) async {
    final v = '${(_auto?['candidate'] as Map?)?['tag'] ?? ''}';
    if (v.isEmpty) return;
    if (decision == 'approve' &&
        !await confirmDialog(context, 'RIMPERIO $v freigeben?',
            'Das Update startet sofort – mit Sicherung vorher und automatischem Rückfall.', action: 'Freigeben')) {
      return;
    }
    if (!mounted) return;
    try {
      await context.session.api!.postJson('/api/app/server/autopilot', {'version': v, 'decision': decision});
      if (!mounted) return;
      showInfo(context, decision == 'approve' ? 'Freigegeben – Update startet.' : 'Übersprungen.');
      if (decision == 'approve') _follow();
      await _loadAuto();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _follow() async {
    _timer?.cancel();
    setState(() => _following = true);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final d = await context.session.api!.getJson('/api/app/server/update/log', {'lines': 60});
        if (mounted) setState(() => _log = ((d['lines'] as List?) ?? const []).map((e) => '$e').toList());
        await _load();
      } catch (_) {
        // Server startet gerade neu – weiter fragen.
      }
    });
  }

  Future<void> _update() async {
    final st = _st!;
    final ok = await confirmWord(
        context,
        'RIMPERIO aktualisieren?',
        '${st['installed']} → ${st['available']}.\n\nVorher wird eine Sicherung angelegt. Während des Updates ist '
            'der Server ein paar Minuten nicht erreichbar.',
        'UPDATE');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.session.api!.postJson('/api/app/server/update', {'confirm': 'UPDATE', 'backup': true});
      if (!mounted) return;
      showInfo(context, 'Update läuft – das Protokoll erscheint unten.');
      _follow();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: const Text('RIMPERIO-Server'), actions: [
        IconButton(tooltip: 'Auf Updates prüfen', onPressed: () => _load(force: true), icon: const Icon(Icons.refresh)),
      ]),
      body: st == null
          ? (_error != null ? ErrorState(error: _error, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: StatTile(icon: Icons.dns_rounded, label: 'Installiert', value: '${st['installed'] ?? '–'}')),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    icon: Icons.cloud_download_outlined,
                    label: 'Verfügbar',
                    value: '${st['available'] ?? '–'}',
                    color: st['update_available'] == true ? RimTheme.gold : const Color(0xFF30A46C),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              if (st['reason'] != null) Text('${st['reason']}', style: TextStyle(color: cs.onSurfaceVariant)),
              if (st['host_access'] != true) ...[
                const SizedBox(height: 12),
                Text('Kein Zugriff auf den Host – das Update geht nur auf der Kommandozeile:',
                    style: TextStyle(color: cs.error)),
                SelectableText('${st['oneliner'] ?? ''}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
              if ((st['run'] as Map?)?['status'] != null) ...[
                const SizedBox(height: 12),
                Text('Letzter Vorgang: ${(st['run'] as Map)['status']} ${(st['run'] as Map)['message'] ?? ''}',
                    style: TextStyle(color: cs.outline, fontSize: 12)),
              ],
              if (_auto != null) ...[
                const SectionHeader('Autopilot'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(_auto!['enabled'] == true ? Icons.autorenew_rounded : Icons.pause_circle_outline,
                            color: _auto!['enabled'] == true ? const Color(0xFF30A46C) : cs.outline),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_auto!['enabled'] == true ? 'RIMPERIO hält sich selbst aktuell' : 'Autopilot aus')),
                      ]),
                      const SizedBox(height: 6),
                      Text('${_auto!['reason'] ?? ''}', style: TextStyle(color: cs.onSurfaceVariant)),
                      if (_auto!['action'] == 'await_approval' && context.session.isAdmin) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          FilledButton.icon(
                              onPressed: () => _decide('approve'),
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('Freigeben')),
                          TextButton(onPressed: () => _decide('skip'), child: const Text('Überspringen')),
                        ]),
                      ],
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (context.session.isAdmin)
                FilledButton.icon(
                  onPressed: _busy || st['update_available'] != true || st['host_access'] != true || st['is_downgrade'] == true
                      ? null
                      : _update,
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: Text(st['update_available'] == true ? 'Jetzt aktualisieren' : 'Aktuell'),
                ),
              if (!_following && context.session.isAdmin)
                TextButton(onPressed: _follow, child: const Text('Protokoll anzeigen')),
              if (_following) ...[
                const SectionHeader('Protokoll'),
                Container(
                  color: const Color(0xFF0B0F17),
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(_log.isEmpty ? '…' : _log.join('\n'),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFE5E7EB))),
                ),
              ],
              if ((st['notes'] ?? '').toString().isNotEmpty) ...[
                const SectionHeader('Neu in dieser Version'),
                Text('${st['notes']}'),
              ],
            ]),
    );
  }
}
