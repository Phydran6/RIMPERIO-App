// ---------------------------------------------------------------------------
// Datei:        lib/screens/dashboard_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Startbildschirm — Logs heute, Probleme, Geräte, offene
//               Freigaben und die Verteilung nach Schweregrad.
//               Quellen: /api/app/summary, /api/app/patching/summary.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'patches_page.dart';

class DashboardPage extends StatelessWidget {
  final void Function(int tab) onOpenTab;
  const DashboardPage({super.key, required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final caps = (s.bootstrap?['server']?['capabilities'] as List?)?.cast<String>() ?? const [];
    final hasPatches = caps.contains('patch-approvals');

    return AsyncView<(Map<String, dynamic>, Map<String, dynamic>?)>(
      load: () async {
        final summary = await s.api!.getJson('/api/app/summary');
        Map<String, dynamic>? patch;
        if (hasPatches) {
          try {
            patch = await s.api!.getJson('/api/app/patching/summary');
          } catch (_) {}
        }
        return (summary, patch);
      },
      builder: (context, data, reload) {
        final (sum, patch) = data;
        final dev = (sum['devices'] as Map?) ?? const {};
        final byLevel = ((sum['by_level_today'] as Map?) ?? const {}).cast<String, dynamic>();
        final problems = sum['problems_today'] as int? ?? 0;
        final offline = dev['offline'] as int? ?? 0;
        final approvals = patch?['needs_approval'] as int? ?? 0;
        final failedRuns = patch?['runs_failed_7d'] as int? ?? 0;

        return RefreshIndicator(
          onRefresh: reload,
          child: CustomScrollView(slivers: [
            SliverAppBar.large(
              title: Text(s.serverName),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Tooltip(
                    message: s.isSecure ? 'Verschlüsselt (HTTPS)' : 'Unverschlüsselt (HTTP)',
                    child: Icon(s.isSecure ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: s.isSecure ? const Color(0xFF30A46C) : const Color(0xFFF2555A)),
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [
                  StatTile(
                    icon: Icons.receipt_long_rounded,
                    label: 'Logs heute',
                    value: fmtInt(sum['logs_today']),
                    onTap: () => onOpenTab(1),
                  ),
                  StatTile(
                    icon: Icons.error_outline_rounded,
                    label: 'Probleme heute',
                    value: fmtInt(problems),
                    color: problems > 0 ? const Color(0xFFF2555A) : const Color(0xFF30A46C),
                    onTap: () => onOpenTab(1),
                  ),
                  StatTile(
                    icon: Icons.devices_rounded,
                    label: 'Geräte online',
                    value: '${dev['online'] ?? 0} / ${dev['total'] ?? 0}',
                    color: offline > 0 ? const Color(0xFFF5A524) : const Color(0xFF30A46C),
                    onTap: () => onOpenTab(2),
                  ),
                  if (hasPatches)
                    StatTile(
                      icon: Icons.system_update_alt_rounded,
                      label: 'Updates freigeben',
                      value: fmtInt(approvals),
                      color: approvals > 0 ? RimTheme.gold : const Color(0xFF30A46C),
                      onTap: () => PatchesPage.open(context),
                    )
                  else
                    StatTile(
                      icon: Icons.storage_rounded,
                      label: 'Logs gesamt',
                      value: fmtInt(sum['logs_total']),
                    ),
                ],
              ),
            ),
            if (failedRuns > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Card(
                    color: const Color(0xFF5A1E1E),
                    child: ListTile(
                      leading: const Icon(Icons.report_rounded, color: Color(0xFFFFB4B4)),
                      title: Text('$failedRuns fehlgeschlagene Update-Läufe (7 Tage)',
                          style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                      onTap: () => PatchesPage.open(context, initialTab: 1),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SectionHeader('Heute nach Schweregrad')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _LevelBars(byLevel: byLevel),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Text(
                  'Stand ${clockTime(sum['generated_at'] as String?)} · '
                  '${fmtInt(sum['logs_total'])} Logs insgesamt · '
                  'Server ${s.bootstrap?['server']?['version'] ?? ''}',
                  style: TextStyle(color: context.cs.outline, fontSize: 12),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _LevelBars extends StatelessWidget {
  final Map<String, dynamic> byLevel;
  const _LevelBars({required this.byLevel});

  static const _order = ['emergency', 'alert', 'critical', 'error', 'warning', 'notice', 'info', 'debug'];

  @override
  Widget build(BuildContext context) {
    final rows = _order.where((l) => (byLevel[l] as num? ?? 0) > 0).toList();
    if (rows.isEmpty) {
      return Text('Heute noch keine Logs.', style: TextStyle(color: context.cs.outline));
    }
    final max = rows.map((l) => (byLevel[l] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final l in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 72, child: Text(Severity.label(l), style: const TextStyle(fontSize: 13))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (byLevel[l] as num).toDouble() / max,
                    minHeight: 10,
                    color: severityColor(context, l),
                    backgroundColor: context.cs.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(fmtInt(byLevel[l]),
                    textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
      ],
    );
  }
}
