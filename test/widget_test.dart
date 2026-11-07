// ---------------------------------------------------------------------------
// Datei:        test/widget_test.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Adress-Aufbereitung (HTTPS als Vorgabe), QR-Anmeldecode,
//               Token-Ablauf und die Einrichtungsseite.
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rimperio_app/core/qr_login.dart';
import 'package:rimperio_app/core/server_address.dart';
import 'package:rimperio_app/core/session.dart';
import 'package:rimperio_app/screens/setup_page.dart';
import 'package:rimperio_app/ui/scope.dart';

void main() {
  group('ServerAddress', () {
    test('ohne Schema wird https angenommen', () {
      final a = ServerAddress.parse('  rmm.example.de/ ');
      expect(a.base, 'https://rmm.example.de');
      expect(a.isSecure, isTrue);
    });

    test('http bleibt http, aber unsicher', () {
      final a = ServerAddress.parse('http://192.168.1.10:8080');
      expect(a.isSecure, isFalse);
      expect(a.asHttps.base, 'https://192.168.1.10:8080');
    });

    test('Port 80 fällt beim Umstieg auf https weg', () {
      expect(ServerAddress.parse('http://rmm.lan:80').asHttps.base, 'https://rmm.lan');
    });

    test('/login aus der Browserleiste wird entfernt', () {
      expect(ServerAddress.parse('https://rmm.example.de/login').base, 'https://rmm.example.de');
    });

    test('Pfade werden angehängt', () {
      final a = ServerAddress.parse('rmm.example.de');
      expect(a.resolve('/api/app/logs', {'limit': '50'}).toString(),
          'https://rmm.example.de/api/app/logs?limit=50');
    });

    test('leer und kaputt werden abgewiesen', () {
      expect(() => ServerAddress.parse(''), throwsFormatException);
      expect(() => ServerAddress.parse('https://'), throwsFormatException);
      expect(() => ServerAddress.parse('ftp://x.de'), throwsFormatException);
    });
  });

  group('QrLogin', () {
    final token = 'a' * 64;

    test('liest den Code aus /api/auth/app-qr', () {
      final raw = jsonEncode({'url': 'https://rmm.example.de', 'token': token, 'type': 'rimperio_app_auth_v1'});
      final qr = QrLogin.parse(raw);
      expect(qr.server.base, 'https://rmm.example.de');
      expect(qr.token, token);
    });

    test('fremde Codes werden abgewiesen', () {
      expect(() => QrLogin.parse('https://example.de'), throwsFormatException);
      expect(() => QrLogin.parse(jsonEncode({'url': 'x', 'token': token, 'type': 'anders'})),
          throwsFormatException);
      expect(
          () => QrLogin.parse(
              jsonEncode({'url': 'https://a.de', 'token': 'kurz', 'type': 'rimperio_app_auth_v1'})),
          throwsFormatException);
    });
  });

  group('Token-Ablauf', () {
    String jwt(DateTime exp) {
      String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      return '${b64({'alg': 'HS256'})}.${b64({'sub': 'admin', 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
    }

    test('gültig und abgelaufen', () {
      expect(Session.isExpired(jwt(DateTime.now().add(const Duration(hours: 5)))), isFalse);
      expect(Session.isExpired(jwt(DateTime.now().subtract(const Duration(minutes: 1)))), isTrue);
    });
  });

  group('Einrichtung', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          SessionScope(session: Session(), child: const MaterialApp(home: SetupPage())),
        );

    testWidgets('zeigt Logo, QR-Knopf und Eingabefeld', (tester) async {
      await pump(tester);
      expect(find.byWidgetPredicate((w) => w is Image && w.semanticLabel == 'RIMPERIO'), findsOneWidget);
      expect(find.text('QR-Code scannen'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('leere Adresse wird abgewiesen', (tester) async {
      await pump(tester);
      await tester.ensureVisible(find.text('Verbinden'));
      await tester.tap(find.text('Verbinden'));
      await tester.pump();
      expect(find.text('Bitte eine Server-Adresse eingeben.'), findsOneWidget);
    });
  });
}
