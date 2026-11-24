// ---------------------------------------------------------------------------
// Datei:        test/app_update_test.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.24.12.00.00
//
// Beschreibung: App-Update: Versionen lesen und vergleichen, Release von
//               GitHub auswerten (APK, Prüfsumme, Versionscode), tägliche
//               Prüfung (nur alle 24 h, jede Version nur einmal melden, nicht
//               bei Play-Store-Installation) und die Seite „App-Update“.
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rimperio_app/core/app_update.dart';
import 'package:rimperio_app/screens/app_update_page.dart';
import 'package:rimperio_app/ui/theme.dart';

Map<String, dynamic> _release(String tag, int code) => {
      'tag_name': 'v$tag',
      'html_url': 'https://github.com/$appRepo/releases/tag/v$tag',
      'published_at': '2026-11-24T10:00:00Z',
      'body': 'Version **$tag** · Versionscode **$code**\n\n'
          '- `RIMPERIO-$tag.apk` — direkt aufs Handy installieren\n'
          '- `RIMPERIO-$tag-$code.aab` — für die Google Play Console\n\n\n'
          "## What's Changed\n"
          '* App-Update per Knopfdruck by @someone in https://example.invalid/pull/3\n',
      'assets': [
        {
          'name': 'RIMPERIO-$tag-$code.aab',
          'size': 1,
          'browser_download_url': 'https://example.invalid/x.aab',
          'digest': 'sha256:aa',
        },
        {
          'name': 'RIMPERIO-$tag.apk',
          'size': 72768480,
          'browser_download_url': 'https://github.com/$appRepo/releases/download/v$tag/RIMPERIO-$tag.apk',
          'digest': 'sha256:645a4f4cf90196929f661c84823c1507527825b41a5f49d7858d8e87309e1a14',
        },
      ],
    };

int _calls = 0;

void _github(Map<String, dynamic> release, {int status = 200}) {
  _calls = 0;
  AppUpdate.clientFactory = () => MockClient((req) async {
        _calls++;
        expect(req.url.toString(), 'https://api.github.com/repos/$appRepo/releases/latest');
        return http.Response(jsonEncode(release), status, headers: {'content-type': 'application/json'});
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppUpdate.installedForTest = const InstalledApp(version: '2026.11.23', code: 119, installer: null);
    AppUpdate.available.value = null;
  });

  group('Versionen', () {
    test('lesen und vergleichen', () {
      expect(parseVersion('v2026.11.23.2'), [2026, 11, 23, 2]);
      expect(parseVersion('2026.11.23+5'), [2026, 11, 23, 5]);
      expect(compareVersions('2026.11.23.2', '2026.11.23'), greaterThan(0));
      expect(compareVersions('2026.11.3', '2026.11.23'), lessThan(0));
      expect(compareVersions('v2026.11.23', '2026.11.23'), 0);
      expect(compareVersions('2026.12.1', '2026.11.30'), greaterThan(0));
    });

    test('Versionscode aus dem Release-Text', () {
      expect(parseVersionCode('Version **2026.11.23** · Versionscode **119**'), 119);
      expect(parseVersionCode('ohne Code'), isNull);
    });

    test('neuer: Code zuerst, sonst Name', () {
      const app = InstalledApp(version: '2026.11.23', code: 119);
      AppRelease r(String v, int? c) => AppRelease(tag: 'v$v', version: v, code: c, pageUrl: '');
      expect(isNewer(r('2026.11.24', 120), app), isTrue);
      expect(isNewer(r('2026.11.23', 119), app), isFalse);
      // Code entscheidet, auch wenn der Name gleich ist (lokaler Build o. Ä.)
      expect(isNewer(r('2026.11.23', 125), app), isTrue);
      expect(isNewer(r('2026.11.24', null), app), isTrue);
      expect(isNewer(r('2026.11.22', null), app), isFalse);
      // Lokaler Build ohne CI-Code: Code des Release gewinnt
      expect(isNewer(r('2026.11.23', 119), const InstalledApp(version: '2026.11.23', code: 5)), isTrue);
    });
  });

  test('Release von GitHub: APK, Prüfsumme, Notizen', () {
    final r = AppRelease.fromGitHub(_release('2026.11.24', 120));
    expect(r.version, '2026.11.24');
    expect(r.code, 120);
    expect(r.apkName, 'RIMPERIO-2026.11.24.apk');
    expect(r.apkSize, 72768480);
    expect(r.apkSha256, startsWith('645a4f'));
    expect(r.notes, isNot(contains('.aab')));
    expect(r.notes, isNot(contains('Versionscode')));
    expect(r.notes, contains("What's Changed"));
    expect(r.notes, contains('• App-Update per Knopfdruck'));
    final back = AppRelease.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.apkUrl, r.apkUrl);
    expect(back.code, 120);
  });

  group('Tägliche Prüfung', () {
    test('fragt höchstens alle 24 h und meldet jede Version einmal', () async {
      _github(_release('2026.11.24', 120));
      final t0 = DateTime.now();
      final first = await AppUpdate.autoCheck(now: t0);
      expect(first?.version, '2026.11.24');
      expect(AppUpdate.available.value?.code, 120);
      expect(_calls, 1);
      await AppUpdate.markNotified(first!);

      // Eine Stunde später: kein neuer Abruf, nichts Neues zu melden …
      final again = await AppUpdate.autoCheck(now: t0.add(const Duration(hours: 1)));
      expect(again, isNull);
      expect(_calls, 1);
      // … aber das Abzeichen bleibt.
      expect(AppUpdate.available.value?.code, 120);

      // Am nächsten Tag: neuer Abruf, wieder dieselbe Version → keine Meldung.
      final nextDay = await AppUpdate.autoCheck(now: t0.add(const Duration(hours: 25)));
      expect(nextDay, isNull);
      expect(_calls, 2);
    });

    test('aktuell: nichts verfügbar', () async {
      _github(_release('2026.11.23', 119));
      expect(await AppUpdate.autoCheck(), isNull);
      expect(AppUpdate.available.value, isNull);
    });

    test('abgeschaltet oder aus dem Play Store: kein Abruf', () async {
      _github(_release('2026.11.24', 120));
      await AppUpdate.setAutoEnabled(false);
      expect(await AppUpdate.autoCheck(), isNull);
      expect(_calls, 0);

      await AppUpdate.setAutoEnabled(true);
      AppUpdate.installedForTest =
          const InstalledApp(version: '2026.11.23', code: 119, installer: playStoreInstaller);
      expect(await AppUpdate.autoCheck(), isNull);
      expect(_calls, 0);
    });

    test('GitHub-Limit: verständliche Meldung', () async {
      _github({'message': 'API rate limit exceeded'}, status: 403);
      expect(AppUpdate.check(), throwsA(isA<AppUpdateException>()));
    });
  });

  testWidgets('Seite „App-Update“ zeigt Versionen und Neuigkeiten', (t) async {
    _github(_release('2026.11.24', 120));
    await t.pumpWidget(MaterialApp(theme: RimTheme.dark(), home: const AppUpdatePage()));
    await t.pumpAndSettle();
    expect(find.text('2026.11.23 (119)'), findsOneWidget);
    expect(find.text('2026.11.24 (120)'), findsOneWidget);
    expect(find.text('Neue Version verfügbar.'), findsOneWidget);
    expect(find.text('Täglich automatisch prüfen'), findsOneWidget);
    // Im Test (kein Android): Verweis aufs Release statt Installieren.
    expect(find.text('Release auf GitHub öffnen'), findsOneWidget);
    expect(find.textContaining('App-Update per Knopfdruck'), findsOneWidget);
  });
}
