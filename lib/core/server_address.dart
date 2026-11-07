// ---------------------------------------------------------------------------
// Datei:        lib/core/server_address.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Server-Adresse aufbereiten und prüfen. Ohne Schema wird immer
//               https:// angenommen; http:// geht nur ausdrücklich und wird in
//               der App sichtbar als unverschlüsselt markiert.
// ---------------------------------------------------------------------------

class ServerAddress {
  final Uri uri;
  const ServerAddress._(this.uri);

  bool get isSecure => uri.scheme == 'https';

  /// Basis ohne abschließenden Schrägstrich, z. B. `https://rmm.example.de`.
  String get base => uri.toString();

  String get host => uri.host;

  /// Wandelt eine Eingabe in eine Adresse um oder wirft [FormatException]
  /// mit einer deutschsprachigen Meldung.
  static ServerAddress parse(String raw) {
    var v = raw.trim();
    if (v.isEmpty) throw const FormatException('Bitte eine Server-Adresse eingeben.');
    if (!v.contains('://')) v = 'https://$v';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('Die Adresse sieht nicht gültig aus.');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const FormatException('Nur https:// (oder ausdrücklich http://) ist möglich.');
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    // Wer die Adresse aus der Browserleiste kopiert, bringt oft /login o. Ä. mit.
    if (path == '/login' || path == '/app') path = '';
    return ServerAddress._(Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ));
  }

  /// Dieselbe Adresse, aber per https — für den Versuch „vielleicht kann der
  /// Server ja doch TLS“.
  ServerAddress get asHttps => ServerAddress._(uri.replace(
        scheme: 'https',
        port: uri.hasPort && uri.port != 80 ? uri.port : null,
      ));

  Uri resolve(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  @override
  String toString() => base;
}
