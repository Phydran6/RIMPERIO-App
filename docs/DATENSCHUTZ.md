# Datenschutzerklärung

**RIMPERIO** (Android/iOS-App) · Stand: 22. November 2026

Diese Erklärung beschreibt, welche Daten die App verarbeitet. Sie ist kurz,
weil die App mit niemandem außer **deinem eigenen Server** spricht.

---

## Kurzfassung

RIMPERIO ist die App zu einem **selbst gehosteten** RIMPERIO-Server. Die App
verbindet sich ausschließlich mit der Server-Adresse, die du selbst einträgst
(oder per QR-Code aus deiner Weboberfläche übernimmst). **Wir – der Entwickler
der App – betreiben keinen Server, bekommen keine Daten und sehen nichts davon.**

Es gibt keine Werbung, kein Tracking, keine Analyse-Werkzeuge, keine
Absturzberichte an Dritte und keine Weitergabe von Daten.

---

## Verantwortlich

Für die **App** (diese Erklärung):

Philipp Fischer
Kontakt: über [GitHub-Issues](https://github.com/Phydran6/RIMPERIO-App/issues) oder
die im GitHub-Profil angegebene Adresse

Für die **Daten auf deinem RIMPERIO-Server** ist verantwortlich, wer diesen
Server betreibt – also du selbst bzw. deine Organisation.

---

## Was auf dem Gerät bleibt

Diese Daten liegen **verschlüsselt** im sicheren Speicher des Geräts
(Android Keystore bzw. iOS Keychain) und verlassen das Gerät nicht – außer
in Richtung deines eigenen Servers, wie unten beschrieben:

- die Adresse deines RIMPERIO-Servers
- dein Benutzername und das Sitzungs-Token der Anmeldung
- dein Passwort – **nur**, wenn du die Entsperrung per Fingerabdruck /
  Gesichtserkennung eingeschaltet hast (damit die App dich nach Ablauf der
  Sitzung still neu anmelden kann)
- Einstellungen: Biometrie an/aus, Benachrichtigungen an/aus, die Kennung der
  zuletzt angezeigten Meldung, ob du eine unverschlüsselte `http://`-Verbindung
  ausdrücklich bestätigt hast

**Abmelden** löscht das Sitzungs-Token. **Deinstallieren** löscht alle Daten der
App vom Gerät.

---

## Was zu deinem Server geht

Die App ruft die Schnittstelle deines RIMPERIO-Servers auf
(`/api/auth/*` und `/api/app/*`):

| Wann | Was |
|:--|:--|
| Anmeldung | Benutzername und Passwort, ggf. der Code des Zweitfaktors – oder das einmalige Token aus dem QR-Code |
| Danach | das Sitzungs-Token bei jeder Anfrage |
| Benachrichtigungen | regelmäßige Abfrage neuer Meldungen (im Vordergrund etwa jede Minute, unter Android im Hintergrund etwa alle 15 Minuten) |

Angezeigt werden die Daten, die dein Server liefert: Geräte, Logs, Meldungen,
Updates/Freigaben, SNMP-Werte. Die App speichert diese Inhalte **nicht**
dauerhaft; sie hält sie nur, solange sie angezeigt werden.

**Verschlüsselung:** Die App verbindet sich standardmäßig über **HTTPS**. Eine
unverschlüsselte `http://`-Verbindung ist nur nach einer ausdrücklichen Warnung
und deiner Bestätigung möglich und wird danach dauerhaft rot markiert.

Was dein Server mit diesen Daten macht (z. B. Protokolle der Anmeldungen),
richtet sich nach dessen Betreiber.

---

## Was die App *nicht* tut

- **Keine Werbung.** Keine Werbekennung, keine Werbenetzwerke
- **Kein Tracking.** Kein Analyse-Werkzeug, keine Nutzungsstatistik, keine
  Absturzberichte an Dritte
- **Keine Verbindung zu uns.** Die App kennt keinen Server des Entwicklers
- **Kein Standort, keine Kontakte, keine Fotos.** Die App fragt nicht danach
- **Kein Verkauf von Daten.** An niemanden, zu keinem Preis

---

## Berechtigungen

| Berechtigung | Wofür |
|:--|:--|
| **Internet** | Verbindung zu deinem eigenen RIMPERIO-Server |
| **Kamera** | Nur zum Scannen des Anmelde-QR-Codes. Die Bilder werden auf dem Gerät ausgewertet, nicht gespeichert und nicht übertragen. Ohne Kamera geht die Anmeldung per Passwort |
| **Face ID / Fingerabdruck** | Nur zum Entsperren der App. Biometrische Daten verlassen das Gerät nicht und sind für die App nicht lesbar – das Betriebssystem meldet nur „passt" oder „passt nicht" |
| **Benachrichtigungen** | Meldungen deines Servers als System-Benachrichtigung anzeigen. Abschaltbar |
| **Nach dem Neustart starten** | Damit die Hintergrund-Abfrage der Meldungen (Android) nach einem Neustart weiterläuft |

---

## Deine Rechte

Du hast Anspruch auf Auskunft, Berichtigung, Löschung, Einschränkung der
Verarbeitung, Datenübertragbarkeit und Widerspruch (Art. 15–21 DSGVO).

Da der Entwickler keine Daten von dir hat, richten sich diese Rechte in Bezug
auf dein Benutzerkonto an den **Betreiber deines RIMPERIO-Servers**. Dein Konto
und die dazugehörigen Daten löscht der Administrator dieses Servers.

Die Daten auf dem Gerät löschst du selbst: Abmelden bzw. die App deinstallieren.

Du kannst dich außerdem bei einer Datenschutz-Aufsichtsbehörde beschweren.

---

## Kinder

Die App ist ein Werkzeug für Administratoren und richtet sich an Erwachsene.
Sie verarbeitet keine Daten von Kindern.

---

## Änderungen

Änderungen an dieser Erklärung sind über die
[Versionsgeschichte dieser Datei](https://github.com/Phydran6/RIMPERIO-App/commits/main/docs/DATENSCHUTZ.md)
nachvollziehbar. Der Stand oben nennt das Datum der letzten Änderung.
