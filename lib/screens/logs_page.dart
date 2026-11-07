// ---------------------------------------------------------------------------
// Datei:        lib/screens/logs_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Logs — endlose Liste (Cursor: before_id), Filter nach
//               Schweregrad, Gerät und Suchtext, „Live“ hängt neue Zeilen per
//               /api/app/logs/tail an. Antippen öffnet die zerlegte Zeile.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class LogsPage extends StatefulWidget {
  final String? hostname;
  const LogsPage({super.key, this.hostname});

  static Future<void> openForHost(BuildContext context, String host) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => Scaffold(body: LogsPage(hostname: host))));

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _items = <Map<String, dynamic>>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  String? _minSeverity;
  String? _host;
  int? _nextBefore;
  int? _newest;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  bool _live = false;
  Timer? _liveTimer;
  bool _searching = false;

  static const _severities = ['critical', 'error', 'warning', 'notice', 'info'];

  @override
  void initState() {
    super.initState();
    _host = widget.hostname;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Map<String, Object?> get _filters => {
        'min_severity': _minSeverity,
        'hostname': _host,
        'search': _search.text.trim().isEmpty ? null : _search.text.trim(),
      };

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _nextBefore = null;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final d = await context.session.api!.getJson('/api/app/logs', {
        ..._filters,
        'limit': 50,
        'before_id': _nextBefore,
      });
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _nextBefore = d['next_before_id'] as int?;
        _hasMore = d['has_more'] == true;
        _newest ??= d['newest_id'] as int?;
        if (_items.isNotEmpty) _newest = _items.first['id'] as int;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleLive() {
    setState(() => _live = !_live);
    _liveTimer?.cancel();
    if (_live) {
      HapticFeedback.selectionClick();
      _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tail());
      _tail();
    }
  }

  Future<void> _tail() async {
    final since = _newest;
    if (since == null) return _reload();
    try {
      final f = _filters..remove('search');
      final d = await context.session.api!.getJson('/api/app/logs/tail', {...f, 'since_id': since});
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted || items.isEmpty) return;
      setState(() {
        _items.insertAll(0, items.reversed); // Server liefert älteste zuerst
        _newest = d['newest_id'] as int?;
        if (_items.length > 1000) _items.removeRange(1000, _items.length);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            title: _searching
                ? TextField(
                    controller: _search,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                        hintText: 'In Logs suchen …', border: InputBorder.none, filled: false),
                    onSubmitted: (_) => _reload(),
                  )
                : Text(_host ?? 'Logs'),
            actions: [
              IconButton(
                tooltip: 'Suchen',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() => _searching = !_searching);
                  if (!_searching && _search.text.isNotEmpty) {
                    _search.clear();
                    _reload();
                  }
                },
              ),
              IconButton(
                tooltip: _live ? 'Live aus' : 'Live',
                icon: Icon(_live ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded,
                    color: _live ? const Color(0xFF30A46C) : null),
                onPressed: _toggleLive,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    if (_host != null && widget.hostname == null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(_host!),
                          onDeleted: () {
                            setState(() => _host = null);
                            _reload();
                          },
                        ),
                      ),
                    for (final l in _severities)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text('ab ${Severity.label(l)}'),
                          selected: _minSeverity == l,
                          avatar: _minSeverity == l
                              ? null
                              : Icon(Icons.circle, size: 10, color: Severity.color(l, cs)),
                          onSelected: (on) {
                            setState(() => _minSeverity = on ? l : null);
                            _reload();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_items.isEmpty && _error != null)
            SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: _error, onRetry: _reload))
          else if (_items.isEmpty && !_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.inbox_outlined, title: 'Keine Logs', text: 'Für diese Filter gibt es nichts.'),
            )
          else
            SliverList.separated(
              itemCount: _items.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
              itemBuilder: (context, i) {
                if (i == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : _hasMore
                              ? const SizedBox.shrink()
                              : Text('Ende der Liste', style: TextStyle(color: cs.outline)),
                    ),
                  );
                }
                return _LogTile(
                  item: _items[i],
                  onHost: widget.hostname == null
                      ? (h) {
                          setState(() => _host = h);
                          _reload();
                        }
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final void Function(String host)? onHost;
  const _LogTile({required this.item, this.onHost});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final badges = (item['badges'] as List?)?.cast<Object?>() ?? const [];
    final text = (item['summary'] ?? item['message'] ?? '') as String;
    return ListTile(
      leading: SeverityDot(item['level'] as String?),
      title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(clockTime(item['ts'] as String?), style: TextStyle(color: cs.outline, fontSize: 12)),
          if (item['host'] != null)
            GestureDetector(
              onLongPress: onHost == null ? null : () => onHost!(item['host'] as String),
              child: Text('· ${item['host']}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          if ((item['app'] ?? item['source']) != null)
            Text('· ${item['app'] ?? item['source']}', style: TextStyle(color: cs.outline, fontSize: 12)),
          for (final b in badges.take(3)) Pill(_badgeText(b), color: cs.primary),
        ]),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LogDetailPage(id: item['id'] as int, preview: item)),
      ),
    );
  }

  static String _badgeText(Object? b) {
    if (b is Map) return '${b['label'] ?? b['key'] ?? ''}${b['value'] != null ? ': ${b['value']}' : ''}';
    return '$b';
  }
}

class LogDetailPage extends StatelessWidget {
  final int id;
  final Map<String, dynamic> preview;
  const LogDetailPage({super.key, required this.id, required this.preview});

  @override
  Widget build(BuildContext context) {
    final api = context.session.api!;
    return Scaffold(
      appBar: AppBar(title: Text(Severity.label(preview['level'] as String?))),
      body: AsyncView<Map<String, dynamic>>(
        load: () => api.getJson('/api/app/logs/$id'),
        builder: (context, d, reload) {
          final cs = context.cs;
          final parsed = (d['parsed'] as Map?)?.cast<String, dynamic>() ?? const {};
          final meta = (parsed['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
          final fields = <(String, Object?)>[
            ('Zeit', fullTime(d['ts'] as String?)),
            ('Gerät', d['host']),
            ('IP', d['ip']),
            ('Quelle', d['source']),
            ('Facility', d['facility']),
            for (final e in meta.entries)
              if (e.value != null && '${e.value}'.isNotEmpty) (e.key, e.value),
          ];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SeverityDot(d['level'] as String?),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      (parsed['summary'] ?? d['message'] ?? '') as String,
                      style: context.tt.bodyLarge,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                for (final (k, v) in fields)
                  if (v != null && '$v'.isNotEmpty)
                    ListTile(
                      dense: true,
                      title: Text(k, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      subtitle: SelectableText('$v', style: TextStyle(color: cs.onSurface, fontSize: 14)),
                    ),
              ]),
            ),
            if (d['raw'] != null) ...[
              const SectionHeader('Rohzeile'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText('${d['raw']}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${d['raw']}'));
                    showInfo(context, 'Rohzeile kopiert.');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Kopieren'),
                ),
              ),
            ],
          ]);
        },
      ),
    );
  }
}
