// ---------------------------------------------------------------------------
// Datei:        lib/screens/inbox_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      0.2.0
//
// Beschreibung: Meldungseingang (/api/app/notifications) — Freigaben,
//               Fehlschläge, Alarme. Wischen markiert als gelesen.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'patches_page.dart';
import 'server_page.dart';

class InboxPage extends StatefulWidget {
  final void Function(int unread)? onUnreadChanged;
  const InboxPage({super.key, this.onUnreadChanged});
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<void> _markRead(List<int> ids) async {
    try {
      await context.session.api!.postJson('/api/app/notifications/read', {'ids': ids});
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Freigabe eines kritischen RIMPERIO-Updates (Autopilot) direkt aus der Meldung.
  Future<void> _decideUpdate(Map<String, dynamic> n) async {
    final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final version = '${data['version'] ?? ''}';
    if (version.isEmpty) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('RIMPERIO $version freigeben?'),
        content: Text('${n['body'] ?? ''}\n\nNach der Freigabe startet das Update sofort – mit Datenbank-Sicherung '
            'vorher und automatischem Rückfall, falls der Server danach nicht antwortet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('Überspringen')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Später')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'approve'), child: const Text('Freigeben')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      await context.session.api!.postJson('/api/app/server/autopilot', {'version': version, 'decision': choice});
      if (!mounted) return;
      showInfo(context, choice == 'approve' ? 'Freigegeben – das Update startet jetzt.' : 'Version übersprungen.');
      await _markRead([n['id'] as int]);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return AsyncView<Map<String, dynamic>>(
      key: _key,
      load: () async {
        final d = await api.getJson('/api/app/notifications', {'limit': 100});
        widget.onUnreadChanged?.call((d['unread'] as int?) ?? 0);
        return d;
      },
      builder: (context, d, reload) {
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        final unread = (d['unread'] as int?) ?? 0;
        return RefreshIndicator(
          onRefresh: reload,
          child: CustomScrollView(slivers: [
            SliverAppBar.medium(
              title: const Text('Meldungen'),
              actions: [
                if (unread > 0)
                  TextButton(
                    onPressed: () => _markRead(const []),
                    child: const Text('Alle gelesen'),
                  ),
              ],
            ),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Keine Meldungen',
                    text: 'Freigaben und Alarme erscheinen hier.'),
              )
            else
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final n = items[i];
                  final read = n['read'] == true;
                  final tile = ListTile(
                    leading: SeverityDot(n['level'] as String?),
                    title: Text('${n['title']}',
                        style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w700)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((n['body'] as String?)?.isNotEmpty ?? false)
                        Text('${n['body']}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(relativeTime(n['created_at'] as String?),
                          style: TextStyle(color: context.cs.outline, fontSize: 12)),
                    ]),
                    trailing: n['action'] == 'rimperio_update' && n['resolved'] != true
                        ? const Icon(Icons.verified_user_outlined)
                        : read
                        ? null
                        : Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: context.cs.primary, shape: BoxShape.circle)),
                    onTap: () {
                      if (n['action'] == 'rimperio_update' && n['resolved'] != true && context.session.isAdmin) {
                        _decideUpdate(n);
                        return;
                      }
                      if (!read) _markRead([n['id'] as int]);
                      if (n['category'] == 'patch') PatchesPage.open(context);
                      if (n['action'] == 'rimperio_update') {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServerPage()));
                      }
                    },
                  );
                  if (read) return tile;
                  return Dismissible(
                    key: ValueKey(n['id']),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      await _markRead([n['id'] as int]);
                      return false;
                    },
                    background: Container(
                      color: context.cs.primaryContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: Icon(Icons.mark_email_read_outlined, color: context.cs.onPrimaryContainer),
                    ),
                    child: tile,
                  );
                },
              ),
          ]),
        );
      },
    );
  }
}
