// ---------------------------------------------------------------------------
// Datei:        lib/setup_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.06.23.30.00
//
// Beschreibung: Einrichtung — die Adresse des eigenen RIMPERIO-Servers eingeben.
//               Fehlt das Schema, wird https:// vorangestellt.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'storage.dart';

class SetupPage extends StatefulWidget {
  final void Function(String url) onSaved;
  const SetupPage({super.key, required this.onSaved});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _controller = TextEditingController();
  String? _error;

  String _normalize(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'https://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Future<void> _save() async {
    final url = _normalize(_controller.text);
    if (url.isEmpty) {
      setState(() => _error = 'Bitte eine Server-Adresse eingeben.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      setState(() => _error = 'Die Adresse sieht nicht gültig aus.');
      return;
    }
    await Storage.setUrl(url);
    widget.onSaved(url);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Das Logo trägt die Wortmarke selbst — kein extra Titel.
                  Center(
                    child: Image.asset(
                      'assets/icon/rimperio_logo.png',
                      width: 168,
                      height: 168,
                      filterQuality: FilterQuality.medium,
                      semanticLabel: 'RIMPERIO',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Mit deinem Server verbinden',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server-Adresse',
                      hintText: 'rmm.example.de',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _save, child: const Text('Verbinden')),
                  const SizedBox(height: 12),
                  const Text(
                    'Die Anmeldung (admin / …) erfolgt danach auf der Server-Seite.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
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
