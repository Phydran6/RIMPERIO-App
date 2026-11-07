// ---------------------------------------------------------------------------
// Datei:        lib/ui/widgets.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Gemeinsame Bausteine: Lade-/Fehler-/Leer-Zustand, Zeitangaben,
//               Kacheln, Abzeichen, Hinweis bei unverschlüsselter Verbindung.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import 'theme.dart';

/// Lädt einmal, zeigt Laden/Fehler/Ergebnis und kann per Ziehen neu laden.
class AsyncView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  const AsyncView({super.key, required this.load, required this.builder});

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => _loading = _data == null);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_data != null) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return ErrorState(error: _error, onRetry: reload);
    }
    return widget.builder(context, _data as T, reload);
  }
}

class ErrorState extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  const ErrorState({super.key, this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: cs.outline),
          const SizedBox(height: 16),
          Text('Laden fehlgeschlagen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${error ?? ''}', textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  const EmptyState({super.key, required this.icon, required this.title, this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: cs.outline),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        if (text != null) ...[
          const SizedBox(height: 6),
          Text(text!, textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
        ],
      ]),
    );
  }
}

void showError(BuildContext context, Object e) {
  final msg = e is ApiException ? e.message : '$e';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void showInfo(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Server-Zeit (UTC, teils ohne „Z“) → lokale Zeit.
DateTime? parseServerTime(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final hasZone = iso.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(iso);
  return DateTime.tryParse(hasZone ? iso : '${iso}Z')?.toLocal();
}

String relativeTime(String? iso) {
  final t = parseServerTime(iso);
  if (t == null) return '–';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'gerade eben';
  if (d.inMinutes < 60) return 'vor ${d.inMinutes} min';
  if (d.inHours < 24) return 'vor ${d.inHours} h';
  if (d.inDays < 7) return 'vor ${d.inDays} ${d.inDays == 1 ? 'Tag' : 'Tagen'}';
  return DateFormat('dd.MM.yyyy').format(t);
}

String clockTime(String? iso) {
  final t = parseServerTime(iso);
  if (t == null) return '–';
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return DateFormat(sameDay ? 'HH:mm:ss' : 'dd.MM. HH:mm').format(t);
}

String fullTime(String? iso) {
  final t = parseServerTime(iso);
  return t == null ? '–' : DateFormat('dd.MM.yyyy HH:mm:ss').format(t);
}

final _num = NumberFormat.decimalPattern('de');
String fmtInt(Object? n) => n is num ? _num.format(n) : '–';

class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;
  const StatTile(
      {super.key, required this.icon, required this.label, required this.value, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(height: 12),
            Text(value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class SeverityDot extends StatelessWidget {
  final String? level;
  const SeverityDot(this.level, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Severity.color(level, Theme.of(context).colorScheme);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: c.withValues(alpha: .15), shape: BoxShape.circle),
      child: Icon(Severity.icon(level), color: c, size: 20),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeader(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Dauerhafter Hinweis, solange die Verbindung nicht verschlüsselt ist.
class InsecureBanner extends StatelessWidget {
  final VoidCallback? onTap;
  const InsecureBanner({super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF5A1E1E),
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.lock_open_rounded, color: Color(0xFFFFB4B4), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text('Unverschlüsselt (HTTP) — Passwort und Token sind mitlesbar.',
                  style: TextStyle(color: Color(0xFFFFDADA), fontSize: 13)),
            ),
          ]),
        ),
      ),
    );
  }
}

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 120});
  @override
  Widget build(BuildContext context) => Image.asset('assets/icon/rimperio_logo.png',
      width: size, height: size, filterQuality: FilterQuality.medium, semanticLabel: 'RIMPERIO');
}

extension ThemeX on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

Color severityColor(BuildContext c, String? level) => Severity.color(level, c.cs);
