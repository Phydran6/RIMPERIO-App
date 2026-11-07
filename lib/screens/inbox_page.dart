// ---------------------------------------------------------------------------
// Datei:        lib/screens/inbox_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Meldungseingang (/api/app/notifications) — Freigaben,
//               Fehlschläge, Alarme. Wischen markiert als gelesen.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'patches_page.dart';

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
                    trailing: read
                        ? null
                        : Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: context.cs.primary, shape: BoxShape.circle)),
                    onTap: () {
                      if (!read) _markRead([n['id'] as int]);
                      if (n['category'] == 'patch') PatchesPage.open(context);
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
