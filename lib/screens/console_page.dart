// ---------------------------------------------------------------------------
// Datei:        lib/screens/console_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
//
// Beschreibung: Fernzugriff aus der App.
//                 * AgentConsolePage: Befehle auf einem Rechner mit
//                   RIMPERIO-Agent — Linux als Dienstkonto „rimperio“,
//                   Windows in PowerShell. Jeder Befehl läuft für sich, das
//                   Arbeitsverzeichnis wandert mit (cd bleibt erhalten).
//                 * PveConsolePage: echte Konsole über Proxmox (termproxy) —
//                   Shell des Knotens, Konsole eines LXC-Containers, serielle
//                   Konsole einer VM. WebSocket mit Ticket (60 s gültig).
//                 * openRdp: RDP-Verbindung zu einem Windows-Rechner über die
//                   RDP-App des Handys (Windows App / Remote Desktop).
// ---------------------------------------------------------------------------
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35);
final _ansi = RegExp(r'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[=>()][0-9A-Za-z]?');

// ===========================================================================
// Befehle über den Agent
// ===========================================================================
class AgentConsolePage extends StatefulWidget {
  final String agentUid;
  final String host;
  final bool windows;
  const AgentConsolePage({super.key, required this.agentUid, required this.host, required this.windows});

  static Future<void> open(BuildContext context, {required String uid, required String host, required bool windows}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AgentConsolePage(agentUid: uid, host: host, windows: windows)));

  @override
  State<AgentConsolePage> createState() => _AgentConsolePageState();
}

class _Entry {
  final String cwd;
  final String command;
  String output = '';
  String? error;
  int? exit;
  bool running = true;
  _Entry(this.cwd, this.command);
}

class _AgentConsolePageState extends State<AgentConsolePage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _entries = <_Entry>[];
  final _history = <String>[];
  int _histPos = 0;
  String _cwd = '';
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final cmd = _input.text.trim();
    if (cmd.isEmpty || _busy) return;
    if (cmd == 'clear' || cmd == 'cls') {
      setState(() => _entries.clear());
      _input.clear();
      return;
    }
    _history.add(cmd);
    _histPos = _history.length;
    final e = _Entry(_cwd, cmd);
    setState(() {
      _entries.add(e);
      _busy = true;
    });
    _input.clear();
    _toEnd();
    final api = context.session.api!;
    try {
      final r = await api.postJson('/api/app/remote/${widget.agentUid}/exec', {'command': cmd, 'cwd': _cwd});
      final id = r['id'] as int;
      final started = DateTime.now();
      while (mounted) {
        await Future.delayed(const Duration(milliseconds: 900));
        final d = await api.getJson('/api/app/remote/commands/$id');
        final status = d['status'] as String? ?? '';
        if (status == 'pending' && DateTime.now().difference(started) > const Duration(seconds: 45)) {
          e.error = 'Der Rechner hat den Befehl noch nicht abgeholt – ist er online?';
        }
        if (status == 'pending' || status == 'running') {
          if (mounted) setState(() {});
          continue;
        }
        e.output = [d['stdout'] ?? '', if ((d['stderr'] ?? '').toString().isNotEmpty) d['stderr']].join('\n').trimRight();
        e.exit = d['exit_code'] as int?;
        e.error = status == 'timeout' ? 'Zeitüberschreitung.' : null;
        if (d['cwd'] != null) _cwd = d['cwd'] as String;
        break;
      }
    } catch (err) {
      e.error = '$err';
    } finally {
      e.running = false;
      if (mounted) setState(() => _busy = false);
      _toEnd();
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  void _historyStep(int d) {
    if (_history.isEmpty) return;
    _histPos = (_histPos + d).clamp(0, _history.length);
    _input.text = _histPos < _history.length ? _history[_histPos] : '';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final prompt = widget.windows ? 'PS ${_cwd.isEmpty ? '' : _cwd}>' : 'rimperio@${widget.host}:${_cwd.isEmpty ? '~' : _cwd}\$';
    return Scaffold(
      appBar: AppBar(title: Text(widget.host), actions: [
        IconButton(
          tooltip: 'Alles kopieren',
          icon: const Icon(Icons.copy_all_rounded),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _entries.map((e) => '> ${e.command}\n${e.output}').join('\n')));
            showInfo(context, 'Kopiert.');
          },
        ),
      ]),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: cs.surfaceContainerHigh,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
              widget.windows
                  ? 'PowerShell über den Agent (SYSTEM). Jeder Befehl läuft für sich; Programme mit eigener Oberfläche gehen nicht.'
                  : 'Shell als Dienstkonto „rimperio“ über den Agent. Jeder Befehl läuft für sich (cd bleibt erhalten); '
                      'interaktive Programme (vim, top) gehen nicht.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF0B0F17),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final e = _entries[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText.rich(TextSpan(children: [
                      TextSpan(
                          text: widget.windows ? 'PS ${e.cwd}> ' : '${e.cwd.isEmpty ? '~' : e.cwd}\$ ',
                          style: _mono.copyWith(color: const Color(0xFF4ADE80))),
                      TextSpan(text: e.command, style: _mono.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                    ])),
                    if (e.running)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    if (e.output.isNotEmpty)
                      SelectableText(e.output.replaceAll(_ansi, ''), style: _mono.copyWith(color: const Color(0xFFE5E7EB))),
                    if (e.error != null)
                      Text(e.error!, style: _mono.copyWith(color: const Color(0xFFFCA5A5))),
                    if (!e.running && e.exit != null && e.exit != 0)
                      Text('[Rückgabewert ${e.exit}]', style: _mono.copyWith(color: const Color(0xFFFBBF24))),
                  ]),
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(children: [
              IconButton(onPressed: () => _historyStep(-1), icon: const Icon(Icons.keyboard_arrow_up)),
              Expanded(
                child: TextField(
                  controller: _input,
                  style: _mono,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(hintText: prompt, isDense: true),
                  onSubmitted: (_) => _run(),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : _run,
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ===========================================================================
// RDP
// ===========================================================================
Future<void> openRdp(BuildContext context, String uid, String host) async {
  final s = context.session;
  final user = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: Text('RDP zu $host'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Öffnet die RDP-App des Handys (z. B. „Windows App“ / „Remote Desktop“). '
              'Das Handy muss den Rechner erreichen – im gleichen Netz oder per VPN.'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Benutzer (optional)', isDense: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Verbinden')),
        ],
      );
    },
  );
  if (user == null || !context.mounted) return;
  try {
    final d = await s.api!.getJson('/api/app/remote/$uid/rdp', {'username': user});
    final uri = Uri.parse(d['uri'] as String);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keine RDP-App gefunden'),
          content: SelectableText('Bitte eine RDP-App installieren (Windows App / Microsoft Remote Desktop) '
              'und verbinden mit:\n\n${d['address']}:${d['port']}'),
          actions: [
            TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${d['address']}'));
                  Navigator.pop(ctx);
                },
                child: const Text('Adresse kopieren')),
          ],
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> enableRdp(BuildContext context, String uid, String host) async {
  final ok = await confirmDialog(context, 'RDP auf $host einschalten?',
      'Schaltet Remotedesktop mit Netzwerkebenen-Authentifizierung ein und öffnet die Windows-Firewall dafür.',
      action: 'Einschalten');
  if (!ok || !context.mounted) return;
  try {
    await context.session.api!.postJson('/api/app/remote/$uid/enable-rdp', const {});
    if (context.mounted) showInfo(context, 'Auftrag an $host geschickt.');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

// ===========================================================================
// Proxmox-Konsole (Knoten, LXC, VM) über WebSocket
// ===========================================================================
class PveConsolePage extends StatefulWidget {
  final int hostId;
  final String node;
  final String kind; // node | lxc | qemu
  final int? vmid;
  final String title;
  const PveConsolePage(
      {super.key, required this.hostId, required this.node, required this.kind, this.vmid, required this.title});

  static Future<void> open(BuildContext context,
          {required int hostId, required String node, required String kind, int? vmid, required String title}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PveConsolePage(hostId: hostId, node: node, kind: kind, vmid: vmid, title: title)));

  @override
  State<PveConsolePage> createState() => _PveConsolePageState();
}

class _PveConsolePageState extends State<PveConsolePage> {
  WebSocket? _ws;
  final _lines = <String>[''];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _error;
  bool _connected = false;
  Timer? _ping;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _ping?.cancel();
    _ws?.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final s = context.session;
    setState(() {
      _error = null;
      _connected = false;
    });
    try {
      final ticket = await s.api!.ticket('console');
      final base = s.server!.resolve('/api/pve/console/ws', {
        'token': ticket,
        'host_id': '${widget.hostId}',
        'node': widget.node,
        'kind': widget.kind,
        if (widget.vmid != null) 'vmid': '${widget.vmid}',
        'cols': '100',
        'rows': '40',
      });
      final url = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws');
      final ws = await WebSocket.connect(url.toString()).timeout(const Duration(seconds: 20));
      _ws = ws;
      ws.listen((raw) {
        final Map<String, dynamic> m;
        try {
          m = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>)) as Map<String, dynamic>;
        } catch (_) {
          _write('$raw');
          return;
        }
        switch (m['type']) {
          case 'output':
            _write('${m['data']}');
          case 'ready':
            setState(() => _connected = true);
          case 'error':
            setState(() => _error = '${m['message']}');
          case 'closed':
            _write('\n[${m['reason']}]\n');
        }
      }, onDone: () {
        if (mounted) setState(() => _connected = false);
      }, onError: (e) {
        if (mounted) setState(() => _error = '$e');
      });
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  void _key(String data) => _send({'type': 'input', 'data': data});

  /// Schlanker Bildschirm: ANSI weg, \r überschreibt die Zeile, Rücktaste löscht.
  void _write(String chunk) {
    final text = chunk.replaceAll(_ansi, '');
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '\n') {
        _lines.add('');
      } else if (c == '\r') {
        if (i + 1 < text.length && text[i + 1] == '\n') continue;
        _lines[_lines.length - 1] = '';
      } else if (c == '\b') {
        final l = _lines.last;
        if (l.isNotEmpty) _lines[_lines.length - 1] = l.substring(0, l.length - 1);
      } else if (c.codeUnitAt(0) >= 32 || c == '\t') {
        _lines[_lines.length - 1] += c == '\t' ? '    ' : c;
      }
    }
    if (_lines.length > 2000) _lines.removeRange(0, _lines.length - 2000);
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Icon(Icons.circle, size: 12, color: _connected ? const Color(0xFF30A46C) : cs.outline),
        ),
        if (!_connected) IconButton(onPressed: _connect, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFF5A1E1E),
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: const TextStyle(color: Colors.white)),
          ),
        if (widget.kind == 'lxc')
          Container(
            width: double.infinity,
            color: cs.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Fragt der Container nach einer Anmeldung, mit root und dessen Passwort anmelden '
                '(oder in Proxmox die Konsole auf „shell“ stellen).', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: const Color(0xFF0B0F17),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(10),
              itemCount: _lines.length,
              itemBuilder: (_, i) => Text(_lines[i], style: _mono.copyWith(color: const Color(0xFFE5E7EB))),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final (label, data) in [
              ('Tab', '\t'), ('Strg+C', '\x03'), ('Strg+D', '\x04'), ('Esc', '\x1b'),
              ('↑', '\x1b[A'), ('↓', '\x1b[B'), ('←', '\x1b[D'), ('→', '\x1b[C'), ('q', 'q'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                child: ActionChip(label: Text(label), onPressed: _connected ? () => _key(data) : null),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  style: _mono,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(hintText: 'Eingabe + Enter', isDense: true),
                  onSubmitted: (_) {
                    _key('${_input.text}\r');
                    _input.clear();
                  },
                ),
              ),
              IconButton(
                onPressed: _connected
                    ? () {
                        _key('${_input.text}\r');
                        _input.clear();
                      }
                    : null,
                icon: const Icon(Icons.keyboard_return_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
