// ---------------------------------------------------------------------------
// Datei:        lib/screens/more_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Weitere Bereiche und Einstellungen — Updates, SNMP,
//               Biometrie, Benachrichtigungen, Verbindung, Abmelden.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../core/biometrics.dart';
import '../core/notifications.dart';
import '../core/storage.dart';
import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'patches_page.dart';
import 'snmp_page.dart';

class MorePage extends StatefulWidget {
  const MorePage({super.key});
  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  bool? _bioAvailable;
  bool _notify = false;
  bool _notifyPermitted = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final bio = await Biometrics.available();
    final n = await Storage.getNotify();
    final p = await Notifications.permitted();
    if (mounted) {
      setState(() {
        _bioAvailable = bio;
        _notify = n && p;
        _notifyPermitted = p;
      });
    }
  }

  Future<void> _toggleBiometric(bool on) async {
    final s = context.session;
    if (on) {
      final err = await s.enableBiometric();
      if (mounted && err != null && err.isNotEmpty) showError(context, err);
      if (mounted && err == null && !s.hasStoredPassword) {
        showInfo(context,
            'Biometrie an. Nach Ablauf der Sitzung (24 h) einmal mit Passwort anmelden — danach reicht der Fingerabdruck.');
      }
    } else {
      await s.disableBiometric();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleNotify(bool on) async {
    var granted = _notifyPermitted;
    if (on && !granted) granted = await Notifications.requestPermission();
    if (on && !granted) {
      if (mounted) {
        showInfo(context, 'Benachrichtigungen sind für RIMPERIO in den Systemeinstellungen blockiert.');
      }
      return;
    }
    await Storage.setNotify(on);
    await Notifications.schedule(on);
    if (on) await Notifications.poll(); // Stand merken
    if (mounted) {
      setState(() {
        _notify = on;
        _notifyPermitted = granted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final cs = context.cs;
    final caps = (s.bootstrap?['server']?['capabilities'] as List?)?.cast<String>() ?? const [];
    final user = s.bootstrap?['user'] as Map?;

    return CustomScrollView(slivers: [
      const SliverAppBar.medium(title: Text('Mehr')),
      SliverList.list(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(((user?['username'] ?? s.username ?? '?') as String).characters.first.toUpperCase(),
                    style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
              ),
              title: Text('${user?['username'] ?? s.username ?? 'Angemeldet'}'),
              subtitle: Text([
                if (user?['role'] != null) user!['role'],
                if (user?['mfa_enabled'] == true) 'MFA an',
              ].join(' · ')),
            ),
          ),
        ),
        const SectionHeader('Bereiche'),
        if (caps.contains('patch-approvals'))
          ListTile(
            leading: const Icon(Icons.system_update_alt_rounded),
            title: const Text('Updates & Freigaben'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => PatchesPage.open(context),
          ),
        if (caps.contains('snmp-status'))
          ListTile(
            leading: const Icon(Icons.router_outlined),
            title: const Text('SNMP-Geräte'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => SnmpPage.open(context),
          ),
        const SectionHeader('Sicherheit'),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint_rounded),
          title: const Text('Biometrische Anmeldung'),
          subtitle: Text(_bioAvailable == false
              ? 'Auf diesem Gerät nicht eingerichtet'
              : s.biometricEnabled
                  ? (s.hasStoredPassword
                      ? 'An — Fingerabdruck meldet auch nach Ablauf neu an'
                      : 'An — sperrt die App nach 2 min im Hintergrund')
                  : 'Fingerabdruck oder Gesicht statt Passwort'),
          value: s.biometricEnabled,
          onChanged: _bioAvailable == true ? _toggleBiometric : null,
        ),
        ListTile(
          leading: Icon(s.isSecure ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: s.isSecure ? const Color(0xFF30A46C) : const Color(0xFFF2555A)),
          title: Text(s.isSecure ? 'Verschlüsselt (HTTPS)' : 'Unverschlüsselt (HTTP)'),
          subtitle: Text(s.server?.base ?? ''),
        ),
        const SectionHeader('Benachrichtigungen'),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Benachrichtigungen'),
          subtitle: const Text('Freigaben, Fehlschläge und Alarme — im Hintergrund etwa alle 15 min'),
          value: _notify,
          onChanged: _toggleNotify,
        ),
        const SectionHeader('Konto'),
        ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('Abmelden'),
          onTap: () => s.logout(),
        ),
        ListTile(
          leading: Icon(Icons.swap_horiz_rounded, color: cs.error),
          title: Text('Server wechseln', style: TextStyle(color: cs.error)),
          subtitle: const Text('Entfernt Server, Anmeldung und Einstellungen von diesem Gerät'),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Server wechseln?'),
                content: const Text('Die App vergisst Server, Anmeldung und Biometrie-Einstellung.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wechseln')),
                ],
              ),
            );
            if (ok == true) await s.changeServer();
          },
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Server ${s.bootstrap?['server']?['version'] ?? '–'} · API-Level ${s.bootstrap?['server']?['api_level'] ?? '–'}',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline, fontSize: 12),
          ),
        ),
      ]),
    ]);
  }
}
