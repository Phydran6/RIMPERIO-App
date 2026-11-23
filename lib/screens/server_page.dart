// ---------------------------------------------------------------------------
// Datei:        lib/screens/server_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
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
