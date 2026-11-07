// ---------------------------------------------------------------------------
// Datei:        lib/screens/home_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Gerüst der App mit unterer Navigationsleiste. Nach der ersten
//               Anmeldung fragt es einmal nach Biometrie und nach der
//               Benachrichtigungs-Berechtigung. Im Vordergrund holt es jede
//               Minute neue Meldungen.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/biometrics.dart';
import '../core/notifications.dart';
import '../core/storage.dart';
import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'dashboard_page.dart';
import 'devices_page.dart';
import 'inbox_page.dart';
import 'logs_page.dart';
import 'more_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onboarding());
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => _pollNow());
    _pollNow();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pollNow() async {
    final api = context.session.api;
    if (api == null) return;
    try {
      await Notifications.poll();
      final d = await api.getJson('/api/app/notifications', {'unread': true, 'limit': 1});
      if (mounted) setState(() => _unread = (d['unread'] as int?) ?? 0);
    } catch (_) {
      // still — Fehler zeigen die Seiten selbst
    }
  }

  /// Einmalige Fragen nach der Anmeldung.
  Future<void> _onboarding() async {
    final s = context.session;
    if (!s.biometricEnabled && !await Storage.getFlag('asked_biometric') && await Biometrics.available()) {
      await Storage.setFlag('asked_biometric');
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.fingerprint_rounded, size: 36),
          title: const Text('Biometrisch anmelden?'),
          content: Text(s.canRememberPassword
              ? 'Künftig reicht Fingerabdruck oder Gesicht zum Öffnen der App — auch wenn die '
                  'Sitzung abgelaufen ist. Das Passwort liegt dann verschlüsselt im '
                  'Schlüsselspeicher des Geräts.'
              : 'Künftig schützt Fingerabdruck oder Gesicht den Zugang zur App.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Später')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Einschalten')),
          ],
        ),
      );
      if (yes == true) {
        final err = await s.enableBiometric();
        if (mounted && err != null && err.isNotEmpty) showError(context, err);
        if (mounted && err == null) showInfo(context, 'Biometrische Anmeldung ist an.');
      }
    }

    if (!await Storage.getFlag('asked_notify')) {
      await Storage.setFlag('asked_notify');
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.notifications_active_outlined, size: 36),
          title: const Text('Benachrichtigungen?'),
          content: const Text(
              'RIMPERIO meldet Freigaben, fehlgeschlagene Updates und Alarme als Benachrichtigung '
              'aufs Handy.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nein')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Erlauben')),
          ],
        ),
      );
      if (yes == true) {
        final granted = await Notifications.requestPermission();
        await Storage.setNotify(granted);
        await Notifications.schedule(granted);
        if (mounted && !granted) {
          showInfo(context, 'Nicht erlaubt — lässt sich in den Systemeinstellungen nachholen.');
        }
      } else {
        await Storage.setNotify(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final pages = [
      DashboardPage(onOpenTab: (i) => setState(() => _tab = i)),
      const LogsPage(),
      const DevicesPage(),
      InboxPage(onUnreadChanged: (n) => setState(() => _unread = n)),
      const MorePage(),
    ];
    return Scaffold(
      body: Column(children: [
        if (!s.isSecure) const SafeArea(bottom: false, child: InsecureBanner()),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: !s.isSecure,
            child: IndexedStack(index: _tab, children: pages),
          ),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Übersicht'),
          const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Logs'),
          const NavigationDestination(
              icon: Icon(Icons.devices_other_outlined), selectedIcon: Icon(Icons.devices_other), label: 'Geräte'),
          NavigationDestination(
            icon: Badge(
                isLabelVisible: _unread > 0,
                label: Text('$_unread'),
                child: const Icon(Icons.notifications_outlined)),
            selectedIcon: Badge(
                isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.notifications)),
            label: 'Meldungen',
          ),
          const NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'Mehr'),
        ],
      ),
    );
  }
}
