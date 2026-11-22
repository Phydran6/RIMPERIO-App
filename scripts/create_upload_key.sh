#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Datei:        scripts/create_upload_key.sh
# Projekt:      RIMPERIO-App
# Autor:        Phydran6
# Version:      2026.11.22.12.00.00
#
# Beschreibung: Legt den Upload-Schlüssel für den Google Play Store an
#               (upload-keystore.jks) und schreibt key.properties in den
#               Repo-Wurzelordner. Beide Dateien sind per .gitignore vom
#               Repo ausgeschlossen. GUT SICHERN — ohne diesen Schlüssel
#               lassen sich keine Updates mehr hochladen (verloren → beim
#               Play-Support einen neuen Upload-Schlüssel beantragen).
#
# Aufruf:       bash scripts/create_upload_key.sh     (Git Bash unter Windows)
#               Braucht keytool aus einem JDK (17 empfohlen).
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

KEYSTORE="upload-keystore.jks"
ALIAS="upload"

if [ -f "$KEYSTORE" ] || [ -f key.properties ]; then
  echo "Abbruch: $KEYSTORE oder key.properties gibt es schon — nicht überschreiben." >&2
  exit 1
fi
command -v keytool >/dev/null || { echo "keytool nicht gefunden (JDK installieren / PATH)." >&2; exit 1; }

read -r -s -p "Passwort für den Schlüssel (mind. 6 Zeichen): " PASS; echo
read -r -s -p "Passwort wiederholen: " PASS2; echo
[ "$PASS" = "$PASS2" ] || { echo "Passwörter stimmen nicht überein." >&2; exit 1; }
[ "${#PASS}" -ge 6 ] || { echo "Passwort zu kurz." >&2; exit 1; }

# PKCS12 kennt nur ein Passwort — Store- und Schlüssel-Passwort sind gleich.
keytool -genkeypair -v \
  -keystore "$KEYSTORE" -storetype PKCS12 \
  -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=RIMPERIO, O=phytech, C=DE"

cat > key.properties <<EOF
storePassword=$PASS
keyPassword=$PASS
keyAlias=$ALIAS
storeFile=$KEYSTORE
EOF

echo
echo "Fertig: $KEYSTORE und key.properties angelegt."
echo "Jetzt sichern (z. B. Passwort-Manager) und dann:"
echo "  bash scripts/setup_platforms.sh   # falls android/ schon vorher da war"
echo "  flutter build appbundle"
echo
echo "Für die CI (GitHub → Settings → Secrets → Actions):"
echo "  ANDROID_KEYSTORE_BASE64  = Inhalt von: base64 -w0 $KEYSTORE"
echo "  ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_PASSWORD = das Passwort"
echo "  ANDROID_KEY_ALIAS        = $ALIAS"
