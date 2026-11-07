// ---------------------------------------------------------------------------
// Datei:        lib/core/biometrics.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Fingerabdruck / Gesichtserkennung über local_auth. Fällt auf
//               die Geräte-PIN zurück, wenn der Sensor gerade nicht will.
//               Android braucht dafür eine FlutterFragmentActivity (richtet
//               scripts/setup_platforms.sh ein).
// ---------------------------------------------------------------------------
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class Biometrics {
  static final _auth = LocalAuthentication();

  /// Hat das Gerät Biometrie (oder wenigstens eine Display-Sperre)?
  static Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.canCheckBiometrics || (await _auth.getAvailableBiometrics()).isNotEmpty);
    } catch (e) {
      debugPrint('Biometrie nicht verfügbar: $e');
      return false;
    }
  }

  /// `null` = erfolgreich; sonst eine Meldung für den Nutzer.
  /// Abbrechen durch den Nutzer liefert einen leeren String (nichts anzeigen).
  static Future<String?> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? null : '';
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.authInProgress =>
          '',
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          'Auf dem Gerät ist kein Fingerabdruck / Gesicht eingerichtet.',
        LocalAuthExceptionCode.noCredentialsSet => 'Auf dem Gerät ist keine Displaysperre eingerichtet.',
        LocalAuthExceptionCode.noBiometricHardware => 'Das Gerät hat keinen Biometrie-Sensor.',
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          'Zu viele Fehlversuche — Sensor vorübergehend gesperrt.',
        _ => 'Biometrie fehlgeschlagen (${e.code.name}).',
      };
    } catch (e) {
      return 'Biometrie fehlgeschlagen: $e';
    }
  }
}
