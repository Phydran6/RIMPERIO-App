// ---------------------------------------------------------------------------
// Datei:        lib/screens/app_update_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.24.12.00.00
//
// Beschreibung: Mehr → App-Update. Installierte und neueste Version
//               (GitHub-Release), „Jetzt prüfen“, tägliche Prüfung an/aus und
//               — wenn es ein Update gibt — „Herunterladen und installieren“
//               mit Fortschritt. Android fragt vor dem Einspielen selbst noch
//               einmal nach. Aus dem Play Store installiert: Verweis auf Play;
//               iOS bzw. ohne Selbst-Update: Verweis aufs Release.
// ---------------------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_update.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class AppUpdatePage extends StatefulWidget {
  /// Nach dem Öffnen sofort bei GitHub nachsehen.
  final bool checkOnOpen;
  const AppUpdatePage({super.key, this.checkOnOpen = true});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppUpdatePage()));

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  InstalledApp? _app;
  AppRelease? _latest;
  SelfInstall _self = const SelfInstall();
  DateTime? _lastCheck;
  bool _auto = true;
  bool _checking = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final app = await AppUpdate.installed();
    final cached = await AppUpdate.cachedLatest();
    final last = await AppUpdate.lastCheck();
    final auto = await AppUpdate.autoEnabled();
    final self = await AppUpdate.selfInstall();
    if (!mounted) return;
    setState(() {
      _app = app;
      _latest = cached;
      _lastCheck = last;
      _auto = auto;
      _self = self;
    });
    // Aus dem Play Store: GitHub nur auf ausdrücklichen Wunsch („Jetzt prüfen“).
    if (widget.checkOnOpen && !app.fromPlayStore) await _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final latest = await AppUpdate.check();
      final last = await AppUpdate.lastCheck();
      final self = await AppUpdate.selfInstall();
      if (mounted) {
        setState(() {
          _latest = latest;
          _lastCheck = last;
          _self = self;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _setAuto(bool on) async {
    await AppUpdate.setAutoEnabled(on);
    if (mounted) setState(() => _auto = on);
  }

  Future<void> _install(AppRelease r) async {
    var self = await AppUpdate.selfInstall();
    if (!mounted) return;
    if (self.supported && !self.allowed) {
      final ok = await confirmDialog(
        context,
        'Installieren erlauben',
        'Android lässt RIMPERIO noch keine Updates installieren. In den Einstellungen '
            '„Dieser Quelle vertrauen“ bzw. „Aus dieser Quelle zulassen“ einschalten, '
            'dann zurück zur App – das Update startet danach hier.',
        action: 'Einstellungen öffnen',
      );
      if (!ok) return;
      await AppUpdate.openInstallSettings();
      // Zurück aus den Einstellungen? Erneut nachsehen.
      await _waitForResume();
      self = await AppUpdate.selfInstall();
      if (!mounted) return;
      setState(() => _self = self);
      if (!self.allowed) {
        showInfo(context, 'Noch nicht erlaubt – ohne die Freigabe geht das Update nicht.');
        return;
      }
    }
    await AppUpdate.downloadAndInstall(r);
  }

  /// Wartet, bis der Nutzer aus den Systemeinstellungen zurück ist.
  Future<void> _waitForResume() {
    final back = Completer<void>();
    var left = false;
    final l = AppLifecycleListener(
      onHide: () => left = true,
      onResume: () {
        if (left && !back.isCompleted) back.complete();
      },
    );
    return back.future.timeout(const Duration(minutes: 5), onTimeout: () {}).whenComplete(l.dispose);
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showInfo(context, 'Konnte $url nicht öffnen.');
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(bytes > 10 * 1024 * 1024 ? 0 : 1)} MB';

  String _source(InstalledApp a) {
    if (a.fromPlayStore) return 'Google Play Store';
    if (_self.supported) return 'APK aus dem GitHub-Release';
    return switch (a.installer) {
      null || '' => 'direkt installiert',
      final s => s,
    };
  }

  Widget _action(AppRelease r, InstallStatus st, bool newer) {
    final app = _app!;
    if (!newer) return const SizedBox.shrink();
    if (app.fromPlayStore) {
      return FilledButton.icon(
        onPressed: () => _openUrl('https://play.google.com/store/apps/details?id=$appPackageId'),
        icon: const Icon(Icons.shop_rounded),
        label: const Text('Im Play Store aktualisieren'),
      );
    }
    if (!_self.supported || r.apkUrl == null) {
      return FilledButton.icon(
        onPressed: () => _openUrl(r.pageUrl),
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Release auf GitHub öffnen'),
      );
    }
    final size = r.apkSize != null ? ' (${_mb(r.apkSize!)})' : '';
    return FilledButton.icon(
      onPressed: st.busy ? null : () => _install(r),
      icon: const Icon(Icons.system_update_rounded),
      label: Text(st.state == InstallState.failed ? 'Erneut versuchen$size' : 'Herunterladen und installieren$size'),
    );
  }

  Widget _progress(InstallStatus st) {
    final cs = context.cs;
    switch (st.state) {
      case InstallState.idle:
        return const SizedBox.shrink();
      case InstallState.downloading:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: st.progress),
          const SizedBox(height: 6),
          Text(
              st.total > 0
                  ? 'Lädt … ${_mb(st.received)} von ${_mb(st.total)}'
                  : 'Lädt … ${_mb(st.received)}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ]);
      case InstallState.installing:
        return Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Prüfsumme prüfen und an Android übergeben …', style: TextStyle(color: cs.onSurfaceVariant))),
        ]);
      case InstallState.confirm:
        return Text('Android fragt jetzt nach – „Aktualisieren“ bzw. „Installieren“ tippen. '
            'Danach startet RIMPERIO in der neuen Version.',
            style: TextStyle(color: cs.onSurfaceVariant));
      case InstallState.done:
        return const Text('Update installiert.', style: TextStyle(color: Color(0xFF30A46C)));
      case InstallState.failed:
        return Text(st.message ?? 'Fehlgeschlagen.', style: TextStyle(color: cs.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final app = _app;
    final r = _latest;
    final newer = app != null && r != null && isNewer(r, app);

    return Scaffold(
      appBar: AppBar(title: const Text('App-Update'), actions: [
        IconButton(
          tooltip: 'Jetzt prüfen',
          onPressed: _checking ? null : _check,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      body: app == null
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<InstallStatus>(
              valueListenable: AppUpdate.status,
              builder: (context, st, _) => ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: StatTile(icon: Icons.phone_android_rounded, label: 'Installiert', value: app.label)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: Icons.cloud_download_outlined,
                      label: 'Neueste',
                      value: r == null ? '–' : (r.code != null ? '${r.version} (${r.code})' : r.version),
                      color: r == null ? null : (newer ? RimTheme.gold : const Color(0xFF30A46C)),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_checking)
                  const LinearProgressIndicator()
                else if (_error != null)
                  Text('$_error', style: TextStyle(color: cs.error))
                else if (r != null)
                  Text(
                    newer ? 'Neue Version verfügbar.' : 'Die App ist aktuell.',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: newer ? RimTheme.gold : const Color(0xFF30A46C)),
                  ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (_lastCheck != null) 'Zuletzt geprüft: ${relativeTime(_lastCheck!.toIso8601String())}',
                    if (r?.published != null) 'Release vom ${DateFormat('dd.MM.yyyy HH:mm').format(r!.published!.toLocal())}',
                  ].join(' · '),
                  style: TextStyle(color: cs.outline, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (r != null) _action(r, st, newer),
                if (st.state != InstallState.idle) ...[
                  const SizedBox(height: 12),
                  _progress(st),
                ],
                if (newer && _self.supported && !app.fromPlayStore) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Die APK kommt direkt aus dem GitHub-Release und wird vor dem Einspielen per '
                    'Prüfsumme geprüft. Android spielt sie nur ein, wenn sie mit demselben Schlüssel '
                    'signiert ist wie die installierte App.',
                    style: TextStyle(color: cs.outline, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Täglich automatisch prüfen'),
                  subtitle: Text(app.fromPlayStore
                      ? 'Aus dem Play Store installiert – Updates kommen über Google Play.'
                      : 'Beim Öffnen der App und – mit Benachrichtigungen – im Hintergrund, einmal am Tag.'),
                  value: _auto && !app.fromPlayStore,
                  onChanged: app.fromPlayStore ? null : _setAuto,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Installiert über'),
                  subtitle: Text(_source(app)),
                ),
                if (r != null && r.notes.isNotEmpty) ...[
                  const SectionHeader('Neu in dieser Version'),
                  SelectableText(r.notes, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openUrl(r.pageUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Release auf GitHub'),
                    ),
                  ),
                ],
              ]),
            ),
    );
  }
}
