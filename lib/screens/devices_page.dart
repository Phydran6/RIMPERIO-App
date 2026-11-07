// ---------------------------------------------------------------------------
// Datei:        lib/screens/devices_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Geräte mit Online-Zustand (/api/app/devices). Antippen zeigt
//               die Logs des Geräts.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'logs_page.dart';

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
                    trailing: const Icon(Icons.chevron_right),
                    onTap: e['host'] == null ? null : () => LogsPage.openForHost(context, e['host'] as String),
                  );
                },
              ),
          ]),
        );
      },
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
