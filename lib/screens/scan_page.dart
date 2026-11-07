// ---------------------------------------------------------------------------
// Datei:        lib/screens/scan_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: QR-Code-Anmeldung. Kamera auf den Code aus der Weboberfläche
//               halten → Server übernehmen und Einmal-Token gegen eine
//               Sitzung tauschen (POST /api/auth/app-token/exchange).
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/qr_login.dart';
import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'setup_page.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanPage()));

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _busy = false;
  String? _error;
  String? _lastRaw;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null || raw == _lastRaw) return;
    _lastRaw = raw;

    QrLogin qr;
    try {
      qr = QrLogin.parse(raw);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    await _scanner.stop();
    try {
      var server = qr.server;
      if (!server.isSecure) {
        // Der Code kommt mit http://, wenn am Server keine SITE_URL gesetzt ist.
        // Erst prüfen, ob HTTPS doch geht; sonst nur nach Rückfrage.
        if (!mounted) return;
        final chosen = await resolveSecure(context, server);
        if (chosen == null) {
          _reset();
          return;
        }
        server = chosen;
      }
      if (!mounted) return;
      await context.session.loginWithQr(server, qr.token);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      _reset(e.isUnauthorized
          ? 'Der Code ist abgelaufen oder wurde schon benutzt. Bitte in der Weboberfläche einen neuen erzeugen.'
          : e.message);
    } catch (e) {
      _reset('$e');
    }
  }

  void _reset([String? error]) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _lastRaw = null;
    });
    _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Mit QR-Code anmelden'),
        actions: [
          IconButton(
            tooltip: 'Taschenlampe',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _scanner.toggleTorch(),
          ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraError(error: error),
        ),
        const _Viewfinder(),
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_busy)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(children: [
                    SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 16),
                    Text('Anmeldung läuft …'),
                  ]),
                ),
              )
            else if (_error != null)
              Card(
                color: const Color(0xFF5A1E1E),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.white)),
                ),
              )
            else
              const Text(
                'Weboberfläche → Benutzer → App verbinden\nden Code in den Rahmen halten',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: context.cs.primary, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  const _CameraError({required this.error});
  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
          const SizedBox(height: 16),
          Text(
            denied
                ? 'Kein Zugriff auf die Kamera. Bitte in den Systemeinstellungen für RIMPERIO erlauben.'
                : 'Kamera nicht verfügbar (${error.errorCode.name}).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ]),
      ),
    );
  }
}
