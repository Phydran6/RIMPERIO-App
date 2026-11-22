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

- **Release:** APK und AAB hängen am [neuesten Release](https://github.com/Phydran6/RIMPERIO-App/releases/latest).
  Releases entstehen **vollautomatisch**: Bei jedem Push auf `main`, der etwas an der
  App ändert (`lib/`, `assets/`, `pubspec.yaml`, `scripts/setup_platforms.sh`),
  vergibt die CI Version und Versionscode selbst und legt das Release an. Reine
  Doku-/CI-Änderungen lösen keins aus; *Actions → CI → Run workflow* erzwingt eins.

  | | Herkunft | Beispiel |
  |---|---|---|
  | Versionsname | Datum (Europe/Berlin), am selben Tag mit `.2`, `.3` … | `2026.11.23` |
  | Versionscode | 100 + fortlaufende CI-Laufnummer — steigt immer | `142` |

  Die `version:` in `pubspec.yaml` gilt nur noch für lokale Builds.
- **Jeder Stand:** jeder [CI-Lauf](https://github.com/Phydran6/RIMPERIO-App/actions/workflows/ci.yml)
  hat 30 Tage lang die APK als Artefakt `android-apk` (Anmeldung bei GitHub nötig).

Die APK ist mit dem Debug-Schlüssel von Flutter signiert — zum direkten
Installieren gedacht, nicht für den Play Store. Für den Play Store siehe
[Google Play Store](#google-play-store).

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

## Google Play Store

Der Play Store will ein **Android App Bundle (`.aab`)**, signiert mit deinem
eigenen **Upload-Schlüssel** (Google signiert die App danach selbst neu —
*Play App Signing*).

**1. Upload-Schlüssel anlegen** (einmalig):

```bash
bash scripts/create_upload_key.sh
```

Das legt `upload-keystore.jks` und `key.properties` im Repo-Ordner an (beide
per `.gitignore` ausgeschlossen). **Beides sicher aufbewahren** — ohne den
Schlüssel kannst du keine Updates mehr hochladen.

**2a. AAB lokal bauen** (braucht Android-SDK, z. B. über Android Studio):

```bash
bash scripts/setup_platforms.sh   # bindet key.properties in android/ ein
flutter build appbundle
# → build/app/outputs/bundle/release/app-release.aab
```

**2b. … oder von der CI bauen lassen** — unter *Settings → Secrets and variables
→ Actions* anlegen:

| Secret | Inhalt |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Passwort |
| `ANDROID_KEY_PASSWORD` | Passwort (dasselbe) |
| `ANDROID_KEY_ALIAS` | `upload` |

Danach hängt an jedem CI-Lauf zusätzlich das Artefakt `android-aab`, und jedes
GitHub-Release enthält neben der APK auch die `.aab`.

**3. Hochladen:** [Play Console](https://play.google.com/console) → App anlegen →
*Testen und veröffentlichen* → z. B. *Interner Test* → Release erstellen → `.aab`
hochladen.

> **Versionscode:** Jede hochgeladene AAB braucht einen höheren Versionscode —
> den vergibt die CI automatisch (siehe [Herunterladen](#herunterladen)).
> Einfach die `.aab` aus dem neuesten Release nehmen.

> **„Mit dem falschen Schlüssel signiert“?** Dann kennt die Play Console einen
> anderen Upload-Schlüssel. Der Fingerabdruck der CI-AAB steht im Protokoll des
> Schritts *Play-Store-Bundle (AAB) bauen*. Entweder den passenden Schlüssel in
> die Secrets legen oder in der Play Console unter *Einstellungen →
> App-Integrität → Upload-Schlüssel zurücksetzen* das neue Zertifikat
> (`keytool -export -rfc -alias upload -keystore upload-keystore.jks -file upload_certificate.pem`)
> hochladen.

> **Paketname:** `de.phytech.rimperio_app` — lässt sich nach dem ersten Upload
> nicht mehr ändern.

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
| [`scripts/create_upload_key.sh`](scripts/create_upload_key.sh) | Upload-Schlüssel + `key.properties` für den Play Store |
| [`test/widget_test.dart`](test/widget_test.dart) | Tests: Adressen, QR-Code, Token-Ablauf, Einrichtung |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI: Analyse, Tests, APK, iOS-Build, Release bei neuer Version auf `main` oder Tag |

---

## Mögliche Erweiterungen

- **Echter Push** (FCM/APNs) — braucht einen Push-Versand am Server.
- **Refresh-Token** am Server, damit auch QR- und MFA-Anmeldungen nach 24 h ohne neue Anmeldung weiterlaufen.

---

## Datenschutz

Siehe [docs/DATENSCHUTZ.md](docs/DATENSCHUTZ.md) — die App spricht nur mit deinem eigenen Server; kein Tracking, keine Werbung.

---

## Lizenz

[MIT](LICENSE) — wie alle Teile des Projekts.
