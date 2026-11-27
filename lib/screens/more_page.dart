// ---------------------------------------------------------------------------
// Datei:        lib/screens/more_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.26.22.00.00
//
// Beschreibung: Weitere Bereiche und Einstellungen — Logs (eigener Bereich),
//               Updates, Proxmox, DB-Updates, NAS, Backup, RIMPERIO-Server, SNMP,
//               Biometrie, Benachrichtigungen, App-Update, Verbindung,
//               Abmelden.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../core/app_update.dart';
import '../core/biometrics.dart';
import '../core/notifications.dart';
import '../core/storage.dart';
import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'app_update_page.dart';
import 'backups_page.dart';
import 'db_updates_page.dart';
import 'log_hub_page.dart';
import 'nas_page.dart';
import 'patches_page.dart';
import 'pve_page.dart';
import 'server_page.dart';
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
  InstalledApp? _app;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final bio = await Biometrics.available();
    final n = await Storage.getNotify();
    final p = await Notifications.permitted();
    final app = await AppUpdate.installed();
    if (mounted) {
      setState(() {
        _app = app;
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

  /// Ein Bereich unter „Mehr“. Kann der Server ihn (noch) nicht, bleibt er
  /// trotzdem sichtbar — mit Hinweis aufs Server-Update statt unsichtbar.
  Widget _area(List<String> caps, String cap,
      {required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    final ok = caps.contains(cap);
    final cs = context.cs;
    return ListTile(
      leading: Icon(icon, color: ok ? null : cs.outline),
      title: Text(title, style: ok ? null : TextStyle(color: cs.outline)),
      subtitle: Text(ok ? (subtitle ?? '') : 'Braucht einen neueren RIMPERIO-Server – bitte Server aktualisieren',
          style: ok ? null : TextStyle(color: cs.outline)),
      trailing: Icon(ok ? Icons.chevron_right : Icons.info_outline_rounded),
      onTap: ok ? onTap : () => _needsServerUpdate(title, caps),
    );
  }

  Future<void> _needsServerUpdate(String title, List<String> caps) async {
    final s = context.session;
    final canUpdate = caps.contains('server-update') && s.isAdmin;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded, size: 36),
        title: Text('$title: Server zu alt'),
        content: Text('Dein RIMPERIO-Server (${s.bootstrap?['server']?['version'] ?? 'Version unbekannt'}) '
            'kennt diesen Bereich noch nicht. Nach einem Server-Update ist er in der App da.'
            '${canUpdate ? '' : '\n\nAktualisieren: Weboberfläche → Updates.'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
          if (canUpdate) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Server aktualisieren')),
        ],
      ),
    );
    if (go == true && mounted) await ServerPage.open(context);
    if (mounted) {
      try {
        await s.refreshBootstrap();
      } catch (_) {}
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
        ListTile(
          leading: const Icon(Icons.receipt_long_rounded),
          title: const Text('Logs'),
          subtitle: const Text('Ansehen, suchen, Themen, Rauschen & Sperren, Aufbewahrung'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => LogHubPage.open(context),
        ),
        _area(caps, 'patch-approvals',
            icon: Icons.system_update_alt_rounded,
            title: 'Updates & Freigaben',
            subtitle: 'Freigeben, je Rechner/Container installieren, Läufe',
            onTap: () => PatchesPage.open(context)),
        _area(caps, 'db-updates',
            icon: Icons.storage_rounded,
            title: 'DB-Updates',
            subtitle: 'Datenbank-Container mit Sicherung und Probelauf',
            onTap: () => DbUpdatesPage.open(context)),
        _area(caps, 'pve-updates',
            icon: Icons.dns_rounded,
            title: 'Proxmox',
            subtitle: 'Knoten-Updates, alle Knoten patchen, Zeitplan, Shell, Konsole',
            onTap: () => PvePage.open(context)),
        _area(caps, 'nas',
            icon: Icons.storage_rounded,
            title: 'NAS',
            subtitle: 'Synology & Co.: Zustand, Platten, DSM- und Paket-Updates',
            onTap: () => NasPage.open(context)),
        _area(caps, 'backup-jobs',
            icon: Icons.backup_outlined,
            title: 'Backup',
            subtitle: 'Aufträge, jetzt sichern, Verlauf und Prüfen',
            onTap: () => BackupsPage.open(context)),
        if (s.isAdmin)
          _area(caps, 'server-update',
              icon: Icons.rocket_launch_outlined,
              title: 'RIMPERIO-Server',
              subtitle: 'Version und Update des Servers',
              onTap: () => ServerPage.open(context)),
        _area(caps, 'snmp-status',
            icon: Icons.router_outlined, title: 'SNMP-Geräte', onTap: () => SnmpPage.open(context)),
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
          subtitle: const Text('Freigaben, Fehlschläge, Alarme, kritische Logs — im Hintergrund etwa alle 15 min'),
          value: _notify,
          onChanged: _toggleNotify,
        ),
        if (_notify)
          ListTile(
            leading: const Icon(Icons.notification_add_outlined),
            title: const Text('Benachrichtigung testen'),
            subtitle: const Text('Zeigt eine Test-Meldung und prüft die Abfrage beim Server'),
            onTap: () async {
              final msg = await Notifications.test();
              if (mounted) showInfo(context, msg);
            },
          ),
        const SectionHeader('App'),
        ValueListenableBuilder<AppRelease?>(
          valueListenable: AppUpdate.available,
          builder: (context, update, _) => ListTile(
            leading: Badge(
              isLabelVisible: update != null,
              child: Icon(Icons.system_update_rounded, color: update != null ? cs.primary : null),
            ),
            title: const Text('App-Update'),
            subtitle: Text(update != null
                ? 'Neue Version ${update.version} – jetzt installieren'
                : 'Version ${_app?.label ?? '–'} · auf GitHub nach Updates suchen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await AppUpdatePage.open(context);
              if (mounted) setState(() {});
            },
          ),
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
            'App ${_app?.label ?? '–'} · Server ${s.bootstrap?['server']?['version'] ?? '–'} · '
            'API-Level ${s.bootstrap?['server']?['api_level'] ?? '–'}',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline, fontSize: 12),
          ),
        ),
      ]),
    ]);
  }
}
