// ---------------------------------------------------------------------------
// Datei:        lib/screens/devices_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
//
// Beschreibung: Geräte mit Online-Zustand (/api/app/devices). Antippen zeigt,
//               was mit dem Gerät geht: Logs, und bei Rechnern mit
//               RIMPERIO-Agent Fernzugriff — Konsole (Linux als „rimperio“,
//               Windows PowerShell), RDP, Updates.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'console_page.dart';
import 'logs_page.dart';
import 'patches_page.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _onlyOffline = false;
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return AsyncView<Map<String, dynamic>>(
      key: _key,
      load: () => api.getJson('/api/app/devices', {'limit': 500, 'only_offline': _onlyOffline}),
      builder: (context, d, reload) {
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        final online = items.where((e) => e['online'] == true).length;
        return RefreshIndicator(
          onRefresh: reload,
          child: CustomScrollView(slivers: [
            SliverAppBar.medium(
              title: const Text('Geräte'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilterChip(
                    label: const Text('nur offline'),
                    selected: _onlyOffline,
                    onSelected: (v) {
                      setState(() => _onlyOffline = v);
                      _key.currentState?.reload();
                    },
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _onlyOffline ? '${items.length} offline' : '$online von ${items.length} online',
                  style: TextStyle(color: context.cs.onSurfaceVariant),
                ),
              ),
            ),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.devices_other_outlined, title: 'Keine Geräte'),
              )
            else
              SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final e = items[i];
                  final on = e['online'] == true;
                  final c = on ? const Color(0xFF30A46C) : const Color(0xFFF2555A);
                  return ListTile(
                    leading: Stack(clipBehavior: Clip.none, children: [
                      CircleAvatar(
                        backgroundColor: context.cs.surfaceContainerHighest,
                        child: Icon(_icon(e['type'] as String?), color: context.cs.onSurfaceVariant),
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.cs.surface, width: 2),
                          ),
                        ),
                      ),
                    ]),
                    title: Text('${e['host'] ?? e['ip'] ?? '–'}'),
                    subtitle: Text([
                      if (e['ip'] != null) e['ip'],
                      if (e['type'] != null) e['type'],
                      on ? 'online' : 'zuletzt ${relativeTime(e['last_seen'] as String?)}',
                    ].join(' · ')),
                    trailing: e['agent_uid'] != null
                        ? Icon(Icons.settings_remote_rounded, color: context.cs.primary)
                        : const Icon(Icons.chevron_right),
                    onTap: e['host'] == null ? null : () => _actions(context, e),
                  );
                },
              ),
          ]),
        );
      },
    );
  }

  void _actions(BuildContext context, Map<String, dynamic> e) {
    final s = context.session;
    final host = e['host'] as String;
    final uid = e['agent_uid'] as String?;
    final windows = '${e['platform'] ?? ''}'.toLowerCase().startsWith('win');
    final remote = uid != null && s.isAdmin && s.hasCapability('remote-console');
    final online = e['rmm_online'] == true;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(host, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([if (e['os'] != null) e['os'], if (e['ip'] != null) e['ip']].join(' · ')),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Logs'),
            onTap: () {
              Navigator.pop(ctx);
              LogsPage.openForHost(context, host);
            },
          ),
          if (remote) ...[
            ListTile(
              leading: const Icon(Icons.terminal_rounded),
              title: Text(windows ? 'PowerShell' : 'Shell (als rimperio)'),
              subtitle: online ? null : const Text('Agent gerade offline – Befehle warten, bis er sich meldet'),
              onTap: () {
                Navigator.pop(ctx);
                AgentConsolePage.open(context, uid: uid, host: host, windows: windows);
              },
            ),
            if (windows && s.hasCapability('rdp')) ...[
              ListTile(
                leading: const Icon(Icons.desktop_windows_outlined),
                title: const Text('Remotedesktop (RDP)'),
                onTap: () {
                  Navigator.pop(ctx);
                  openRdp(context, uid, host);
                },
              ),
              ListTile(
                leading: const Icon(Icons.power_settings_new_rounded),
                title: const Text('RDP auf dem Rechner einschalten'),
                onTap: () {
                  Navigator.pop(ctx);
                  enableRdp(context, uid, host);
                },
              ),
            ],
            if (s.hasCapability('patch-installable'))
              ListTile(
                leading: const Icon(Icons.system_update_alt_rounded),
                title: const Text('Updates'),
                onTap: () {
                  Navigator.pop(ctx);
                  PatchesPage.open(context, initialTab: 1);
                },
              ),
          ],
        ]),
      ),
    );
  }

  static IconData _icon(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('windows') || t.contains('workstation') || t.contains('pc')) return Icons.computer_rounded;
    if (t.contains('linux') || t.contains('server')) return Icons.dns_rounded;
    if (t.contains('switch') || t.contains('router') || t.contains('fritz') || t.contains('network')) {
      return Icons.router_rounded;
    }
    if (t.contains('firewall')) return Icons.shield_rounded;
    return Icons.devices_other_rounded;
  }
}
