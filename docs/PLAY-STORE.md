# Google Play Store

So kommt RIMPERIO in den Play Store – vom Signaturschlüssel über den
automatischen Build bis zu den Antworten in der Play Console.

| | |
|:--|:--|
| **Paketname** | `de.phytech.rimperio_app` (nach dem ersten Upload nicht mehr änderbar) |
| **App-Name** | RIMPERIO |
| **Datenschutzerklärung** | <https://github.com/Phydran6/RIMPERIO-App/blob/main/docs/DATENSCHUTZ.md> |
| **Store-Grafiken** | [`store/`](../store/) – Beschreibung in [`store/README.md`](../store/README.md) |

---

## Überblick

```
Push auf main ──► CI (GitHub Actions)
                   ├─ Version + Versionscode automatisch vergeben
                   ├─ analysieren, testen
                   ├─ APK bauen (Debug-Schlüssel, zum direkten Installieren)
                   ├─ AAB bauen (Upload-Schlüssel aus den Secrets) ──► Play Store
                   └─ App geändert? ──► GitHub-Release mit APK + AAB
```

Für ein Update im Play Store: `.aab` aus dem
[neuesten Release](https://github.com/Phydran6/RIMPERIO-App/releases/latest)
herunterladen und in der Play Console hochladen. Mehr ist nicht zu tun.

---

## 1. Signatur

Der Play Store nimmt nur ein **Android App Bundle (`.aab`)**, das mit dem
**Upload-Schlüssel** der App signiert ist. Google signiert die App danach
selbst neu (*Play App Signing*) – der Upload-Schlüssel beweist nur, dass das
Bundle von uns kommt.

| | |
|:--|:--|
| Schlüsseldatei | `upload-keystore.jks` (PKCS12, RSA 2048, 10 000 Tage gültig) |
| Alias | `upload` |
| Zugangsdaten lokal | `key.properties` im Repo-Ordner |
| SHA1 | `E7:96:67:63:D0:6C:30:5A:5B:74:7F:E6:DD:B5:0C:F1:35:A8:2D:C8` |
| SHA256 | `07:E7:E6:EE:DE:12:FD:7E:7A:EF:90:6F:B6:A4:B9:55:D8:22:50:44:C5:88:BA:89:E5:D0:90:93:AD:98:F4:9B` |

> **`upload-keystore.jks` und `key.properties` sind NICHT im Repo** (per
> `.gitignore` ausgeschlossen) und **außerhalb gesichert**. Aus den
> GitHub-Secrets lässt sich der Schlüssel nicht mehr auslesen. Ohne ihn keine
> Updates – dann bleibt nur, den Upload-Schlüssel zurücksetzen zu lassen
> (siehe [Probleme](#probleme)).

### Neuen Schlüssel anlegen (nur falls nötig)

```bash
bash scripts/create_upload_key.sh   # Git Bash unter Windows; braucht keytool (JDK)
```

Legt `upload-keystore.jks` und `key.properties` an und gibt aus, was in die
GitHub-Secrets gehört.

### GitHub-Secrets

*Settings → Secrets and variables → Actions*:

| Secret | Inhalt |
|:--|:--|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Passwort des Keystores |
| `ANDROID_KEY_PASSWORD` | Passwort des Schlüssels (bei PKCS12 dasselbe) |
| `ANDROID_KEY_ALIAS` | `upload` |

Fehlen die Secrets (z. B. bei Pull Requests aus Forks), baut die CI nur die
APK und überspringt die AAB.

### Wie die Signatur in den Build kommt

`android/` ist nicht im Repo, sondern wird von
[`scripts/setup_platforms.sh`](../scripts/setup_platforms.sh) erzeugt. Das
Skript ergänzt `android/app/build.gradle.kts` um:

- `key.properties` aus dem Repo-Wurzelordner laden,
- eine `release`-Signatur daraus,
- Release-Builds damit signieren – fehlt `key.properties`, mit dem
  Debug-Schlüssel (Warnung im Build-Protokoll).

Die CI schreibt `key.properties` aus den Secrets, baut und löscht Datei und
Keystore danach wieder.

---

## 2. Versionen und Releases (vollautomatisch)

In `pubspec.yaml` muss **nichts** geändert werden. Die CI
([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) vergibt selbst:

| | Herkunft | Beispiel |
|:--|:--|:--|
| **Versionsname** | Datum (Europe/Berlin); am selben Tag `.2`, `.3` … | `2026.11.23` |
| **Versionscode** | 100 + fortlaufende CI-Laufnummer – steigt immer | `142` |

**Wann ein Release entsteht:** bei einem Push auf `main`, wenn sich seit dem
letzten Release etwas an der App geändert hat:

- `lib/`, `assets/`, `pubspec.yaml`, `scripts/setup_platforms.sh`

Reine Doku-, CI- oder Store-Grafik-Änderungen lösen **kein** Release aus.
Von Hand erzwingen: *Actions → CI → Run workflow* (auf `main`).

Das Release (Tag `v<Version>`) enthält:

| Datei | Wofür |
|:--|:--|
| `RIMPERIO-<Version>-<Code>.aab` | Play Console |
| `RIMPERIO-<Version>.apk` | direkt aufs Handy installieren (Debug-signiert) |

Im Protokoll des Schritts *Play-Store-Bundle (AAB) bauen* steht der
Fingerabdruck der AAB – er muss zum Upload-Schlüssel in der Play Console
passen.

> Die `version:` in `pubspec.yaml` gilt nur noch für lokale Builds.
> Ändert sich der Name der Workflow-Datei, beginnt die Laufnummer neu – dann
> den Versatz `100` in der CI so erhöhen, dass der Code weiter steigt.

### Lokal bauen (optional)

Braucht das Android-SDK (z. B. über Android Studio) und `key.properties`:

```bash
bash scripts/setup_platforms.sh
flutter build appbundle --build-name 2026.11.23 --build-number 999
# → build/app/outputs/bundle/release/app-release.aab
```

Der Versionscode muss höher sein als der zuletzt hochgeladene.

---

## 3. Hochladen

[Play Console](https://play.google.com/console) → RIMPERIO →
*Testen und veröffentlichen* → z. B. *Interner Test* → *Neuen Release
erstellen* → `.aab` hochladen.

| Feld | Eintrag |
|:--|:--|
| Release-Name | schlägt die Play Console aus der AAB vor – übernehmen |
| Versionshinweise | siehe unten |

```
<de-DE>
Erste Testversion von RIMPERIO.
</de-DE>
```

---

## 4. Store-Eintrag

### Texte

**App-Name:** `RIMPERIO`

**Kurzbeschreibung** (max. 80 Zeichen):

> Dein RMM-Server am Handy: Geräte, Logs, Meldungen und Updates im Blick.

**Vollständige Beschreibung:**

> RIMPERIO ist die App zu deinem selbst gehosteten RIMPERIO-Server – Fernüberwachung und Verwaltung deiner Windows- und Linux-Geräte, jederzeit dabei.
>
> • Übersicht: Zustand aller Geräte auf einen Blick
> • Geräte: Details, Status und Erreichbarkeit
> • Logs: zentrale Syslog-Einträge durchsuchen
> • Meldungen: Warnungen als Benachrichtigung aufs Handy
> • Updates & Freigaben: Patches prüfen, freigeben oder zurückrollen – mit KI-Einschätzung
> • SNMP: Netzwerkgeräte überwachen
>
> Anmeldung per QR-Code aus der Weboberfläche oder mit Benutzer und Passwort (inkl. Zweitfaktor). Fingerabdruck bzw. Gesichtserkennung schützen den Zugang. Zugangsdaten werden verschlüsselt auf dem Gerät gespeichert, die Verbindung läuft standardmäßig über HTTPS.
>
> Hinweis: Die App benötigt einen eigenen RIMPERIO-Server.

### Grafiken

Alle in [`store/`](../store/), erzeugt mit
[`scripts/store/make_store_graphics.ps1`](../scripts/store/make_store_graphics.ps1):

| Feld in der Play Console | Datei(en) |
|:--|:--|
| App-Symbol (512×512) | `store/icon-512.png` |
| Vorstellungsgrafik (1024×500) | `store/feature-graphic-1024x500.png` |
| Screenshots Telefon | `store/screenshots/telefon/01…06` |
| Screenshots 7"-Tablet | `store/screenshots/tablet-7/01…06` |
| Screenshots 10"-Tablet | `store/screenshots/tablet-10/01…06` |

### Kategorie und Kontakt

| | |
|:--|:--|
| Typ | App |
| Kategorie | Tools |
| Website | <https://github.com/Phydran6/RIMPERIO> |
| E-Mail | Support-Adresse des Entwicklerkontos |

---

## 5. App-Inhalte (Fragebögen)

Die Antworten beruhen darauf, was die App laut Code tatsächlich tut – siehe
auch die [Datenschutzerklärung](DATENSCHUTZ.md).

| Punkt | Antwort |
|:--|:--|
| **Datenschutzerklärung** | <https://github.com/Phydran6/RIMPERIO-App/blob/main/docs/DATENSCHUTZ.md> |
| **Anmeldedaten** | „Für alle oder einige Funktionen ist eine Anmeldung erforderlich“ – Demo-Zugang hinterlegen (siehe unten) |
| **Anzeigen** | Nein |
| **Einstufung des Inhalts** | Kategorie „Alle anderen App-Typen“; alle Fragen zu Gewalt, Sexualität, Sprache, Drogen, Glücksspiel: Nein; Nutzer interagieren/teilen Inhalte: Nein → USK 0 / PEGI 3 |
| **Zielgruppe** | Nur 18 Jahre und älter; spricht Kinder nicht an |
| **Behörden-Apps** | Nein |
| **Finanzfunktionen** | Keine |
| **Gesundheit** | Keine |

### Anmeldedaten für die Prüfer

Die Prüfer brauchen einen **von außen erreichbaren Server** und ein Konto
**ohne Zweitfaktor** – sonst wird die App abgelehnt. Hinweistext:

> Die App verbindet sich mit einem selbst gehosteten RIMPERIO-Server. Beim ersten Start „Server-Adresse“ eingeben: `https://<demo-server>`, dann „Mit Benutzer/Passwort anmelden“. Benutzer: `<demo>` · Passwort: `<…>`

Zugangsdaten **nur in der Play Console** eintragen, nicht hier im Repo.

### Datensicherheit

| Frage | Antwort |
|:--|:--|
| Erhebt oder teilt die App Nutzerdaten? | Ja, erhebt – teilt nicht |
| Datenart | Persönliche Daten → **Nutzer-IDs** (Benutzername) |
| Erhebung optional? | Nein |
| Zweck | App-Funktionen, Kontoverwaltung |
| Alle Daten bei der Übertragung verschlüsselt? | **Nein** – HTTPS ist Standard, `http://` ist aber nach Warnung möglich |
| Können Nutzer die Löschung beantragen? | Ja – beim Administrator ihres RIMPERIO-Servers |

Nicht als „erhoben“ gelten: Kamerabilder (QR-Code, nur auf dem Gerät
ausgewertet), Biometrie (nur „passt/passt nicht“ vom System), die
verschlüsselt auf dem Gerät gespeicherten Daten.

---

## Probleme

**„Dein Android App Bundle ist mit dem falschen Schlüssel signiert“**
Die App in der Play Console erwartet einen anderen Upload-Schlüssel. Den
SHA1-Fingerabdruck aus der Meldung mit dem oben vergleichen. Erst prüfen, ob
die richtige App geöffnet ist (Paketname `de.phytech.rimperio_app` unter
*App-Integrität*). Sonst:

- App noch nie veröffentlicht → löschen und neu anlegen, beim Signieren
  „Von Google generierten Schlüssel verwenden“; der erste Upload legt den
  Upload-Schlüssel fest.
- sonst *App-Integrität → Upload-Schlüssel zurücksetzen* und das Zertifikat
  hochladen (dauert meist 1–2 Tage):

  ```bash
  keytool -export -rfc -alias upload -keystore upload-keystore.jks -file upload_certificate.pem
  ```

**Paketname passt nicht**
Eine bestehende App mit anderem Paketnamen (z. B. eine frühere Version unter
`rimperio.phytech.de`) nimmt dieses Bundle nicht an. Neue App mit
`de.phytech.rimperio_app` anlegen.

**„Versionscode wurde bereits verwendet“**
Eine ältere AAB erwischt – die aus dem neuesten Release nehmen, oder per
*Run workflow* ein neues Release erzwingen.

**Keine AAB im CI-Lauf**
Secrets fehlen oder sind leer (Schritt *Upload-Schlüssel einrichten* meldet
„Keine Signatur-Secrets“).
