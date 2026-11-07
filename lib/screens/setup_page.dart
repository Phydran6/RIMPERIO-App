// ---------------------------------------------------------------------------
// Datei:        lib/screens/setup_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Erster Start — Server per QR-Code (Anmeldung gleich mit) oder
//               von Hand verbinden. Die App probiert immer zuerst HTTPS; auf
//               http:// fällt sie nur nach ausdrücklicher Bestätigung zurück.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/server_address.dart';
import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'scan_page.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    ServerAddress addr;
    try {
      addr = ServerAddress.parse(_controller.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final chosen = await resolveSecure(context, addr);
      if (chosen == null || !mounted) return;
      await context.session.setServer(chosen);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Logo(size: 140)),
                  const SizedBox(height: 20),
                  Text('Willkommen', textAlign: TextAlign.center, style: context.tt.headlineSmall),
                  const SizedBox(height: 6),
                  Text('Verbinde die App mit deinem RIMPERIO-Server.',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => ScanPage.open(context),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('QR-Code scannen'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Den Code zeigt die Weboberfläche unter Benutzer → App verbinden. '
                    'Server und Anmeldung werden damit in einem Schritt eingerichtet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('oder von Hand', style: TextStyle(color: cs.outline, fontSize: 12)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enabled: !_busy,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      labelText: 'Server-Adresse',
                      hintText: 'rmm.example.de',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      errorText: _error,
                      errorMaxLines: 4,
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy ? null : _connect,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Verbinden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prüft die Adresse und sorgt für HTTPS, wo immer es geht:
/// * https:// erreichbar → nehmen.
/// * http:// angegeben → erst https versuchen; klappt das, still umstellen.
/// * nur http erreichbar → deutlich warnen, nur nach Bestätigung nehmen.
/// Gibt `null` zurück, wenn der Nutzer abbricht.
Future<ServerAddress?> resolveSecure(BuildContext context, ServerAddress addr) async {
  if (addr.isSecure) {
    final api = Api(addr);
    try {
      await api.ping();
      return addr;
    } finally {
      api.close();
    }
  }

  // http:// angegeben — klappt https trotzdem?
  final https = addr.asHttps;
  final probe = Api(https);
  try {
    await probe.ping();
    if (context.mounted) {
      showInfo(context, 'Der Server kann HTTPS — die App nutzt die verschlüsselte Verbindung.');
    }
    return https;
  } on ApiException {
    // weiter mit http
  } finally {
    probe.close();
  }

  final plain = Api(addr);
  try {
    await plain.ping();
  } finally {
    plain.close();
  }
  if (!context.mounted) return null;
  final ok = await confirmInsecure(context, addr.host);
  return ok ? addr : null;
}

Future<bool> confirmInsecure(BuildContext context, String host) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.lock_open_rounded, color: Color(0xFFF2555A)),
      title: const Text('Unverschlüsselte Verbindung'),
      content: Text(
        '$host spricht nur HTTP. Passwort, Sitzungs-Token und alle Daten gehen '
        'im Klartext über das Netz.\n\n'
        'Besser: am Server HTTPS einschalten (RIMPERIO_SITE_ADDRESS bzw. Domain bei der '
        'Installation) — dann stellt die App automatisch um.\n\n'
        'Nur im eigenen, vertrauenswürdigen Netz fortfahren.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFF2555A)),
          child: const Text('Trotzdem HTTP'),
        ),
      ],
    ),
  );
  return res ?? false;
}
