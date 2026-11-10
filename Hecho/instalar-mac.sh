#!/bin/bash
# Compila Hecho para el Mac, la instala en /Applications/Hecho.app y la abre.
# Uso: ./instalar-mac.sh
set -euo pipefail
cd "$(dirname "$0")"
NAME="Hecho"
BUNDLE_ID="com.francho.hecho"
LOG="$(mktemp)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$LOG" "$STAGE"' EXIT

echo "== Compilando… (la primera vez tarda un poco)"
if ! xcodebuild -project Hecho.xcodeproj -scheme Hecho -configuration Debug -destination 'platform=macOS' \
     -derivedDataPath build CODE_SIGNING_ALLOWED=NO build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | head -20
  mkdir -p build && cp "$LOG" build/ultima-compilacion.log
  echo "La compilación falló. El registro completo está en Hecho/build/ultima-compilacion.log"
  exit 1
fi

# La app se firma fuera de Documentos: la sincronización de iCloud añade atributos que invalidan la firma.
ditto --norsrc --noextattr "build/Build/Products/Debug/$NAME.app" "$STAGE/$NAME.app"
IDENTITY="Fran Firma Local"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$STAGE/$NAME.app"
else
  echo "Aviso: firma provisional (ejecuta ../crear-firma.sh para una firma estable)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$STAGE/$NAME.app"
fi

osascript -e "tell application \"$NAME\" to quit" >/dev/null 2>&1 || true
rm -rf "/Applications/$NAME.app"
ditto --norsrc --noextattr "$STAGE/$NAME.app" "/Applications/$NAME.app"
echo "Instalado en /Applications/$NAME.app"
open "/Applications/$NAME.app"
