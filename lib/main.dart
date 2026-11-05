// ---------------------------------------------------------------------------
// Datei:        lib/main.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.05.12.00.00
//
// Beschreibung: Einstieg der App. Entscheidet beim Start: ist schon ein Server
//               hinterlegt → WebView; sonst → Einrichtung.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'setup_page.dart';
import 'storage.dart';
import 'webview_page.dart';

void main() => runApp(const RimperioApp());

class RimperioApp extends StatelessWidget {
  const RimperioApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return MaterialApp(
      title: 'RIMPERIO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0A1222),
      ),
      home: const _Gate(),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await Storage.getUrl();
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_url == null || _url!.isEmpty) {
      return SetupPage(onSaved: (u) => setState(() => _url = u));
    }
    return WebViewPage(url: _url!, onReset: () => setState(() => _url = null));
  }
}
