<div align="center">

<img src="assets/icon/rimperio_logo.png" alt="RIMPERIO" width="160">

# RIMPERIO-App

**Die eigene RIMPERIO-Instanz am Handy**

Eine native **Flutter**-App für deinen
[RIMPERIO-Server](https://github.com/Phydran6/RIMPERIO-Server).
Eine Codebasis für **Android und iOS**.

[![CI](https://github.com/Phydran6/RIMPERIO-App/actions/workflows/ci.yml/badge.svg)](https://github.com/Phydran6/RIMPERIO-App/actions/workflows/ci.yml)
[![Android](https://img.shields.io/badge/Android-APK-3DDC84?logo=android&logoColor=white)](https://github.com/Phydran6/RIMPERIO-App/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

← [Übersicht](https://github.com/Phydran6/RIMPERIO) · [Server](https://github.com/Phydran6/RIMPERIO-Server)

</div>

---

## Prinzip

Eine **native** App auf die schlanke App-Schnittstelle des Servers (`/api/app/*`) —
keine WebView. Untere Navigationsleiste mit **Übersicht, Logs, Geräte, Meldungen, Mehr**;
dazu Updates/Freigaben (inkl. KI-Einschätzung, Zurückrollen) und SNMP.

| | |
|---|---|
| **Anmeldung** | QR-Code aus der Weboberfläche (*Benutzer → App verbinden*) oder Benutzer/Passwort, mit Zweitfaktor |
| **Biometrie** | Fingerabdruck / Face ID entsperrt die App; nach Passwort-Anmeldung meldet sie nach Ablauf der 24-h-Sitzung still neu an |
| **Verbindung** | immer zuerst HTTPS; `http://` nur nach Warnung, danach dauerhaft rot markiert |
| **Benachrichtigungen** | Berechtigung wird nach der Anmeldung erfragt; Abfrage im Vordergrund jede Minute, im Hintergrund (Android) etwa alle 15 min |
| **Gespeichert (verschlüsselt)** | Server-Adresse, Sitzungs-Token; das Passwort nur bei eingeschalteter Biometrie |
| **Technik** | Flutter / Dart, `http`, `flutter_secure_storage`, `local_auth`, `mobile_scanner`, `flutter_local_notifications`, `workmanager` |

> **QR-Code zeigt `http://`?** Dann ist am Server keine `SITE_URL` gesetzt. Die App
> probiert trotzdem zuerst HTTPS. Dauerhaft beheben: `SITE_URL=https://…` am Server setzen.

> **Benachrichtigungen:** Der Server hat (noch) keinen Push-Dienst. Die App fragt deshalb
> selbst nach. Unter iOS geht das nur, solange die App offen ist.

---

## Herunterladen

- **Release:** die APK hängt am [neuesten Release](https://github.com/Phydran6/RIMPERIO-App/releases/latest)
  (entsteht automatisch, sobald ein Tag `v…` gepusht wird).
- **Jeder Stand:** jeder [CI-Lauf](https://github.com/Phydran6/RIMPERIO-App/actions/workflows/ci.yml)
  hat 30 Tage lang die APK als Artefakt `android-apk` (Anmeldung bei GitHub nötig).

Die APK ist mit dem Debug-Schlüssel von Flutter signiert — zum direkten
Installieren gedacht, nicht für den Play Store.

---

## Bauen

Dieses Repo enthält die Quelle (`lib/`, `pubspec.yaml`, `assets/`). Die
plattform-spezifischen Ordner (`android/`, `ios/`) erzeugt ein Skript, das sie
auch gleich fertig einrichtet — App-Name **RIMPERIO**, Berechtigungen (Internet,
Kamera, Benachrichtigungen, Biometrie), FragmentActivity, Desugaring, iOS-Texte im
Release, App-Symbol:

```bash
git clone https://github.com/Phydran6/RIMPERIO-App && cd RIMPERIO-App

bash scripts/setup_platforms.sh   # unter Windows in der Git Bash

flutter run            # auf angeschlossenem Gerät/Emulator
flutter build apk      # Release-APK
```

> **HTTP-Server im LAN:** Android blockiert unverschlüsseltes HTTP ab Werk. Spricht
> dein Server nur `http://`, das Skript mit `RIMPERIO_CLEARTEXT=1 bash scripts/setup_platforms.sh`
> aufrufen — oder besser am Server HTTPS einschalten (der Server kann das
> automatisch, siehe `RIMPERIO_SITE_ADDRESS`).

---

## App-Symbol

Das Symbol kommt aus [`assets/icon/`](assets/icon/) und wird von
[`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) in
alle Größen für Android und iOS gerechnet (Einstellungen in
[`pubspec.yaml`](pubspec.yaml)):

| Datei | Wofür |
|---|---|
| [`icon.png`](assets/icon/icon.png) | 1024², vollflächig, ohne Rahmen — iOS und ältere Android-Versionen runden selbst ab |
| [`icon_foreground.png`](assets/icon/icon_foreground.png) | Android 8+ (adaptiv): Logo in der Sicherheitszone, Hintergrund `#030B1A` — die Wortmarke bleibt in jeder Launcher-Form ganz |
| [`rimperio_logo.png`](assets/icon/rimperio_logo.png) | Logo mit Goldrahmen, transparente Ecken — für die Einrichtungsseite und dieses README |

Neues Logo? Die drei Dateien ersetzen und `dart run flutter_launcher_icons` ausführen.

---

## Dateien

| Datei | Wofür |
|---|---|
| [`lib/main.dart`](lib/main.dart) | Einstieg: Einrichtung → Anmeldung → Sperre → App |
| [`lib/core/session.dart`](lib/core/session.dart) | Sitzungszustand, Token-Ablauf, Biometrie-Neuanmeldung |
| [`lib/core/api.dart`](lib/core/api.dart) | Client für `/api/auth/*` und `/api/app/*` |
| [`lib/core/server_address.dart`](lib/core/server_address.dart) | Adresse aufbereiten, HTTPS als Vorgabe |
| [`lib/core/qr_login.dart`](lib/core/qr_login.dart) | Inhalt des Anmelde-QR-Codes |
| [`lib/core/biometrics.dart`](lib/core/biometrics.dart) | Fingerabdruck / Face ID |
| [`lib/core/notifications.dart`](lib/core/notifications.dart) | Berechtigung, Abfrage, System-Benachrichtigungen |
| [`lib/core/storage.dart`](lib/core/storage.dart) | verschlüsselte Ablage |
| [`lib/screens/`](lib/screens/) | Einrichtung, QR-Scan, Anmeldung, Sperre, Übersicht, Logs, Geräte, Meldungen, Updates, SNMP, Mehr |
| [`lib/ui/`](lib/ui/) | Farben, gemeinsame Bausteine |
| [`scripts/setup_platforms.sh`](scripts/setup_platforms.sh) | erzeugt und konfiguriert `android/` und `ios/` |
| [`test/widget_test.dart`](test/widget_test.dart) | Tests: Adressen, QR-Code, Token-Ablauf, Einrichtung |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI: Analyse, Tests, APK, iOS-Build, Release bei Tag |

---

## Mögliche Erweiterungen

- **Echter Push** (FCM/APNs) — braucht einen Push-Versand am Server.
- **Refresh-Token** am Server, damit auch QR- und MFA-Anmeldungen nach 24 h ohne neue Anmeldung weiterlaufen.

---

## Lizenz

[MIT](LICENSE) — wie alle Teile des Projekts.
