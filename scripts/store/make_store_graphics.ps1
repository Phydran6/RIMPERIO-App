# ---------------------------------------------------------------------------
# Datei:        scripts/store/make_store_graphics.ps1
# Projekt:      RIMPERIO-App
# Autor:        Phydran6
# Version:      2026.11.22.14.00.00
#
# Beschreibung: Erzeugt alle Grafiken für den Google-Play-Store-Eintrag:
#                 store/icon-512.png                    App-Symbol 512×512
#                 store/feature-graphic-1024x500.png    Vorstellungsgrafik
#                 store/screenshots/telefon/            1080×1920
#                 store/screenshots/tablet-7/           1200×1920
#                 store/screenshots/tablet-10/          1920×1200 (quer)
#                 store/screenshots/geschwaerzt/        Screenshots nach dem
#                                                       Unkenntlichmachen
#               Quelle der Screenshots: store/screenshots/roh/ (Handy-
#               Screenshots 1080×2340, NICHT eingecheckt — enthalten echte
#               Daten). Welche Bereiche unkenntlich werden, steht unten in
#               $shots (Pixel des Original-Screenshots: x1,y1,x2,y2, …).
#
# Aufruf:       powershell -ExecutionPolicy Bypass -File scripts\store\make_store_graphics.ps1
#               … -SkipScreenshots   nur Symbol und Vorstellungsgrafik
#               Windows PowerShell 5.1 genügt (System.Drawing).
#
# WICHTIG:      Diese Datei als UTF-8 MIT BOM speichern — sonst liest
#               PowerShell 5.1 die Umlaute der Bildtexte falsch.
# ---------------------------------------------------------------------------
param([switch]$SkipScreenshots)
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $here '..\..')).Path
Add-Type -Path (Join-Path $here 'StoreGraphics.cs') -ReferencedAssemblies System.Drawing

$logo  = "$repo\assets\icon\icon.png"          # vollflächig, 1024²
$mark  = "$repo\assets\icon\rimperio_logo.png"  # mit Goldrahmen, transparente Ecken
$store = "$repo\store"

[StoreGraphics]::Icon($logo, "$store\icon-512.png")
[StoreGraphics]::Feature($logo, "$store\feature-graphic-1024x500.png")
"Symbol und Vorstellungsgrafik fertig"
if ($SkipScreenshots) { return }

$raw = "$store\screenshots\roh"
$out = "$store\screenshots"
foreach ($d in 'telefon', 'tablet-7', 'tablet-10', 'geschwaerzt') {
  New-Item -ItemType Directory -Force "$out\$d" | Out-Null
}

# Reihenfolge = Reihenfolge im Store. r = unkenntlich zu machende Rechtecke.
$shots = @(
  @{ f='Screenshot_20261122_022749.jpg'; n='01-uebersicht'; t='Alles auf einen Blick'
     r=@() },
  @{ f='Screenshot_20261122_022756.jpg'; n='02-geraete';    t='Jedes Gerät im Blick'
     # Hostname + IP-Adresse je Gerät
     r=@(197,515,503,638, 197,743,473,866, 197,971,473,1094, 197,1199,503,1322) },
  @{ f='Screenshot_20261122_022759.jpg'; n='03-meldungen';  t='Meldungen sofort aufs Handy'
     # Hostname am Anfang jeder Meldung + Detailzeilen (Container, Pakete, URLs)
     r=@(187,439,386,494,  187,571,1041,622,
         187,735,386,789,  187,799,1041,969,
         187,1074,386,1130, 187,1137,1041,1301,
         187,1413,314,1470, 187,1545,1041,1652,
         187,1765,386,1821, 187,1896,1041,1980) },
  @{ f='Screenshot_20261122_022810.jpg'; n='04-updates';    t='Updates freigeben und zurückrollen'
     # Hostnamen der Läufe + Name einer Sicherung
     r=@(176,417,287,470, 176,645,357,699, 176,872,445,927, 176,1100,357,1155,
         176,1327,357,1383, 176,1555,357,1611, 176,1218,872,1272) },
  @{ f='Screenshot_20261122_022753.jpg'; n='05-logs';       t='Zentrale Logs durchsuchen'
     # Hostname in jeder Logzeile
     r=@(351,552,454,601, 351,853,454,902, 351,1154,454,1203, 351,1454,454,1504, 351,1755,503,1804) },
  @{ f='Screenshot_20261122_022801.jpg'; n='06-sicherheit'; t='Biometrie, MFA und HTTPS'
     # Anzeige- und Benutzername, Server-Adresse
     r=@(240,456,398,510, 240,521,365,573, 152,1513,661,1570) }
)

foreach ($s in $shots) {
  $src = "$raw\$($s.f)"
  if (-not (Test-Path $src)) { Write-Warning "fehlt: $src — übersprungen"; continue }
  $bmp = [StoreGraphics]::Redact($src, [int[]]$s.r)
  $bmp.Save("$out\geschwaerzt\$($s.n).png", [System.Drawing.Imaging.ImageFormat]::Png)
  [StoreGraphics]::Portrait($logo, $bmp, $s.t, 1080, 1920, "$out\telefon\$($s.n).png")
  [StoreGraphics]::Portrait($logo, $bmp, $s.t, 1200, 1920, "$out\tablet-7\$($s.n).png")
  [StoreGraphics]::Landscape($logo, $mark, $bmp, $s.t, 1920, 1200, "$out\tablet-10\$($s.n).png")
  $bmp.Dispose()
  "fertig: $($s.n)"
}
