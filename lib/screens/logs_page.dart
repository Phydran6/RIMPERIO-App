// ---------------------------------------------------------------------------
// Datei:        lib/screens/logs_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.24.21.00.00
//
// Beschreibung: Logs — endlose Liste (Cursor: before_id). Zwei Arten:
//                 * Ansehen: nur Warnungen und Schlimmeres. Info und Hinweis
//                   kommen hier nicht vor — davon gibt es viel zu viele.
//                   Filter nach Stufe (Kritisch / Fehler / Warnung, mehrere
//                   wählbar), Gerät, „Live“.
//                 * Suchen: alle Stufen inkl. Info/Hinweis/Debug, Suchtext,
//                   Gerät, Zeitraum — wer Info sucht, sucht ausdrücklich.
//               Antippen öffnet die Zeile im Klartext (Was ist passiert? Was
//               tun?), mit „Diese Meldung sperren“ und „KI erklärt“.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

enum LogMode { view, search }

/// Stufen-Gruppen, wie sie in der App gewählt werden (Server-Stufen in `levels`).
class _LevelGroup {
  final String key;
  final String label;
  final String levels;
  const _LevelGroup(this.key, this.label, this.levels);
}

const _problemGroups = [
  _LevelGroup('critical', 'Kritisch', 'critical,alert,emergency'),
  _LevelGroup('error', 'Fehler', 'error'),
  _LevelGroup('warning', 'Warnung', 'warning'),
];
const _lowGroups = [
  _LevelGroup('notice', 'Hinweis', 'notice'),
  _LevelGroup('info', 'Info', 'info'),
  _LevelGroup('debug', 'Debug', 'debug'),
];

/// Stufen, die beim Ansehen nie auftauchen – nur über die Suche.
const lowLevels = {'debug', 'info', 'informational', 'notice'};

/// Ansehen: Info/Hinweis/Debug weg – auch wenn ein älterer Server
/// `exclude_low` nicht kennt und sie trotzdem schickt.
List<Map<String, dynamic>> withoutLow(List<Map<String, dynamic>> items) =>
    items.where((i) => !lowLevels.contains('${i['level'] ?? ''}'.toLowerCase())).toList();

class LogsPage extends StatefulWidget {
  final String? hostname;
  final LogMode mode;
  final String? initialSearch;
  const LogsPage({super.key, this.hostname, this.mode = LogMode.view, this.initialSearch});

  static Future<void> open(BuildContext context, {LogMode mode = LogMode.view, String? host, String? search}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(body: LogsPage(mode: mode, hostname: host, initialSearch: search))));

  static Future<void> openForHost(BuildContext context, String host) => open(context, host: host);

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _items = <Map<String, dynamic>>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _groups = <String>{};
  String? _host;
  int? _sinceHours;
  int? _nextBefore;
  int? _newest;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  bool _live = false;
  Timer? _liveTimer;

  bool get _isSearch => widget.mode == LogMode.search;

  @override
  void initState() {
    super.initState();
    _host = widget.hostname;
    _search.text = widget.initialSearch ?? '';
    if (_isSearch) _sinceHours = 24;
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

  String? get _levels {
    if (_groups.isEmpty) return null;
    return [..._problemGroups, ..._lowGroups].where((g) => _groups.contains(g.key)).map((g) => g.levels).join(',');
  }

  Map<String, Object?> get _filters => {
        'hostname': _host,
        'levels': _levels,
        // Ansehen: Info/Hinweis/Debug grundsätzlich weg.
        'exclude_low': !_isSearch && _groups.isEmpty ? true : null,
        'search': _search.text.trim().isEmpty ? null : _search.text.trim(),
        'since_hours': _sinceHours,
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
    var refill = false;
    try {
      final d = await context.session.api!.getJson('/api/app/logs', {
        ..._filters,
        'limit': 50,
        'before_id': _nextBefore,
      });
      var items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!_isSearch && _groups.isEmpty) items = withoutLow(items);
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _nextBefore = d['next_before_id'] as int?;
        _hasMore = d['has_more'] == true;
        _newest ??= d['newest_id'] as int?;
        if (_items.isNotEmpty) _newest = _items.first['id'] as int;
        _error = null;
      });
      // Bleibt die Liste nach dem Aussortieren zu kurz zum Scrollen, gleich
      // die nächste Seite holen.
      refill = _hasMore && _items.length < 20;
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (refill && mounted) await _loadMore();
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
      final f = Map<String, Object?>.from(_filters)
        ..remove('search')
        ..remove('since_hours')
        ..remove('levels');
      final d = await context.session.api!.getJson('/api/app/logs/tail', {...f, 'since_id': since});
      var items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (_groups.isEmpty) items = withoutLow(items);
      if (_groups.isNotEmpty) {
        // /tail kennt nur "ab Stufe" – die Auswahl hier filtern.
        final wanted = _levels!.split(',').toSet();
        items = items.where((i) => wanted.contains('${i['level']}'.toLowerCase())).toList();
      }
      if (!mounted) return;
      setState(() {
        _items.insertAll(0, items.reversed); // Server liefert älteste zuerst
        _newest = d['newest_id'] as int?;
        if (_items.length > 1000) _items.removeRange(1000, _items.length);
      });
    } catch (_) {}
  }

  Future<void> _pickHost() async {
    final hosts = ((context.session.bootstrap?['filters']?['hostnames'] as List?) ?? const []).cast<String>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (ctx, scroll) => ListView(controller: scroll, children: [
          ListTile(leading: const Icon(Icons.all_inclusive), title: const Text('Alle Geräte'), onTap: () => Navigator.pop(ctx, '')),
          for (final h in hosts) ListTile(leading: const Icon(Icons.dns_outlined), title: Text(h), onTap: () => Navigator.pop(ctx, h)),
        ]),
      ),
    );
    if (picked == null) return;
    setState(() => _host = picked.isEmpty ? null : picked);
    _reload();
  }

  Widget _chip(_LevelGroup g) {
    final cs = context.cs;
    final on = _groups.contains(g.key);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(g.label),
        selected: on,
        avatar: on ? null : Icon(Icons.circle, size: 10, color: Severity.color(g.key, cs)),
        onSelected: (v) {
          setState(() => v ? _groups.add(g.key) : _groups.remove(g.key));
          _reload();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final title = _isSearch ? 'Logs suchen' : (_host ?? 'Logs ansehen');
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(title),
            actions: [
              if (widget.hostname == null)
                IconButton(
                  tooltip: 'Gerät wählen',
                  icon: Icon(_host == null ? Icons.dns_outlined : Icons.dns_rounded),
                  onPressed: _pickHost,
                ),
              if (!_isSearch)
                IconButton(
                  tooltip: 'Suchen (auch Info/Hinweis)',
                  icon: const Icon(Icons.search),
                  onPressed: () => LogsPage.open(context, mode: LogMode.search, host: _host),
                ),
              if (!_isSearch)
                IconButton(
                  tooltip: _live ? 'Live aus' : 'Live',
                  icon: Icon(_live ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded,
                      color: _live ? const Color(0xFF30A46C) : null),
                  onPressed: _toggleLive,
                ),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(_isSearch ? 168 : 52),
              child: Column(children: [
                if (_isSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: TextField(
                      controller: _search,
                      autofocus: widget.initialSearch == null,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Text in der Meldung …',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _search.clear();
                                  _reload();
                                }),
                      ),
                      onSubmitted: (_) => _reload(),
                    ),
                  ),
                if (_isSearch)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      children: [
                        for (final (h, label) in [(1, '1 h'), (24, '24 h'), (168, '7 Tage'), (720, '30 Tage'), (0, 'alles')])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: (_sinceHours ?? 0) == h,
                              onSelected: (_) {
                                setState(() => _sinceHours = h == 0 ? null : h);
                                _reload();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(
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
                      for (final g in _problemGroups) _chip(g),
                      if (_isSearch) for (final g in _lowGroups) _chip(g),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          if (!_isSearch && _groups.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text('Warnungen und Schlimmeres. Info und Hinweise über die Suche.',
                    style: TextStyle(color: cs.outline, fontSize: 12)),
              ),
            ),
          if (_items.isEmpty && _error != null)
            SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: _error, onRetry: _reload))
          else if (_items.isEmpty && !_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                  icon: _isSearch ? Icons.search_off_rounded : Icons.verified_rounded,
                  title: _isSearch ? 'Nichts gefunden' : 'Keine Probleme',
                  text: _isSearch ? 'Für diese Suche gibt es keine Zeilen.' : 'Keine Warnungen oder Fehler für diese Auswahl.'),
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
                return LogTile(
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

class LogTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final void Function(String host)? onHost;
  const LogTile({super.key, required this.item, this.onHost});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final badges = (item['badges'] as List?)?.cast<Object?>() ?? const [];
    final text = (item['summary'] ?? item['message'] ?? '') as String;
    final repeat = item['repeat'] as int?;
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
          if (item['category_label'] != null) Pill('${item['category_label']}', color: cs.tertiary),
          if (repeat != null && repeat > 1) Pill('×$repeat', color: const Color(0xFFF5A524)),
          if (item['has_hint'] == true) Icon(Icons.lightbulb_outline_rounded, size: 14, color: cs.primary),
          for (final b in badges.take(2)) Pill(_badgeText(b), color: cs.primary),
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

class LogDetailPage extends StatefulWidget {
  final int id;
  final Map<String, dynamic> preview;
  const LogDetailPage({super.key, required this.id, required this.preview});

  @override
  State<LogDetailPage> createState() => _LogDetailPageState();
}

class _LogDetailPageState extends State<LogDetailPage> {
  Map<String, dynamic>? _ai;
  bool _aiBusy = false;

  Future<void> _block(String level) async {
    final s = context.session;
    final scope = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Diese Meldung sperren'),
            subtitle: Text('Meldungen dieser Art (Zahlen, IPs, IDs egal) werden ab sofort nicht mehr gespeichert. '
                'Vorhandene gleiche Zeilen werden gelöscht.'),
          ),
          ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text('Nur von ${widget.preview['host'] ?? 'diesem Gerät'}'),
              onTap: () => Navigator.pop(ctx, 'host')),
          ListTile(
              leading: const Icon(Icons.public), title: const Text('Von allen Geräten'), onTap: () => Navigator.pop(ctx, 'all')),
          ListTile(
              leading: const Icon(Icons.timelapse_rounded),
              title: const Text('Nur kurz behalten (als Debug, 1 Tag)'),
              onTap: () => Navigator.pop(ctx, 'downgrade')),
        ]),
      ),
    );
    if (scope == null || !mounted) return;
    try {
      final r = await s.api!.postJson('/api/log-handling/rules/from-log', {
        'log_id': widget.id,
        'scope': scope == 'all' ? 'all' : 'host',
        'action': scope == 'downgrade' ? 'downgrade' : 'drop',
        'purge_existing': scope != 'downgrade',
      });
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showInfo(context, 'Gesperrt: ${r['name']}${(r['purged'] ?? 0) > 0 ? ' · ${r['purged']} Zeilen gelöscht' : ''}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _explain() async {
    setState(() => _aiBusy = true);
    try {
      final r = await context.session.api!.postJson('/api/log-handling/explain/${widget.id}', const {});
      if (!mounted) return;
      if (r['available'] == true) {
        setState(() => _ai = (r['answer'] as Map).cast<String, dynamic>());
      } else {
        showInfo(context, '${r['message'] ?? 'Keine KI eingerichtet.'}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final api = s.api!;
    final canHandle = s.hasCapability('log-handling');
    return Scaffold(
      appBar: AppBar(title: Text(Severity.label(widget.preview['level'] as String?))),
      body: AsyncView<Map<String, dynamic>>(
        load: () => api.getJson('/api/app/logs/${widget.id}'),
        builder: (context, d, reload) {
          final cs = context.cs;
          final parsed = (d['parsed'] as Map?)?.cast<String, dynamic>() ?? const {};
          final meta = (parsed['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
          final explain = (parsed['explain'] as Map?)?.cast<String, dynamic>() ?? const {};
          final level = '${d['level'] ?? ''}'.toLowerCase();
          final blockable = const ['info', 'informational', 'notice', 'debug', 'warning', 'warn'].contains(level);
          final extra = (d['extra'] as Map?)?.cast<String, dynamic>() ?? const {};
          final fields = <(String, Object?)>[
            ('Zeit', fullTime(d['ts'] as String?)),
            ('Gerät', d['host']),
            ('IP', d['ip']),
            ('Programm', d['source']),
            if ((extra['repeat'] ?? 1) is int && (extra['repeat'] ?? 1) > 1)
              ('Wiederholt', '${extra['repeat']}× (zuletzt ${clockTime(extra['repeat_last'] as String?)})'),
            for (final e in meta.entries)
              if (e.value != null && '${e.value}'.isNotEmpty && !const ['severity', 'app', 'host'].contains(e.key))
                (e.key, e.value),
          ];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SeverityDot(d['level'] as String?),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (parsed['category_label'] != null && parsed['category'] != 'other')
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Pill('${parsed['category_label']}', color: cs.tertiary),
                          ),
                        SelectableText(
                          (parsed['summary'] ?? d['message'] ?? '') as String,
                          style: context.tt.bodyLarge,
                        ),
                      ]),
                    ),
                  ]),
                  if (explain['hint'] != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${explain['hint']}')),
                      ]),
                    ),
                  ],
                  if (parsed['original'] != null && parsed['original'] != parsed['summary']) ...[
                    const SizedBox(height: 10),
                    Text('Original: ${parsed['original']}', style: TextStyle(color: cs.outline, fontSize: 12)),
                  ],
                ]),
              ),
            ),
            if (canHandle) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (s.isAdmin && blockable)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => _block(level),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('Diese Meldung sperren'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _aiBusy ? null : _explain,
                  icon: _aiBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('KI erklärt'),
                ),
              ]),
            ],
            if (_ai != null) ...[
              const SectionHeader('KI-Erklärung'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final (k, label) in [('was', 'Was'), ('bedeutung', 'Bedeutung'), ('tun', 'Tun')])
                      if (_ai![k] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: '${_ai![k]}'),
                          ])),
                        ),
                    if (_ai!['rauschen'] == true)
                      Text('Die KI hält das für Grundrauschen – sperren spart Platz.',
                          style: TextStyle(color: cs.outline, fontSize: 12)),
                  ]),
                ),
              ),
            ],
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
