# RIMPERIO-App

Die eigene RIMPERIO-Instanz am Handy — eine schlanke **Flutter**-App, die als
gehärtete WebView auf deinen [RIMPERIO-Server](https://github.com/Phydran6/RIMPERIO-Server)
zeigt. Eine Codebasis für **Android und iOS**.

← [Übersicht](https://github.com/Phydran6/RIMPERIO) · [Server](https://github.com/Phydran6/RIMPERIO-Server)

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

## Bauen

Dieses Repo enthält die Quelle (`lib/`, `pubspec.yaml`). Die plattform-
spezifischen Ordner (`android/`, `ios/`) erzeugt Flutter einmalig selbst:

```bash
git clone https://github.com/Phydran6/RIMPERIO-App && cd RIMPERIO-App

# android/ios/... erzeugen, ohne lib/ anzutasten
flutter create --org de.phytech --project-name rimperio_app .

flutter pub get
flutter run            # auf angeschlossenem Gerät/Emulator
flutter build apk      # Release-APK
```

> **HTTP-Server im LAN:** Android blockiert unverschlüsseltes HTTP ab Werk. Wenn
> dein Server nur `http://` spricht, in `android/app/src/main/AndroidManifest.xml`
> im `<application>`-Tag `android:usesCleartextTraffic="true"` setzen — oder am
> Server HTTPS einschalten (empfohlen; der Server kann das automatisch, siehe
> `LRMM_SITE_ADDRESS` → `RIMPERIO_SITE_ADDRESS`).

---

## Dateien

| Datei | Wofür |
|---|---|
| [`lib/main.dart`](lib/main.dart) | Einstieg: Server vorhanden → WebView, sonst Einrichtung |
| [`lib/setup_page.dart`](lib/setup_page.dart) | Server-Adresse eingeben und speichern |
| [`lib/webview_page.dart`](lib/webview_page.dart) | die WebView samt Zurück-Navigation und „Server ändern" |
| [`lib/storage.dart`](lib/storage.dart) | verschlüsselte Ablage der Adresse |

---

## Mögliche Erweiterungen

- **App-Sperre per Biometrie** (`local_auth`) wie bei der LogBot-App — dafür muss
  `MainActivity` von `FlutterFragmentActivity` erben.
- **QR-Code-Einrichtung**: Server-Adresse (und optional ein Token) per QR aus der
  Weboberfläche scannen.

---

## Lizenz

[MIT](LICENSE) — wie alle Teile des Projekts.
