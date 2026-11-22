# Store-Grafiken

Grafiken für den Google-Play-Store-Eintrag. Wohin sie in der Play Console
gehören und die Store-Texte stehen in [`docs/PLAY-STORE.md`](../docs/PLAY-STORE.md).

| Datei / Ordner | Format | Play Console |
|:--|:--|:--|
| [`icon-512.png`](icon-512.png) | 512×512 PNG, ohne Transparenz | App-Symbol |
| [`feature-graphic-1024x500.png`](feature-graphic-1024x500.png) | 1024×500 PNG | Vorstellungsgrafik |
| [`screenshots/telefon/`](screenshots/telefon/) | 1080×1920 (9:16) | Screenshots für Telefon |
| [`screenshots/tablet-7/`](screenshots/tablet-7/) | 1200×1920 | Screenshots für 7"-Tablet |
| [`screenshots/tablet-10/`](screenshots/tablet-10/) | 1920×1200 (quer) | Screenshots für 10"-Tablet |
| [`screenshots/geschwaerzt/`](screenshots/geschwaerzt/) | 1080×2340 | Zwischenstufe: Handy-Screenshot nach dem Unkenntlichmachen |
| `screenshots/roh/` | 1080×2340 | Original-Screenshots – **nicht im Repo** (echte Daten) |

Die Screenshots in der Reihenfolge 01 bis 06 hochladen:

| Nr. | Bildschirm | Überschrift |
|:--|:--|:--|
| 01 | Übersicht | Alles auf einen Blick |
| 02 | Geräte | Jedes Gerät im Blick |
| 03 | Meldungen | Meldungen sofort aufs Handy |
| 04 | Updates → Läufe | Updates freigeben und zurückrollen |
| 05 | Logs | Zentrale Logs durchsuchen |
| 06 | Mehr | Biometrie, MFA und HTTPS |

## Datenschutz in den Screenshots

Die Screenshots stammen von einem echten Server. Vor dem Einbau werden
**Hostnamen, IP-Adressen, die Server-Adresse, Benutzernamen sowie Container-,
Paket- und Sicherungsnamen** unkenntlich gemacht: Der Bereich wird auf etwa
1/28 verkleinert und weich zurückskaliert – der Text lässt sich daraus nicht
zurückgewinnen.

Die Originale liegen nur lokal in `screenshots/roh/`; der Ordner steht in
der `.gitignore`.

## Neu erzeugen

Windows, PowerShell 5.1 genügt (reines .NET, kein Python/ImageMagick):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\store\make_store_graphics.ps1
# nur Symbol und Vorstellungsgrafik (keine Screenshots nötig):
powershell -ExecutionPolicy Bypass -File scripts\store\make_store_graphics.ps1 -SkipScreenshots
```

| Datei | Wofür |
|:--|:--|
| [`scripts/store/make_store_graphics.ps1`](../scripts/store/make_store_graphics.ps1) | Ablauf: welche Screenshots, Überschriften, **welche Bereiche unkenntlich werden** |
| [`scripts/store/StoreGraphics.cs`](../scripts/store/StoreGraphics.cs) | Bildbearbeitung: Unkenntlichmachen, Hintergrund aus der Logo-Textur, Rahmen, Layouts |

**Neue Screenshots:**

1. Handy-Screenshots nach `store/screenshots/roh/` legen.
2. In `make_store_graphics.ps1` die Dateinamen in `$shots` eintragen und je
   Bild die Rechtecke `r` (Pixel des Originals: `x1,y1,x2,y2, …`) um alle
   persönlichen Daten setzen.
3. Skript laufen lassen und **jedes Bild in `screenshots/geschwaerzt/`
   prüfen**, bevor etwas committet oder hochgeladen wird.

> `make_store_graphics.ps1` muss als **UTF-8 mit BOM** gespeichert sein –
> sonst liest PowerShell 5.1 die Umlaute der Überschriften falsch.

Quelle aller Grafiken ist das Logo in [`assets/icon/`](../assets/icon/):
`icon.png` für Symbol, Vorstellungsgrafik und Hintergrund, `rimperio_logo.png`
(transparente Ecken) für die 10"-Tablet-Bilder.
