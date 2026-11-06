#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Datei:        scripts/setup_platforms.sh
# Projekt:      RIMPERIO-App
# Autor:        Phydran6
# Version:      2026.11.06.23.30.00
#
# Beschreibung: Erzeugt die Plattform-Ordner (android/, ios/) und richtet sie
#               für RIMPERIO ein: App-Name, Internet-Berechtigung im Release,
#               App-Symbol. Läuft lokal (Linux, macOS, Git Bash unter Windows)
#               und in der CI gleich. Mehrfach ausführbar.
#
# Aufruf:       bash scripts/setup_platforms.sh
#               RIMPERIO_CLEARTEXT=1 bash scripts/setup_platforms.sh
#                 → erlaubt zusätzlich unverschlüsseltes http:// (Android),
#                   z. B. für einen Server im LAN ohne HTTPS.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="RIMPERIO"

# sed -i ist unter GNU und BSD/macOS verschieden — so geht es auf beiden.
sedi() { sed -i.bak "$@" && rm -f "${@: -1}.bak"; }

echo "==> Plattform-Ordner erzeugen (bestehende Dateien bleiben unangetastet)"
flutter create --org de.phytech --project-name rimperio_app \
  --platforms android,ios .

# flutter create legt einen Beispieltest an, falls keiner da ist; unser Test
# liegt unter test/widget_test.dart und wird deshalb nicht überschrieben.

echo "==> Abhängigkeiten holen"
flutter pub get

# --- Android ---------------------------------------------------------------
MANIFEST="android/app/src/main/AndroidManifest.xml"

echo "==> Android: App-Name '${APP_NAME}'"
sedi "s/android:label=\"[^\"]*\"/android:label=\"${APP_NAME}\"/" "$MANIFEST"

# Die Vorlage erlaubt Internet nur in den debug/profile-Manifesten — eine
# Release-APK könnte den Server sonst gar nicht erreichen.
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  echo "==> Android: Internet-Berechtigung für Release"
  sedi 's#<manifest xmlns:android="http://schemas.android.com/apk/res/android">#&\
    <uses-permission android:name="android.permission.INTERNET"/>#' "$MANIFEST"
fi

if [ "${RIMPERIO_CLEARTEXT:-0}" = "1" ] && ! grep -q 'usesCleartextTraffic' "$MANIFEST"; then
  echo "==> Android: unverschlüsseltes HTTP erlaubt (RIMPERIO_CLEARTEXT=1)"
  sedi 's#<application#<application android:usesCleartextTraffic="true"#' "$MANIFEST"
fi

# --- iOS -------------------------------------------------------------------
PLIST="ios/Runner/Info.plist"
if [ -f "$PLIST" ]; then
  echo "==> iOS: App-Name '${APP_NAME}'"
  sedi "/<key>CFBundleDisplayName<\/key>/{n;s#<string>.*</string>#<string>${APP_NAME}</string>#;}" "$PLIST"
fi

# --- App-Symbol --------------------------------------------------------------
echo "==> App-Symbol erzeugen"
dart run flutter_launcher_icons

echo "==> Fertig. Weiter mit: flutter run   oder   flutter build apk"
