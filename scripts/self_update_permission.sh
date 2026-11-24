#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Datei:        scripts/self_update_permission.sh
# Projekt:      RIMPERIO-App
# Autor:        Phydran6
# Version:      2026.11.24.12.00.00
#
# Beschreibung: Schaltet die Android-Berechtigung REQUEST_INSTALL_PACKAGES
#               im Manifest an oder aus. Mit ihr kann sich die App aus dem
#               GitHub-Release selbst aktualisieren (Mehr → App-Update).
#
#               * APK (GitHub-Release): an
#               * AAB (Play Store): aus — Google Play verbietet Apps, sich
#                 an Play vorbei selbst zu aktualisieren, und lehnt die
#                 Berechtigung ohne Begründung ab. Updates kommen dort über
#                 den Play Store.
#
#               Ohne Berechtigung bleibt die Funktion in der App einfach aus
#               (sie prüft das zur Laufzeit) — zu sehen sind dann nur die
#               Version und ein Link aufs Release bzw. den Play Store.
#
# Aufruf:       bash scripts/self_update_permission.sh on|off
#               (scripts/setup_platforms.sh ruft es mit RIMPERIO_SELF_UPDATE
#               auf, Vorgabe: on)
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

MANIFEST="android/app/src/main/AndroidManifest.xml"
PERM="android.permission.REQUEST_INSTALL_PACKAGES"

sedi() { sed -i.bak "$@" && rm -f "${@: -1}.bak"; }

[ -f "$MANIFEST" ] || { echo "Fehlt: $MANIFEST — erst scripts/setup_platforms.sh ausführen." >&2; exit 1; }

case "${1:-on}" in
  on|1)
    if ! grep -q "$PERM" "$MANIFEST"; then
      echo "==> Android: Selbst-Update an (${PERM})"
      sedi "s#<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">#&\\
    <uses-permission android:name=\"${PERM}\"/>#" "$MANIFEST"
    fi
    ;;
  off|0)
    if grep -q "$PERM" "$MANIFEST"; then
      echo "==> Android: Selbst-Update aus (ohne ${PERM}, für den Play Store)"
      sedi "/${PERM//./\\.}/d" "$MANIFEST"
    fi
    ;;
  *)
    echo "Aufruf: $0 on|off" >&2
    exit 2
    ;;
esac
