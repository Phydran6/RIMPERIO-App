#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Datei:        scripts/setup_platforms.sh
# Projekt:      RIMPERIO-App
# Autor:        Phydran6
# Version:      2026.11.07.12.00.00
#
# Beschreibung: Erzeugt die Plattform-Ordner (android/, ios/) und richtet sie
#               für RIMPERIO ein: App-Name, Berechtigungen (Internet, Kamera
#               für den QR-Code, Benachrichtigungen, Biometrie),
#               FragmentActivity für local_auth, Desugaring für
#               flutter_local_notifications, App-Symbol. Läuft lokal (Linux,
#               macOS, Git Bash unter Windows) und in der CI gleich.
#               Mehrfach ausführbar.
#
# Aufruf:       bash scripts/setup_platforms.sh
#               RIMPERIO_CLEARTEXT=1 bash scripts/setup_platforms.sh
#                 → erlaubt zusätzlich unverschlüsseltes http:// (Android und
#                   iOS), z. B. für einen Server im LAN ohne HTTPS. Die App
#                   warnt dann trotzdem bei jeder http-Verbindung.
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
GRADLE="android/app/build.gradle.kts"

echo "==> Android: App-Name '${APP_NAME}'"
sedi "s/android:label=\"[^\"]*\"/android:label=\"${APP_NAME}\"/" "$MANIFEST"

# Die Vorlage erlaubt Internet nur in den debug/profile-Manifesten — eine
# Release-APK könnte den Server sonst gar nicht erreichen. Kamera (QR-Code),
# Benachrichtigungen (Android 13+) und Biometrie bringen die Plugins zwar
# meist selbst mit; ausdrücklich steht es hier trotzdem.
for perm in INTERNET CAMERA POST_NOTIFICATIONS USE_BIOMETRIC RECEIVE_BOOT_COMPLETED; do
  if ! grep -q "android.permission.${perm}\"" "$MANIFEST"; then
    echo "==> Android: Berechtigung ${perm}"
    sedi "s#<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">#&\\
    <uses-permission android:name=\"android.permission.${perm}\"/>#" "$MANIFEST"
  fi
done
if ! grep -q 'android.hardware.camera' "$MANIFEST"; then
  # Kamera ist kein Muss — ohne geht die Anmeldung per Passwort.
  sedi 's#<manifest xmlns:android="http://schemas.android.com/apk/res/android">#&\
    <uses-feature android:name="android.hardware.camera" android:required="false"/>#' "$MANIFEST"
fi

if [ "${RIMPERIO_CLEARTEXT:-0}" = "1" ] && ! grep -q 'usesCleartextTraffic' "$MANIFEST"; then
  echo "==> Android: unverschlüsseltes HTTP erlaubt (RIMPERIO_CLEARTEXT=1)"
  sedi 's#<application#<application android:usesCleartextTraffic="true"#' "$MANIFEST"
fi

# local_auth zeigt den Biometrie-Dialog als Fragment → FragmentActivity nötig.
MAIN_ACTIVITY="$(find android/app/src/main -name 'MainActivity.kt' | head -1)"
if [ -n "$MAIN_ACTIVITY" ] && ! grep -q 'FlutterFragmentActivity' "$MAIN_ACTIVITY"; then
  echo "==> Android: MainActivity → FlutterFragmentActivity (Biometrie)"
  sedi 's/io\.flutter\.embedding\.android\.FlutterActivity/io.flutter.embedding.android.FlutterFragmentActivity/; s/: FlutterActivity()/: FlutterFragmentActivity()/' "$MAIN_ACTIVITY"
fi

# flutter_local_notifications braucht Core-Library-Desugaring.
if [ -f "$GRADLE" ] && ! grep -q 'isCoreLibraryDesugaringEnabled' "$GRADLE"; then
  echo "==> Android: Core-Library-Desugaring"
  sedi 's/^    compileOptions {/    compileOptions {\
        isCoreLibraryDesugaringEnabled = true/' "$GRADLE"
  cat >> "$GRADLE" <<'EOF'

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
EOF
fi

# --- iOS -------------------------------------------------------------------
PLIST="ios/Runner/Info.plist"
plist_add() { # $1 = Schlüssel, $2 = XML-Wert; nur wenn noch nicht vorhanden
  if ! grep -q "<key>$1</key>" "$PLIST"; then
    # Das letzte, nicht eingerückte </dict> schließt das Wurzel-Dictionary.
    sedi "s#^</dict>\$#	<key>$1</key>\\
	$2\\
</dict>#" "$PLIST"
  fi
}
if [ -f "$PLIST" ]; then
  echo "==> iOS: App-Name '${APP_NAME}', Kamera- und Face-ID-Texte"
  sedi "/<key>CFBundleDisplayName<\/key>/{n;s#<string>.*</string>#<string>${APP_NAME}</string>#;}" "$PLIST"
  plist_add NSCameraUsageDescription \
    '<string>Zum Scannen des Anmelde-QR-Codes aus der RIMPERIO-Weboberfläche.</string>'
  plist_add NSFaceIDUsageDescription \
    '<string>Zum Entsperren von RIMPERIO mit Face ID.</string>'
  if [ "${RIMPERIO_CLEARTEXT:-0}" = "1" ]; then
    echo "==> iOS: unverschlüsseltes HTTP erlaubt (RIMPERIO_CLEARTEXT=1)"
    plist_add NSAppTransportSecurity \
      '<dict><key>NSAllowsArbitraryLoads</key><true/><key>NSAllowsLocalNetworking</key><true/></dict>'
  fi
fi

# --- App-Symbol --------------------------------------------------------------
echo "==> App-Symbol erzeugen"
dart run flutter_launcher_icons

echo "==> Fertig. Weiter mit: flutter run   oder   flutter build apk"
