// ---------------------------------------------------------------------------
// Datei:        lib/storage.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.05.12.00.00
//
// Beschreibung: Verschlüsselte Ablage der Server-Adresse auf dem Gerät.
//               Die Anmeldung selbst passiert in der WebView (Token bleibt in
//               deren localStorage) — hier liegt nur, wohin die App zeigt.
// ---------------------------------------------------------------------------
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Storage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyUrl = 'server_url';

  static Future<String?> getUrl() => _storage.read(key: _keyUrl);
  static Future<void> setUrl(String url) => _storage.write(key: _keyUrl, value: url);
  static Future<void> clear() => _storage.delete(key: _keyUrl);
}
