// ---------------------------------------------------------------------------
// Datei:        lib/core/session.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Zustand der App: kein Server → Einrichtung; kein gültiger
//               Token → Anmeldung; Biometrie an → Sperrbildschirm; sonst die
//               App. Der Server stellt 24-h-Tokens ohne Refresh aus. Ist die
//               Biometrie an und wurde mit Passwort angemeldet, meldet die App
//               nach dem Fingerabdruck still neu an.
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'biometrics.dart';
import 'notifications.dart';
import 'server_address.dart';
import 'storage.dart';

enum Stage { loading, setup, login, locked, ready }

class Session extends ChangeNotifier {
  Stage stage = Stage.loading;
  ServerAddress? server;
  Api? api;
  Map<String, dynamic>? bootstrap;
  String? username;
  bool biometricEnabled = false;
  bool hasStoredPassword = false;

  /// Hinweis für den Anmeldebildschirm (z. B. „Sitzung abgelaufen“).
  String? loginNotice;

  DateTime? _pausedAt;
  static const lockAfter = Duration(minutes: 2);

  bool get isAdmin => bootstrap?['user']?['is_admin'] == true;
  String get serverName => bootstrap?['server']?['name'] as String? ?? 'RIMPERIO';
  bool get isSecure => server?.isSecure ?? false;

  Future<void> start() async {
    final url = await Storage.getUrl();
    if (url == null || url.isEmpty) return _go(Stage.setup);
    _useServer(ServerAddress.parse(url));
    username = await Storage.getUsername();
    biometricEnabled = await Storage.getBiometric();
    hasStoredPassword = (await Storage.getPassword()) != null;
    final token = await Storage.getToken();

    if (token != null && !_expired(token)) {
      api!.token = token;
      if (biometricEnabled) return _go(Stage.locked);
      return _enter();
    }
    await Storage.setToken(null);
    if (biometricEnabled && hasStoredPassword) return _go(Stage.locked);
    loginNotice = token != null ? 'Die Sitzung ist abgelaufen — bitte neu anmelden.' : null;
    _go(Stage.login);
  }

  // ---- Einrichtung --------------------------------------------------------

  Future<void> setServer(ServerAddress s) async {
    await Storage.clearAll();
    await Storage.setUrl(s.base);
    _useServer(s);
    biometricEnabled = false;
    hasStoredPassword = false;
    loginNotice = null;
    _go(Stage.login);
  }

  Future<void> changeServer() async {
    await Notifications.schedule(false);
    await Storage.clearAll();
    api?.close();
    api = null;
    server = null;
    bootstrap = null;
    _go(Stage.setup);
  }

  // ---- Anmeldung ----------------------------------------------------------

  /// Gibt einen MFA-Token zurück, wenn noch der Zweitfaktor fehlt.
  Future<String?> loginWithPassword(String user, String password) async {
    final res = await api!.login(user, password);
    if (res.needsMfa) {
      _pendingUser = user;
      return res.mfaToken;
    }
    await _signedIn(res.accessToken!, user: user, password: password);
    return null;
  }

  String? _pendingUser;

  Future<void> loginWithMfa(String mfaToken, String code) async {
    final token = await api!.loginMfa(mfaToken, code);
    // Mit Zweitfaktor lässt sich nicht still neu anmelden → Passwort nicht merken.
    await _signedIn(token, user: _pendingUser, password: null);
    _pendingUser = null;
  }

  /// QR-Code-Weg. Der Code bringt die Server-Adresse mit.
  Future<void> loginWithQr(ServerAddress s, String oneTimeToken) async {
    if (server?.base != s.base) {
      await Storage.clearAll();
      await Storage.setUrl(s.base);
      _useServer(s);
      biometricEnabled = false;
    }
    final token = await api!.exchangeQrToken(oneTimeToken);
    await _signedIn(token, user: null, password: null);
  }

  Future<void> _signedIn(String token, {String? user, String? password}) async {
    api!.token = token;
    await Storage.setToken(token);
    if (user != null) {
      username = user;
      await Storage.setUsername(user);
    }
    // Passwort nur behalten, wenn die Biometrie es schützt.
    if (biometricEnabled && password != null) {
      await Storage.setPassword(password);
      hasStoredPassword = true;
    } else {
      _lastPassword = password;
    }
    loginNotice = null;
    await _enter();
  }

  /// Passwort der letzten Anmeldung, bis der Nutzer über die Biometrie
  /// entschieden hat (nur im Speicher).
  String? _lastPassword;
  bool get canRememberPassword => _lastPassword != null || hasStoredPassword;

  Future<void> logout() async {
    await Notifications.schedule(false);
    await Storage.clearSession();
    api?.token = null;
    biometricEnabled = false;
    hasStoredPassword = false;
    _lastPassword = null;
    bootstrap = null;
    _go(Stage.login);
  }

  // ---- Biometrie ----------------------------------------------------------

  /// `null` = ok, sonst Fehlermeldung ('' = abgebrochen).
  Future<String?> enableBiometric() async {
    final err = await Biometrics.authenticate('Biometrische Anmeldung für RIMPERIO einschalten');
    if (err != null) return err;
    biometricEnabled = true;
    await Storage.setBiometric(true);
    if (_lastPassword != null) {
      await Storage.setPassword(_lastPassword);
      hasStoredPassword = true;
      _lastPassword = null;
    }
    notifyListeners();
    return null;
  }

  Future<void> disableBiometric() async {
    biometricEnabled = false;
    hasStoredPassword = false;
    await Storage.setBiometric(false);
    await Storage.setPassword(null);
    notifyListeners();
  }

  /// Sperrbildschirm → App. `null` = ok, sonst Meldung.
  Future<String?> unlock() async {
    final err = await Biometrics.authenticate('Bei RIMPERIO anmelden');
    if (err != null) return err;

    if (api!.token != null && !_expired(api!.token!)) {
      await _enter();
      return null;
    }
    // Token abgelaufen: mit den geschützten Zugangsdaten still neu anmelden.
    final user = await Storage.getUsername();
    final pw = await Storage.getPassword();
    if (user == null || pw == null) {
      loginNotice = 'Die Sitzung ist abgelaufen — bitte neu anmelden.';
      _go(Stage.login);
      return null;
    }
    try {
      final res = await api!.login(user, pw);
      if (res.needsMfa) {
        loginNotice = 'Für dieses Konto ist ein Zweitfaktor nötig — bitte neu anmelden.';
        _go(Stage.login);
        return null;
      }
      api!.token = res.accessToken;
      await Storage.setToken(res.accessToken);
      await _enter();
      return null;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await Storage.setPassword(null);
        hasStoredPassword = false;
        loginNotice = 'Das gespeicherte Passwort gilt nicht mehr — bitte neu anmelden.';
        _go(Stage.login);
        return null;
      }
      return e.message;
    }
  }

  /// Ohne Biometrie entsperren (z. B. Sensor kaputt): zur Anmeldung.
  void unlockWithPassword() {
    loginNotice = null;
    _go(Stage.login);
  }

  // ---- Lebenszyklus -------------------------------------------------------

  void paused() => _pausedAt = DateTime.now();

  void resumed() {
    final p = _pausedAt;
    _pausedAt = null;
    if (stage == Stage.ready && biometricEnabled && p != null &&
        DateTime.now().difference(p) > lockAfter) {
      _go(Stage.locked);
    }
  }

  Future<void> refreshBootstrap() async {
    bootstrap = await api!.getJson('/api/app/bootstrap');
    notifyListeners();
  }

  // ---- Intern -------------------------------------------------------------

  void _useServer(ServerAddress s) {
    api?.close();
    server = s;
    api = Api(s)..onUnauthorized = _onUnauthorized;
  }

  Future<void> _enter() async {
    try {
      bootstrap = await api!.getJson('/api/app/bootstrap');
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // _onUnauthorized hat schon umgeschaltet
      // Offline o. Ä.: trotzdem rein, die Seiten zeigen den Fehler selbst.
      debugPrint('Bootstrap fehlgeschlagen: $e');
    }
    _go(Stage.ready);
    if (await Storage.getNotify() && await Notifications.permitted()) {
      await Notifications.schedule(true);
    }
  }

  void _onUnauthorized() {
    if (stage != Stage.ready && stage != Stage.loading) return;
    api?.token = null;
    Storage.setToken(null);
    if (biometricEnabled && hasStoredPassword) {
      _go(Stage.locked);
    } else {
      loginNotice = 'Die Sitzung ist abgelaufen — bitte neu anmelden.';
      _go(Stage.login);
    }
  }

  void _go(Stage s) {
    stage = s;
    notifyListeners();
  }

  /// Ablauf aus dem JWT lesen (ohne Prüfung der Signatur — das macht der
  /// Server). Eine Minute Puffer.
  static bool _expired(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = (payload as Map)['exp'];
      if (exp is! num) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now().isAfter(at.subtract(const Duration(minutes: 1)));
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static bool isExpired(String jwt) => _expired(jwt);
}
