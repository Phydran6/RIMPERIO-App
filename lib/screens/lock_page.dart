// ---------------------------------------------------------------------------
// Datei:        lib/screens/lock_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Sperrbildschirm bei eingeschalteter Biometrie. Fragt beim
//               Öffnen sofort nach Fingerabdruck / Gesicht.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';

class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.session.unlock();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = (err == null || err.isEmpty) ? null : err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final cs = context.cs;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            const Spacer(),
            const Logo(size: 120),
            const SizedBox(height: 24),
            Text('Gesperrt', style: context.tt.headlineSmall),
            const SizedBox(height: 6),
            Text(
              [if (s.username != null) s.username!, s.server?.host ?? ''].join(' · '),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 40),
            IconButton.filledTonal(
              iconSize: 48,
              padding: const EdgeInsets.all(20),
              onPressed: _busy ? null : _unlock,
              icon: const Icon(Icons.fingerprint_rounded),
              tooltip: 'Entsperren',
            ),
            const SizedBox(height: 12),
            Text(_busy ? 'Bitte bestätigen …' : 'Tippen zum Entsperren',
                style: TextStyle(color: cs.onSurfaceVariant)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
            ],
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : s.unlockWithPassword,
              child: const Text('Mit Passwort anmelden'),
            ),
          ]),
        ),
      ),
    );
  }
}
