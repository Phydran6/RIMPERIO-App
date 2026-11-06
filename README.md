<div align="center">

<img src="assets/icon/rimperio_logo.png" alt="RIMPERIO" width="160">

# RIMPERIO-App

**Die eigene RIMPERIO-Instanz am Handy**

Eine schlanke **Flutter**-App, die als gehärtete WebView auf deinen
[RIMPERIO-Server](https://github.com/Phydran6/RIMPERIO-Server) zeigt.
Eine Codebasis für **Android und iOS**.

[![CI](https://github.com/Phydran6/RIMPERIO-App/actions/workflows/ci.yml/badge.svg)](https://github.com/Phydran6/RIMPERIO-App/actions/workflows/ci.yml)
[![Android](https://img.shields.io/badge/Android-APK-3DDC84?logo=android&logoColor=white)](https://github.com/Phydran6/RIMPERIO-App/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

← [Übersicht](https://github.com/Phydran6/RIMPERIO) · [Server](https://github.com/Phydran6/RIMPERIO-Server)

</div>

---

## Prinzip

Wie bei der LogBot-App: Die App reicht die volle Weboberfläche durch und merkt
sich nur **wohin** sie zeigt. Die Anmeldung (Sitzungs-Token) bleibt in der WebView
— die App speichert nur die Server-Adresse, verschlüsselt über
`flutter_secure_storage`.

| | |
|---|---|
| **Technik** | Flutter / Dart, `webview_flutter`, `flutter_secure_storage` |
| **Plattformen** | Android &amp; iOS |
| **Was gespeichert wird** | nur die Server-Adresse (verschlüsselt) |

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
auch gleich fertig einrichtet — App-Name **RIMPERIO**, Internet-Berechtigung im
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
| [`lib/main.dart`](lib/main.dart) | Einstieg: Server vorhanden → WebView, sonst Einrichtung |
| [`lib/setup_page.dart`](lib/setup_page.dart) | Server-Adresse eingeben und speichern |
| [`lib/webview_page.dart`](lib/webview_page.dart) | die WebView samt Zurück-Navigation und „Server ändern" |
| [`lib/storage.dart`](lib/storage.dart) | verschlüsselte Ablage der Adresse |
| [`scripts/setup_platforms.sh`](scripts/setup_platforms.sh) | erzeugt und konfiguriert `android/` und `ios/` |
| [`test/widget_test.dart`](test/widget_test.dart) | Tests der Einrichtungsseite |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI: Analyse, Tests, APK, iOS-Build, Release bei Tag |

---

## Mögliche Erweiterungen

- **App-Sperre per Biometrie** (`local_auth`) wie bei der LogBot-App — dafür muss
  `MainActivity` von `FlutterFragmentActivity` erben.
- **QR-Code-Einrichtung**: Server-Adresse (und optional ein Token) per QR aus der
  Weboberfläche scannen.

---

## Lizenz

[MIT](LICENSE) — wie alle Teile des Projekts.
