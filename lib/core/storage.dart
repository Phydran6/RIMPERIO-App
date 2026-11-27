// ---------------------------------------------------------------------------
// Datei:        lib/core/storage.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.24.12.00.00
//
// Beschreibung: Verschlüsselte Ablage auf dem Gerät (Android Keystore bzw.
//               iOS Keychain): Server-Adresse, Sitzungs-Token und — nur wenn
//               die Biometrie-Anmeldung eingeschaltet ist — die Zugangsdaten,
//               damit nach Ablauf des Tokens (24 h) ein Fingerabdruck reicht.
// ---------------------------------------------------------------------------
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Storage {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const _kUrl = 'server_url';
  static const _kToken = 'access_token';
  static const _kUser = 'username';
  static const _kPassword = 'password';
  static const _kBiometric = 'biometric_enabled';
  static const _kNotify = 'notifications_enabled';
  static const _kLastNotification = 'last_notification_id';
  static const _kInsecureOk = 'insecure_confirmed_for';
  static const _kDeviceKey = 'device_key';
  static const _kDeviceId = 'device_id';
  static const _kTenantScope = 'tenant_scope';

  static Future<String?> getUrl() => _s.read(key: _kUrl);
  static Future<void> setUrl(String url) => _s.write(key: _kUrl, value: url);

  static Future<String?> getToken() => _s.read(key: _kToken);
  static Future<void> setToken(String? t) =>
      t == null ? _s.delete(key: _kToken) : _s.write(key: _kToken, value: t);

  static Future<String?> getUsername() => _s.read(key: _kUser);
  static Future<void> setUsername(String u) => _s.write(key: _kUser, value: u);

  static Future<String?> getPassword() => _s.read(key: _kPassword);
  static Future<void> setPassword(String? p) =>
      p == null ? _s.delete(key: _kPassword) : _s.write(key: _kPassword, value: p);

  static Future<bool> getBiometric() async => (await _s.read(key: _kBiometric)) == '1';
  static Future<void> setBiometric(bool on) => _s.write(key: _kBiometric, value: on ? '1' : '0');

  static Future<bool> getNotify() async => (await _s.read(key: _kNotify)) != '0';
  static Future<void> setNotify(bool on) => _s.write(key: _kNotify, value: on ? '1' : '0');

  static Future<int?> getLastNotificationId() async =>
      int.tryParse(await _s.read(key: _kLastNotification) ?? '');
  static Future<void> setLastNotificationId(int id) =>
      _s.write(key: _kLastNotification, value: '$id');

  /// Geräteschlüssel für die Hintergrundabfrage (nur Meldungen abholen).
  static Future<String?> getDeviceKey() => _s.read(key: _kDeviceKey);
  static Future<int?> getDeviceId() async => int.tryParse(await _s.read(key: _kDeviceId) ?? '');
  static Future<void> setDevice(int? id, String? key) async {
    if (id == null || key == null) {
      await _s.delete(key: _kDeviceKey);
      await _s.delete(key: _kDeviceId);
    } else {
      await _s.write(key: _kDeviceKey, value: key);
      await _s.write(key: _kDeviceId, value: '$id');
    }
  }

  /// Mandanten-Ansicht eines Betreibers (leer = alle Mandanten).
  static Future<String?> getTenantScope() => _s.read(key: _kTenantScope);
  static Future<void> setTenantScope(String? v) =>
      (v == null || v.isEmpty) ? _s.delete(key: _kTenantScope) : _s.write(key: _kTenantScope, value: v);

  /// Für welche http://-Adresse der Nutzer das Risiko bestätigt hat.
  static Future<String?> getInsecureConfirmed() => _s.read(key: _kInsecureOk);
  static Future<void> setInsecureConfirmed(String? url) =>
      url == null ? _s.delete(key: _kInsecureOk) : _s.write(key: _kInsecureOk, value: url);

  /// Einmal-Hinweise („Biometrie anbieten“, „Benachrichtigungen erfragen“).
  static Future<bool> getFlag(String name) async => (await _s.read(key: 'flag_$name')) == '1';
  static Future<void> setFlag(String name) => _s.write(key: 'flag_$name', value: '1');

  /// Einfache Werte (App-Update: letzte Prüfung, gemerktes Release …).
  static Future<String?> getValue(String name) => _s.read(key: 'val_$name');
  static Future<void> setValue(String name, String? value) =>
      value == null ? _s.delete(key: 'val_$name') : _s.write(key: 'val_$name', value: value);

  /// Abmelden: Sitzung und gespeicherte Zugangsdaten weg, Server bleibt.
  static Future<void> clearSession() async {
    await _s.delete(key: _kToken);
    await _s.delete(key: _kPassword);
    await _s.delete(key: _kBiometric);
    await _s.delete(key: _kLastNotification);
    await _s.delete(key: _kDeviceKey);
    await _s.delete(key: _kDeviceId);
    await _s.delete(key: _kTenantScope);
  }

  /// Server wechseln: alles weg.
  static Future<void> clearAll() => _s.deleteAll();
}
