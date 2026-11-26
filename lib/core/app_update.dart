// ---------------------------------------------------------------------------
// Datei:        lib/core/app_update.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      0.0.1
//
// Beschreibung: App-Update aus dem GitHub-Release — wie beim Server:
//                 * einmal täglich automatisch (beim Öffnen der App und in
//                   der Hintergrundabfrage, die dann benachrichtigt),
//                 * jederzeit von Hand unter Mehr → App-Update.
//               Gefragt wird die öffentliche GitHub-API
//               (releases/latest, ohne Anmeldung, 60 Abfragen/h je IP).
//               Verglichen wird der Versionscode aus dem Release-Text
//               („Versionscode **142**“), sonst der Versionsname
//               (Semantic Versioning, ab 0.0.1; alte Datums-Namen wie
//               2026.11.23 gelten als älter als jede SemVer-Version).
//
//               Installieren (nur Android, nur die APK aus dem Release):
//               APK in den Cache laden, Prüfsumme (SHA-256 vom Release)
//               prüfen, über den PackageInstaller einspielen — Android fragt
//               selbst noch einmal nach. Aus dem Play Store installiert?
//               Dann kommen Updates über Play; die App verweist nur dorthin.
// ---------------------------------------------------------------------------
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'storage.dart';

const appRepo = 'Phydran6/RIMPERIO-App';
const appPackageId = 'de.phytech.rimperio_app';
const playStoreInstaller = 'com.android.vending';

/// Ein Release auf GitHub.
class AppRelease {
  final String tag;
  final String version;
  final int? code;
  final String notes;
  final String pageUrl;
  final DateTime? published;
  final String? apkUrl;
  final String? apkName;
  final int? apkSize;
  final String? apkSha256;

  const AppRelease({
    required this.tag,
    required this.version,
    this.code,
    this.notes = '',
    required this.pageUrl,
    this.published,
    this.apkUrl,
    this.apkName,
    this.apkSize,
    this.apkSha256,
  });

  /// Aus der Antwort von /repos/…/releases/latest.
  factory AppRelease.fromGitHub(Map<String, dynamic> j) {
    final tag = (j['tag_name'] as String?)?.trim() ?? '';
    final body = (j['body'] as String?) ?? '';
    Map<String, dynamic>? apk;
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map<String, dynamic> && '${a['name']}'.toLowerCase().endsWith('.apk')) {
        apk = a;
        break;
      }
    }
    final digest = apk?['digest'] as String?;
    return AppRelease(
      tag: tag,
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      code: parseVersionCode(body),
      notes: cleanNotes(body),
      pageUrl: (j['html_url'] as String?) ?? 'https://github.com/$appRepo/releases/latest',
      published: DateTime.tryParse('${j['published_at'] ?? ''}'),
      apkUrl: apk?['browser_download_url'] as String?,
      apkName: apk?['name'] as String?,
      apkSize: (apk?['size'] as num?)?.toInt(),
      apkSha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'version': version,
        'code': code,
        'notes': notes,
        'page': pageUrl,
        'published': published?.toIso8601String(),
        'apk': apkUrl,
        'apk_name': apkName,
        'apk_size': apkSize,
        'apk_sha256': apkSha256,
      };

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
        tag: '${j['tag'] ?? ''}',
        version: '${j['version'] ?? ''}',
        code: (j['code'] as num?)?.toInt(),
        notes: '${j['notes'] ?? ''}',
        pageUrl: '${j['page'] ?? ''}',
        published: DateTime.tryParse('${j['published'] ?? ''}'),
        apkUrl: j['apk'] as String?,
        apkName: j['apk_name'] as String?,
        apkSize: (j['apk_size'] as num?)?.toInt(),
        apkSha256: j['apk_sha256'] as String?,
      );
}

/// Die installierte App.
class InstalledApp {
  final String version;
  final int code;
  final String? installer;
  const InstalledApp({required this.version, required this.code, this.installer});

  bool get fromPlayStore => installer == playStoreInstaller;
  String get label => code > 0 ? '$version ($code)' : version;
}

/// Was dieses Gerät beim Installieren kann.
class SelfInstall {
  /// Android und die APK hat die Berechtigung REQUEST_INSTALL_PACKAGES.
  final bool supported;

  /// „Unbekannte Apps installieren“ ist für RIMPERIO erlaubt.
  final bool allowed;
  final String? cacheDir;
  const SelfInstall({this.supported = false, this.allowed = false, this.cacheDir});
}

/// "142" aus „Versionscode **142**“ im Release-Text.
int? parseVersionCode(String body) {
  final m = RegExp(r'Versionscode\s*\**\s*(\d+)', caseSensitive: false).firstMatch(body);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// „v2026.11.23.2“ → [2026, 11, 23, 2]. Nicht-Zahlen werden übersprungen.
List<int> parseVersion(String v) => v
    .replaceFirst(RegExp(r'^[vV]'), '')
    .split(RegExp(r'[.+\-]'))
    .map((p) => int.tryParse(p.trim()))
    .whereType<int>()
    .toList();

/// Alter Versionsname im Datumsschema (2026.11.23, 2026.11.23.2)? Eine
/// vierstellige Jahreszahl vorne ist nie ein SemVer-Major.
bool isLegacyVersion(String v) {
  final p = parseVersion(v);
  return p.length >= 3 && p.first >= 1900 && p.first <= 2199;
}

/// <0: a älter, 0: gleich, >0: a neuer. Datumsnamen sind älter als SemVer.
int compareVersions(String a, String b) {
  final la = isLegacyVersion(a), lb = isLegacyVersion(b);
  if (la != lb) return la ? -1 : 1;
  final x = parseVersion(a), y = parseVersion(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Ist das Release neuer als die installierte App? Der Versionscode steigt
/// mit jedem CI-Lauf — darauf ist Verlass; der Name nur als Rückfall.
bool isNewer(AppRelease r, InstalledApp a) {
  if (r.code != null && a.code > 0) return r.code! > a.code;
  return compareVersions(r.version, a.version) > 0;
}

/// Release-Text lesbar machen: Dateiliste und Markdown-Zierrat raus.
String cleanNotes(String body) {
  final lines = <String>[];
  for (var l in const LineSplitter().convert(body)) {
    final t = l.trim();
    if (t.startsWith('Version **') || RegExp(r'^- `RIMPERIO-.*\.(apk|aab)`').hasMatch(t)) continue;
    l = l
        .replaceAll('**', '')
        .replaceAll('`', '')
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .replaceFirst(RegExp(r'^\s*[*-]\s+'), '• ')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!);
    lines.add(l.trimRight());
  }
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

class AppUpdateException implements Exception {
  final String message;
  const AppUpdateException(this.message);
  @override
  String toString() => message;
}

/// Zustand der Installation, gemeldet von Android.
enum InstallState { idle, downloading, installing, confirm, done, failed }

class InstallStatus {
  final InstallState state;
  final double? progress;
  final int received;
  final int total;
  final String? message;
  const InstallStatus(this.state, {this.progress, this.received = 0, this.total = 0, this.message});
  bool get busy =>
      state == InstallState.downloading || state == InstallState.installing || state == InstallState.confirm;
}

class AppUpdate {
  static const _channel = MethodChannel('de.phytech.rimperio/updater');
  static const checkInterval = Duration(hours: 24);
  static const _kLastCheck = 'update_last_check';
  static const _kLatest = 'update_latest';
  static const _kAuto = 'update_auto';
  static const _kNotified = 'update_notified';
  static const _apkFile = 'rimperio-update.apk';

  /// Neueres Release, sobald eins bekannt ist — für Abzeichen und Hinweise.
  static final available = ValueNotifier<AppRelease?>(null);

  /// Fortschritt und Ergebnis der Installation.
  static final status = ValueNotifier<InstallStatus>(const InstallStatus(InstallState.idle));

  /// Für Tests: eigener HTTP-Client.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static InstalledApp? _installed;
  static bool _handlerSet = false;
  static Future<void>? _running;

  // --- Installierte App ------------------------------------------------------

  static Future<InstalledApp> installed() async {
    if (_installed != null) return _installed!;
    try {
      final p = await PackageInfo.fromPlatform();
      _installed = InstalledApp(
        version: p.version,
        code: int.tryParse(p.buildNumber) ?? 0,
        installer: p.installerStore,
      );
    } catch (_) {
      _installed = const InstalledApp(version: '?', code: 0);
    }
    return _installed!;
  }

  @visibleForTesting
  static set installedForTest(InstalledApp? a) => _installed = a;

  // --- Einstellungen ---------------------------------------------------------

  static Future<bool> autoEnabled() async => (await Storage.getValue(_kAuto)) != '0';
  static Future<void> setAutoEnabled(bool on) => Storage.setValue(_kAuto, on ? '1' : '0');

  static Future<DateTime?> lastCheck() async => DateTime.tryParse(await Storage.getValue(_kLastCheck) ?? '');

  /// Zuletzt gesehenes Release (auch ohne Netz anzeigbar).
  static Future<AppRelease?> cachedLatest() async {
    final raw = await Storage.getValue(_kLatest);
    if (raw == null) return null;
    try {
      return AppRelease.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // --- Prüfen ------------------------------------------------------------------

  /// Neuestes Release von GitHub holen.
  static Future<AppRelease> fetchLatest() async {
    final client = clientFactory();
    try {
      final r = await client.get(
        Uri.parse('https://api.github.com/repos/$appRepo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'RIMPERIO-App'},
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 403 || r.statusCode == 429) {
        throw const AppUpdateException('GitHub-Limit erreicht (60 Abfragen pro Stunde) – später erneut versuchen.');
      }
      if (r.statusCode == 404) throw const AppUpdateException('Auf GitHub gibt es noch kein Release.');
      if (r.statusCode != 200) throw AppUpdateException('GitHub antwortet mit ${r.statusCode}.');
      return AppRelease.fromGitHub(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } on TimeoutException {
      throw const AppUpdateException('GitHub antwortet nicht.');
    } on SocketException catch (e) {
      throw AppUpdateException('GitHub nicht erreichbar: ${e.message}');
    } on http.ClientException catch (e) {
      throw AppUpdateException('GitHub nicht erreichbar: ${e.message}');
    } finally {
      client.close();
    }
  }

  /// Jetzt prüfen. Gibt das neueste Release zurück; `available` ist danach
  /// gesetzt, wenn es neuer ist als die installierte App.
  static Future<AppRelease> check() async {
    final latest = await fetchLatest();
    await Storage.setValue(_kLastCheck, DateTime.now().toUtc().toIso8601String());
    await Storage.setValue(_kLatest, jsonEncode(latest.toJson()));
    final app = await installed();
    available.value = isNewer(latest, app) ? latest : null;
    return latest;
  }

  /// Die tägliche Prüfung: nur wenn eingeschaltet, nicht aus dem Play Store
  /// und die letzte Prüfung älter als 24 h ist. Sonst gilt der gemerkte Stand.
  /// Gibt ein neueres Release zurück, das noch nicht gemeldet wurde
  /// (`markNotified` danach aufrufen).
  static Future<AppRelease?> autoCheck({DateTime? now}) async {
    // Nicht doppelt laufen (Start + Minutentakt + Hintergrund).
    final running = _running;
    if (running != null) {
      await running;
      return null;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      final app = await installed();
      if (app.fromPlayStore || !await autoEnabled()) return null;
      final last = await lastCheck();
      final t = now ?? DateTime.now();
      AppRelease? latest;
      if (last == null || t.difference(last) >= checkInterval || t.isBefore(last)) {
        try {
          latest = await check();
        } catch (e) {
          debugPrint('App-Update: Prüfung fehlgeschlagen: $e');
          latest = await cachedLatest();
        }
      } else {
        latest = await cachedLatest();
      }
      if (latest == null || !isNewer(latest, app)) {
        available.value = null;
        return null;
      }
      available.value = latest;
      final notified = await Storage.getValue(_kNotified);
      return notified == latest.tag ? null : latest;
    } finally {
      _running = null;
      done.complete();
    }
  }

  static Future<void> markNotified(AppRelease r) => Storage.setValue(_kNotified, r.tag);

  // --- Installieren (Android) --------------------------------------------------

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'status') return;
      final a = (call.arguments as Map?) ?? const {};
      switch (a['state']) {
        case 'confirm':
          status.value = const InstallStatus(InstallState.confirm);
        case 'done':
          status.value = const InstallStatus(InstallState.done);
        default:
          status.value = InstallStatus(InstallState.failed,
              message: installFailure(a['status'] as int?, a['message'] as String?));
      }
    });
  }

  /// Statuscodes von PackageInstaller in Klartext.
  static String installFailure(int? code, String? message) {
    switch (code) {
      case 3: // STATUS_FAILURE_ABORTED
        return 'Installation abgebrochen.';
      case 4: // STATUS_FAILURE_INVALID
        return 'Die heruntergeladene APK ist ungültig.';
      case 5: // STATUS_FAILURE_CONFLICT
      case 7: // STATUS_FAILURE_INCOMPATIBLE
        return 'Die neue Version ist mit einem anderen Schlüssel signiert als die installierte App. '
            'Einmalig nötig: App deinstallieren und die APK aus dem Release neu installieren – '
            'danach klappt das Update per Knopfdruck.';
      case 6: // STATUS_FAILURE_STORAGE
        return 'Zu wenig Speicherplatz für das Update.';
      case 2: // STATUS_FAILURE_BLOCKED
        return 'Die Installation wurde vom System blockiert.';
    }
    return 'Installation fehlgeschlagen${message != null && message.isNotEmpty ? ': $message' : '.'}';
  }

  static Future<SelfInstall> selfInstall() async {
    if (kIsWeb || !Platform.isAndroid) return const SelfInstall();
    final app = await installed();
    if (app.fromPlayStore) return const SelfInstall();
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('info');
      return SelfInstall(
        supported: info?['declared'] == true,
        allowed: info?['canInstall'] == true,
        cacheDir: info?['cacheDir'] as String?,
      );
    } catch (_) {
      return const SelfInstall();
    }
  }

  /// Systemseite „Unbekannte Apps installieren“ für RIMPERIO öffnen.
  static Future<void> openInstallSettings() => _channel.invokeMethod('openInstallSettings');

  /// Alte Downloads aufräumen (nach einem Update liegt die APK noch im Cache).
  static Future<void> cleanup() async {
    if (status.value.busy) return;
    final si = await selfInstall();
    if (si.cacheDir == null) return;
    try {
      final f = File('${si.cacheDir}/$_apkFile');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Herunterladen, prüfen und Android zum Einspielen übergeben. Fehler
  /// landen in `status` (InstallState.failed mit Klartext), nicht als Ausnahme.
  static Future<void> downloadAndInstall(AppRelease r) async {
    if (status.value.busy) return;
    _ensureHandler();
    final client = clientFactory();
    try {
      final si = await selfInstall();
      if (!si.supported || si.cacheDir == null) {
        throw const AppUpdateException('Diese App-Ausgabe kann sich nicht selbst aktualisieren.');
      }
      if (r.apkUrl == null) throw const AppUpdateException('Im Release liegt keine APK.');
      final file = File('${si.cacheDir}/$_apkFile');
      status.value = InstallStatus(InstallState.downloading, progress: 0, total: r.apkSize ?? 0);
      final resp = await client
          .send(http.Request('GET', Uri.parse(r.apkUrl!))..headers['User-Agent'] = 'RIMPERIO-App')
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw AppUpdateException('Download fehlgeschlagen (${resp.statusCode}).');
      final total = resp.contentLength ?? r.apkSize ?? 0;
      final sink = file.openWrite();
      var received = 0;
      var lastShown = 0;
      try {
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          if (received - lastShown > 256 * 1024 || received == total) {
            lastShown = received;
            status.value = InstallStatus(InstallState.downloading,
                progress: total > 0 ? received / total : null, received: received, total: total);
          }
        }
      } finally {
        await sink.close();
      }
      if (r.apkSize != null && received != r.apkSize) {
        throw AppUpdateException('Download unvollständig ($received von ${r.apkSize} Bytes).');
      }

      status.value = const InstallStatus(InstallState.installing);
      try {
        await _channel.invokeMethod('install', {'path': file.path, 'sha256': r.apkSha256});
      } on PlatformException catch (e) {
        throw AppUpdateException(e.message ?? 'Installation fehlgeschlagen.');
      }
      // Weiter geht es über den Kanal: "confirm" → Android fragt nach; nach
      // dem Update startet die App neu.
    } on TimeoutException {
      status.value = const InstallStatus(InstallState.failed, message: 'Download abgebrochen – keine Antwort.');
    } on SocketException catch (e) {
      status.value = InstallStatus(InstallState.failed, message: 'Download fehlgeschlagen: ${e.message}');
    } catch (e) {
      status.value = InstallStatus(InstallState.failed, message: '$e');
    } finally {
      client.close();
    }
  }
}
