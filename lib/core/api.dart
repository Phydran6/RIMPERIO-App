// ---------------------------------------------------------------------------
// Datei:        lib/core/api.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Schlanker Client für die RIMPERIO-API. Anmeldung über
//               /api/auth/*, alles Weitere über die App-Schnittstelle
//               /api/app/* (kompakte Antworten, Cursor-Blättern).
// ---------------------------------------------------------------------------
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'server_address.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  const ApiException(this.message, {this.status});

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;

  @override
  String toString() => message;
}

/// Ergebnis von /api/auth/login: entweder fertig oder es fehlt der Zweitfaktor.
class LoginResult {
  final String? accessToken;
  final String? mfaToken;
  const LoginResult.done(String token)
      : accessToken = token,
        mfaToken = null;
  const LoginResult.mfa(String token)
      : accessToken = null,
        mfaToken = token;
  bool get needsMfa => mfaToken != null;
}

class Api {
  final ServerAddress server;
  String? token;

  /// Wird aufgerufen, wenn der Server den Token ablehnt (abgelaufen/entzogen).
  void Function()? onUnauthorized;

  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Api(this.server, {this.token, http.Client? client}) : _http = client ?? http.Client();

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  // ---- Anmeldung ----------------------------------------------------------

  /// Prüft, ob unter der Adresse wirklich ein RIMPERIO-Server antwortet.
  /// Liefert die Server-Version.
  Future<String> ping() async {
    final res = await _send(() => _http.get(server.resolve('/api/health'), headers: _headers),
        auth: false);
    Object? data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    if (res.statusCode != 200 || data is! Map || data['version'] == null) {
      throw ApiException(
          'Unter ${server.host} antwortet kein RIMPERIO-Server (HTTP ${res.statusCode}).');
    }
    return '${data['version']}';
  }

  Future<LoginResult> login(String username, String password) async {
    final res = await _send(
      () => _http.post(
        server.resolve('/api/auth/login'),
        headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username, 'password': password},
      ),
      auth: false,
    );
    final data = _decode(res);
    if (data is Map && data['mfa_required'] == true) {
      return LoginResult.mfa(data['mfa_token'] as String);
    }
    return LoginResult.done((data as Map)['access_token'] as String);
  }

  Future<String> loginMfa(String mfaToken, String code) async {
    final res = await _send(
      () => _http.post(
        server.resolve('/api/auth/login/mfa'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'mfa_token': mfaToken, 'code': code.replaceAll(' ', '')}),
      ),
      auth: false,
    );
    return (_decode(res) as Map)['access_token'] as String;
  }

  /// QR-Code-Weg: Einmal-Token gegen eine Sitzung tauschen.
  Future<String> exchangeQrToken(String oneTimeToken) async {
    final res = await _send(
      () => _http.post(
        server.resolve('/api/auth/app-token/exchange'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'token': oneTimeToken}),
      ),
      auth: false,
    );
    return (_decode(res) as Map)['access_token'] as String;
  }

  // ---- App-Schnittstelle --------------------------------------------------

  Future<Map<String, dynamic>> getJson(String path, [Map<String, Object?>? query]) async {
    final q = <String, String>{
      for (final e in (query ?? const {}).entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
    };
    final res = await _send(() => _http.get(server.resolve(path, q), headers: _headers));
    return _decode(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postJson(String path, Object body) async {
    final res = await _send(() => _http.post(
          server.resolve(path),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
    final data = _decode(res);
    return data is Map<String, dynamic> ? data : {'result': data};
  }

  // ---- Intern -------------------------------------------------------------

  Future<http.Response> _send(Future<http.Response> Function() call, {bool auth = true}) async {
    http.Response res;
    try {
      res = await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Zeitüberschreitung — ${server.host} antwortet nicht.');
    } on HandshakeException {
      throw ApiException(
          'Das HTTPS-Zertifikat von ${server.host} ist ungültig oder nicht vertrauenswürdig.');
    } on SocketException catch (e) {
      throw ApiException('Keine Verbindung zu ${server.host} (${e.osError?.message ?? e.message}).');
    } on http.ClientException catch (e) {
      throw ApiException('Verbindung fehlgeschlagen: ${e.message}');
    } catch (e) {
      // Android/iOS sperren http:// ab Werk ("Insecure HTTP is not allowed by platform").
      if ('$e'.contains('Insecure HTTP')) {
        throw ApiException('${server.host} spricht nur unverschlüsseltes HTTP, das diese App-Version '
            'sperrt. Bitte am Server HTTPS einschalten.');
      }
      throw ApiException('Verbindung fehlgeschlagen: $e');
    }
    if (auth && res.statusCode == 401) {
      onUnauthorized?.call();
    }
    return res;
  }

  Object? _decode(http.Response res) {
    Object? data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (data == null && res.body.isNotEmpty) {
        throw ApiException('Unerwartete Antwort von ${server.host} — ist das ein RIMPERIO-Server?',
            status: res.statusCode);
      }
      return data;
    }
    throw ApiException(_detail(data) ?? _fallback(res.statusCode), status: res.statusCode);
  }

  static String? _detail(Object? data) {
    if (data is! Map) return null;
    final d = data['detail'];
    if (d is String) return d;
    if (d is List && d.isNotEmpty && d.first is Map) return (d.first as Map)['msg']?.toString();
    return null;
  }

  static String _fallback(int status) => switch (status) {
        401 => 'Anmeldung abgelaufen oder ungültig.',
        403 => 'Dafür fehlen die Rechte (Admin nötig).',
        404 => 'Nicht gefunden — ist der Server aktuell?',
        423 => 'Vorübergehend gesperrt.',
        429 => 'Zu viele Versuche — bitte kurz warten.',
        _ => 'Fehler vom Server (HTTP $status).',
      };

  void close() => _http.close();
}
