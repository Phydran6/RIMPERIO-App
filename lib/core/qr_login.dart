// ---------------------------------------------------------------------------
// Datei:        lib/core/qr_login.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Inhalt des Anmelde-QR-Codes aus der Weboberfläche
//               (Benutzer → App verbinden). Der Server erzeugt ihn unter
//               GET /api/auth/app-qr:
//                 {"url":"https://…","token":"<64 Hex>","type":"rimperio_app_auth_v1"}
//               Der Token ist 15 Minuten gültig und nur einmal einlösbar.
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'server_address.dart';

class QrLogin {
  static const type = 'rimperio_app_auth_v1';

  final ServerAddress server;
  final String token;
  const QrLogin(this.server, this.token);

  static final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Liest den QR-Inhalt oder wirft [FormatException] mit Klartext-Meldung.
  static QrLogin parse(String raw) {
    Object? data;
    try {
      data = jsonDecode(raw.trim());
    } catch (_) {
      throw const FormatException(
          'Das ist kein RIMPERIO-Anmeldecode. Den Code bitte in der Weboberfläche unter '
          '„App verbinden“ erzeugen.');
    }
    if (data is! Map || data['type'] != type) {
      throw const FormatException('Das ist kein RIMPERIO-Anmeldecode.');
    }
    final token = data['token'];
    final url = data['url'];
    if (token is! String || !_hex64.hasMatch(token) || url is! String) {
      throw const FormatException('Der Anmeldecode ist unvollständig.');
    }
    return QrLogin(ServerAddress.parse(url), token);
  }
}
