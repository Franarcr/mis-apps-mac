#!/bin/bash
# Compila Lienzo y instala /Applications/Lienzo.app.
# Uso: ./build.sh   -> compila e instala en /Applications (única copia de la app)
set -euo pipefail
cd "$(dirname "$0")"
NAME="Lienzo"
BUNDLE_ID="com.fran.lienzo"

# El icono se genera la primera vez (necesita AppKit, así que solo se puede crear en el Mac).
if [ ! -f Resources/AppIcon.icns ]; then
  swift ../iconos/crear-icono.swift ../iconos/$NAME.icns scribble.variable "#2DD4BF" "#4F46E5"
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
mkdir -p "$APP/Contents/Resources/es.lproj"

# Con el certificado de ../crear-firma.sh la firma es estable y macOS conserva los permisos.
IDENTITY="Fran Firma Local"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
  echo "Aviso: firma provisional (ejecuta ../crear-firma.sh para conservar los permisos)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

# Solo se instala en /Applications para que no aparezcan copias repetidas en el Launchpad.
rm -rf "/Applications/$NAME.app"
ditto --norsrc --noextattr "$APP" "/Applications/$NAME.app"
# Registra el tipo .lienzo con la copia instalada.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$NAME.app" || true
echo "Instalado en /Applications/$NAME.app"
