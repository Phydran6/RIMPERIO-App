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
keine WebView. Untere Navigationsleiste mit **Übersicht, Geräte, Meldungen, Mehr**.
Unter **Mehr** liegen die Bereiche:

| Bereich | Was |
|---|---|
| **Logs** | eigener Bereich: *Ansehen* (nur Warnung, Fehler, Kritisch – ohne Info/Hinweis), *Suchen* (alle Stufen inkl. Info/Hinweis, Text, Gerät, Zeitraum), *Themenbereiche*, *Rauschen & Sperren*, *Sperrregeln*, *Aufbewahrung*. Jede Zeile im Klartext mit Hinweis, „Diese Meldung sperren“, „KI erklärt“. Die Kacheln der Übersicht führen weiter direkt in die Logs |
| **Updates & Freigaben** | Freigeben/ablehnen (KI-Einschätzung), je Update **Stufe** (Normal / Wichtig / Kritisch) und **Dringlichkeit** (sofort / zeitnah / irgendwann) – Sofortiges und Kritisches steht oben, der Startbildschirm färbt sich rot, wenn etwas sofort freigegeben werden muss. **Installieren**: alle offenen Updates je Rechner und Container, freigegebene sofort einspielen (ein Lauf mit Snapshot, Prüfung, Rückweg), Läufe mit Verlauf, Zurückrollen |
| **DB-Updates** | Datenbank-Container mit Sicherung und Probelauf prüfen, Bericht lesen, freigeben |
| **Proxmox** | Updates der Knoten installieren, Neustart, **„Alle Knoten patchen“** (rollierend, Knoten für Knoten mit Neustart nie/bei Kernel/immer) und **Zeitplan im Wartungsfenster** samt Verlauf, Shell auf dem Knoten, Konsole von Containern/VMs, Agent per `pct exec` in Container |
| **RIMPERIO-Server** | Version, Update starten, Protokoll mitlesen |
| **SNMP** | Geräte und Probleme |
| **App-Update** | wie beim Server: **einmal täglich automatisch** und jederzeit per „Jetzt prüfen“ nach der neuesten Version auf GitHub sehen. Gibt es eine, zeigt die App einen Punkt an *Mehr* (im Hintergrund eine Benachrichtigung) – und **„Herunterladen und installieren“** spielt sie ein: APK aus dem Release laden, Prüfsumme prüfen, Android fragt noch einmal nach, fertig. Tägliche Prüfung abschaltbar |

**Geräte** → Rechner mit Agent: **Shell** (Linux als Dienstkonto `rimperio`), **PowerShell**
(Windows), **RDP** (öffnet die RDP-App des Handys) und „RDP einschalten“.

| | |
|---|---|
| **Anmeldung** | QR-Code aus der Weboberfläche (*Benutzer → App verbinden*) oder Benutzer/Passwort, mit Zweitfaktor |
| **Biometrie** | Fingerabdruck / Face ID entsperrt die App; nach Passwort-Anmeldung meldet sie nach Ablauf der 24-h-Sitzung still neu an |
| **Verbindung** | immer zuerst HTTPS; `http://` nur nach Warnung, danach dauerhaft rot markiert |
| **Benachrichtigungen** | Berechtigung wird nach der Anmeldung erfragt; Abfrage im Vordergrund jede Minute, im Hintergrund (Android) etwa alle 15 min – mit eigenem Geräteschlüssel, der nicht nach 24 h abläuft. Gemeldet wird alles, was der Server unter *Meldungen → 📱* auswählt (Freigaben, Fehlschläge, Rechner offline, Checks, volle Platte, kritische Logzeilen …). *Mehr → Benachrichtigung testen* prüft Anzeige und Abfrage beim Server |
| **Gespeichert (verschlüsselt)** | Server-Adresse, Sitzungs-Token; das Passwort nur bei eingeschalteter Biometrie |
| **Technik** | Flutter / Dart, `http`, `flutter_secure_storage`, `local_auth`, `mobile_scanner`, `flutter_local_notifications`, `workmanager`, `url_launcher` (RDP), `package_info_plus` (App-Update) |

> **QR-Code zeigt `http://`?** Dann ist am Server keine `SITE_URL` gesetzt. Die App
> probiert trotzdem zuerst HTTPS. Dauerhaft beheben: `SITE_URL=https://…` am Server setzen.

> **App-Update per Knopfdruck** gibt es nur für die **APK aus dem GitHub-Release**
> (Android). Beim ersten Mal fragt Android, ob RIMPERIO Apps installieren darf
> („Aus dieser Quelle zulassen“). Aus dem **Play Store** installiert, kommen Updates
> über Google Play – die App prüft dann nicht selbst. Unter iOS zeigt sie nur die
> Version und verweist aufs Release.
>
> **Einmalig nötig:** Bis 2026.11.23 waren die APKs mit wechselnden Debug-Schlüsseln
> signiert. Wer so eine Version hat, deinstalliert die App einmal und installiert die
> neue APK – ab dann sind alle APKs mit demselben Schlüssel signiert und das Update
> per Knopfdruck klappt.

> **Benachrichtigungen:** Der Server hat (noch) keinen Push-Dienst. Die App fragt deshalb
> selbst nach – mit einem Geräteschlüssel, der nur Meldungen abholen darf und nicht nach
> 24 h abläuft (vorher verstummte die Hintergrundabfrage mit der Sitzung). Unter iOS geht
> das nur, solange die App offen ist. Braucht Server-API-Level 4.

---

## Herunterladen

- **Release:** APK und AAB hängen am [neuesten Release](https://github.com/Phydran6/RIMPERIO-App/releases/latest).
  Releases entstehen **vollautomatisch**: Bei jedem Push auf `main`, der etwas an der
  App ändert (`lib/`, `assets/`, `pubspec.yaml`, `scripts/setup_platforms.sh`, `scripts/android/`, `scripts/self_update_permission.sh`),
  vergibt die CI Version und Versionscode selbst und legt das Release an. Reine
  Doku-/CI-Änderungen lösen keins aus; *Actions → CI → Run workflow* erzwingt eins.

  | | Herkunft | Beispiel |
  |---|---|---|
  | Versionsname | Datum (Europe/Berlin), am selben Tag mit `.2`, `.3` … | `2026.11.23` |
  | Versionscode | 100 + fortlaufende CI-Laufnummer — steigt immer | `142` |

  Die `version:` in `pubspec.yaml` gilt nur noch für lokale Builds.
- **Jeder Stand:** jeder [CI-Lauf](https://github.com/Phydran6/RIMPERIO-App/actions/workflows/ci.yml)
  hat 30 Tage lang die Artefakte `android-apk` und `android-aab` (Anmeldung bei GitHub nötig).

| Datei | Signiert mit | Wofür |
|---|---|---|
| `RIMPERIO-<Version>.apk` | Upload-Schlüssel (immer derselbe) | direkt aufs Handy installieren; danach Updates per Knopfdruck (*Mehr → App-Update*) |
| `RIMPERIO-<Version>-<Code>.aab` | Upload-Schlüssel | [Google Play Store](#google-play-store) |

---

## Bauen

Dieses Repo enthält die Quelle (`lib/`, `pubspec.yaml`, `assets/`). Die
plattform-spezifischen Ordner (`android/`, `ios/`) erzeugt ein Skript, das sie
auch gleich fertig einrichtet — App-Name **RIMPERIO**, Berechtigungen (Internet,
Kamera, Benachrichtigungen, Biometrie, Selbst-Update), MainActivity, Desugaring,
iOS-Texte im Release, App-Symbol:

```bash
git clone https://github.com/Phydran6/RIMPERIO-App && cd RIMPERIO-App

bash scripts/setup_platforms.sh   # unter Windows in der Git Bash

flutter run            # auf angeschlossenem Gerät/Emulator
flutter build apk      # Release-APK
```

> **Für den Play Store** (eigenes AAB) das Selbst-Update weglassen:
> `RIMPERIO_SELF_UPDATE=0 bash scripts/setup_platforms.sh` – Google Play erlaubt
> keine Apps, die sich an Play vorbei aktualisieren. Die CI macht das von selbst.

> **HTTP-Server im LAN:** Android blockiert unverschlüsseltes HTTP ab Werk. Spricht
> dein Server nur `http://`, das Skript mit `RIMPERIO_CLEARTEXT=1 bash scripts/setup_platforms.sh`
> aufrufen — oder besser am Server HTTPS einschalten (der Server kann das
> automatisch, siehe `RIMPERIO_SITE_ADDRESS`).

---

## Google Play Store

Die App ist als **`de.phytech.rimperio_app`** in der Play Console angelegt.
Ein Update ist ein Handgriff: `.aab` aus dem
[neuesten Release](https://github.com/Phydran6/RIMPERIO-App/releases/latest)
nehmen und in der Play Console hochladen. Version, Versionscode und Signatur
erledigt die CI.

| | |
|---|---|
| **Anleitung** | [docs/PLAY-STORE.md](docs/PLAY-STORE.md) — Signatur, Secrets, Release-Ablauf, Store-Texte, Antworten der Fragebögen, Probleme |
| **Grafiken** | [store/](store/) — Symbol, Vorstellungsgrafik, Screenshots (Telefon, 7"/10"-Tablet); [store/README.md](store/README.md) |
| **Datenschutz** | [docs/DATENSCHUTZ.md](docs/DATENSCHUTZ.md) — die URL in der Play Console |
| **Upload-Schlüssel** | `upload-keystore.jks` + `key.properties` — **nicht im Repo**, extern gesichert, in der CI als Secrets |

> **Wichtig:** Ohne den Upload-Schlüssel lassen sich keine Updates mehr
> hochladen. Fingerabdrücke und das Vorgehen bei Verlust stehen in
> [docs/PLAY-STORE.md](docs/PLAY-STORE.md#1-signatur).

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
| [`lib/core/app_update.dart`](lib/core/app_update.dart) | App-Update: GitHub fragen, Versionen vergleichen, tägliche Prüfung, Download und Übergabe an Android |
| [`lib/screens/`](lib/screens/) | Einrichtung, QR-Scan, Anmeldung, Sperre, Übersicht, Logs (Bereich, Ansehen/Suchen), Geräte, Meldungen, Updates, DB-Updates, Proxmox, Server, Konsole/RDP, SNMP, Mehr |
| [`lib/ui/`](lib/ui/) | Farben, gemeinsame Bausteine |
| [`scripts/setup_platforms.sh`](scripts/setup_platforms.sh) | erzeugt und konfiguriert `android/` und `ios/` |
| [`scripts/android/MainActivity.kt`](scripts/android/MainActivity.kt) | Vorlage der Android-Activity: Biometrie, Prüfsumme und Installation des App-Updates |
| [`scripts/self_update_permission.sh`](scripts/self_update_permission.sh) | Selbst-Update-Berechtigung an (APK) / aus (Play-Store-AAB) |
| [`scripts/create_upload_key.sh`](scripts/create_upload_key.sh) | Upload-Schlüssel + `key.properties` für den Play Store |
| [`scripts/store/`](scripts/store/) | erzeugt die Store-Grafiken, macht persönliche Daten in Screenshots unkenntlich |
| [`store/`](store/) | Store-Grafiken: Symbol, Vorstellungsgrafik, Screenshots |
| [`docs/PLAY-STORE.md`](docs/PLAY-STORE.md) | Play Store: Signatur, Release-Ablauf, Store-Texte, Fragebögen |
| [`docs/DATENSCHUTZ.md`](docs/DATENSCHUTZ.md) | Datenschutzerklärung (URL für die Play Console) |
| [`test/widget_test.dart`](test/widget_test.dart) | Tests: Adressen, QR-Code, Token-Ablauf, Einrichtung |
| [`test/pages_test.dart`](test/pages_test.dart) | Tests gegen einen simulierten Server: Logs ansehen/suchen, Log-Bereich, Installieren, DB-Updates |
| [`test/app_update_test.dart`](test/app_update_test.dart) | Tests App-Update: Versionen, Release lesen, tägliche Prüfung, Seite |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI: Analyse, Tests, AAB (ohne Selbst-Update), APK (mit), iOS-Build; Version automatisch, Release bei App-Änderung auf `main` |

---

## Mögliche Erweiterungen

- **Echter Push** (FCM/APNs) — braucht einen Push-Versand am Server und ein Firebase-Projekt
  (`google-services.json`, APNs-Schlüssel) als CI-Secrets; erst damit gibt es Meldungen auch
  unter iOS im Hintergrund und ohne 15-min-Takt.
- **Volles Terminal** (xterm) für die Proxmox-Konsole — bisher ein schlanker Bildschirm ohne
  Vollbildprogramme (vim, top).
- **Refresh-Token** am Server, damit auch QR- und MFA-Anmeldungen nach 24 h ohne neue Anmeldung weiterlaufen.

---

## Datenschutz

Siehe [docs/DATENSCHUTZ.md](docs/DATENSCHUTZ.md) — die App spricht nur mit deinem eigenen Server; kein Tracking, keine Werbung.

---

## Lizenz

[MIT](LICENSE) — wie alle Teile des Projekts.
