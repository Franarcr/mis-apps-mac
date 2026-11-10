#!/bin/bash
# Compila Guardian y instala /Applications/Guardian.app.
# Uso: ./build.sh   -> compila e instala en /Applications (única copia de la app)
set -euo pipefail
cd "$(dirname "$0")"
NAME="Guardian"
BUNDLE_ID="com.fran.guardian"

# El icono se genera la primera vez (necesita AppKit, así que solo se puede crear en el Mac).
if [ ! -f Resources/AppIcon.icns ]; then
  swift ../iconos/crear-icono.swift ../iconos/$NAME.icns checkmark.shield.fill "#5B8DEF" "#2B3FA8"
  cp ../iconos/$NAME.icns Resources/AppIcon.icns
fi

swift build -c release

# La app se monta y firma fuera de Documentos: la sincronización de iCloud
# añade atributos al paquete que invalidan la firma.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$NAME" "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Con el certificado de ../crear-firma.sh la firma es estable y macOS conserva los permisos
# (aquí, el permiso de notificaciones). Si no existe, se usa «MacCleaner Local» si está.
IDENTITY=""
for candidate in "Fran Firma Local" "MacCleaner Local"; do
  if security find-certificate -c "$candidate" >/dev/null 2>&1; then IDENTITY="$candidate"; break; fi
done
xattr -cr "$APP"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
  echo "Aviso: firma provisional (ejecuta ../crear-firma.sh para conservar los permisos)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

# Solo se instala en /Applications para que no aparezcan copias repetidas en el Launchpad.
rm -rf "/Applications/$NAME.app"
ditto --norsrc --noextattr "$APP" "/Applications/$NAME.app"
echo "Instalado en /Applications/$NAME.app"
