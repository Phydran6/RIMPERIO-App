// ---------------------------------------------------------------------------
// Datei:        lib/screens/snmp_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: SNMP-Geräte mit Zustand und aktuellen Problemen (/api/app/snmp).
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';

class SnmpPage extends StatelessWidget {
  const SnmpPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SnmpPage()));

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return Scaffold(
      appBar: AppBar(title: const Text('SNMP-Geräte')),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => ((await api.getJson('/api/app/snmp'))['items'] as List).cast<Map<String, dynamic>>(),
        builder: (context, items, reload) => RefreshIndicator(
          onRefresh: reload,
          child: items.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.router_outlined, title: 'Keine SNMP-Geräte')])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final d = items[i];
                    final problems = (d['problems'] as List).cast<Map<String, dynamic>>();
                    final status = d['status'] as String?;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: Column(children: [
                          ListTile(
                            leading: SeverityDot(_level(status)),
                            title: Text('${d['name']}'),
                            subtitle: Text([d['host'], d['site']].whereType<Object>().join(' · ')),
                            trailing: Text(relativeTime(d['last_ok_at'] as String?),
                                style: TextStyle(color: context.cs.outline, fontSize: 12)),
                          ),
                          for (final p in problems)
                            ListTile(
                              dense: true,
                              leading: Icon(Icons.subdirectory_arrow_right_rounded,
                                  color: severityColor(context, p['status'] as String?)),
                              title: Text('${p['label']}'),
                              trailing: Text(
                                '${p['text'] ?? p['value'] ?? ''}${p['unit'] != null ? ' ${p['unit']}' : ''}',
                                style: TextStyle(
                                    color: severityColor(context, p['status'] as String?),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  static String _level(String? s) => switch (s) {
        'ok' || 'up' => 'info',
        'warning' => 'warning',
        'critical' || 'down' || 'unreachable' => 'critical',
        _ => 'notice',
      };
}
