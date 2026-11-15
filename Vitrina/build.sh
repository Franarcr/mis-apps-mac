#!/bin/bash
# Compila Vitrina, mete dentro las apps caseras que están instaladas en este Mac
# y la instala en /Applications/Vitrina.app.
# Uso: ./build.sh         -> compila e instala
#      ./build.sh --dmg   -> además crea ../dist/Vitrina.dmg para llevarla a otro Mac
set -euo pipefail
cd "$(dirname "$0")"
NAME="Vitrina"
BUNDLE_ID="com.fran.vitrina"
APPS=(Captura Portapapeles Puntos Monitor Ventanas Volumen Oido Barra Barrendero Guardian
      Hecho Lienzo Revela Historietas Compresor Lazo Grabador Batido Antena
      MacCleaner "Suite Notarial")

# El icono se genera la primera vez (necesita AppKit, así que solo se puede crear en el Mac).
if [ ! -f Resources/AppIcon.icns ]; then
  swift ../iconos/crear-icono.swift ../iconos/$NAME.icns shippingbox "#F2994A" "#EB5757"
  cp ../iconos/$NAME.icns Resources/AppIcon.icns
fi

swift build -c release

# La app se monta y firma fuera de Documentos: la sincronización de iCloud
# añade atributos al paquete que invalidan la firma.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/$NAME.app"
PACK="$APP/Contents/Resources/Apps"
mkdir -p "$APP/Contents/MacOS" "$PACK"
cp ".build/release/$NAME" "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Cada app va comprimida (así macOS no la confunde con una app instalada) junto con su icono
# y una ficha con su versión y la huella de su ejecutable, para saber si la instalada está al día.
echo "[" > "$PACK/manifest.json"
first=1
for app in "${APPS[@]}"; do
  src="/Applications/$app.app"
  # Las apps de Elena se pueden tomar ya compiladas en su repo, sin instalarlas en este Mac.
  if [ ! -d "$src" ] && [ "$app" = "Suite Notarial" ]; then src="$HOME/Documents/GitHub/suite-notarial/$app.app"; fi
  if [ ! -d "$src" ] && [ "$app" = "MacCleaner" ]; then src="$HOME/Documents/GitHub/mac-cleaner/$app.app"; fi
  if [ ! -d "$src" ]; then echo "   (sin $app: no está instalada en este Mac)"; continue; fi
  # La copia del repo vive en Documentos (iCloud le agrega atributos): se limpia y se firma aparte.
  if [[ "$src" != /Applications/* ]]; then
    clean="$STAGE/repo/$app.app"
    mkdir -p "$STAGE/repo"
    ditto --norsrc --noextattr "$src" "$clean"
    codesign --force --deep --sign "Fran Firma Local" "$clean" 2>/dev/null || codesign --force --deep --sign - "$clean"
    src="$clean"
  fi
  if ! codesign --verify --strict "$src" 2>/dev/null; then echo "   (sin $app: su firma no es válida)"; continue; fi
  ditto -c -k --norsrc --noextattr --keepParent "$src" "$PACK/$app.zip"
  swift icono-de-app.swift "$src" "$PACK/$app.png"
  exe="$src/Contents/MacOS/$(defaults read "$src/Contents/Info" CFBundleExecutable)"
  version=$(defaults read "$src/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
  minos=$(defaults read "$src/Contents/Info" LSMinimumSystemVersion 2>/dev/null || echo "14.0")
  hash=$(shasum -a 256 "$exe" | cut -d' ' -f1)
  built=$(stat -f %m "$exe")
  [ $first -eq 1 ] || echo "," >> "$PACK/manifest.json"
  first=0
  printf '{"name":"%s","version":"%s","hash":"%s","built":%s,"minOS":"%s"}' \
    "$app" "$version" "$hash" "$built" "$minos" >> "$PACK/manifest.json"
  echo "   + $app $version"
done
echo "]" >> "$PACK/manifest.json"

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
echo "Instalado en /Applications/$NAME.app"

if [ "${1:-}" = "--dmg" ]; then
  # El DMG trae Vitrina y un acceso a Aplicaciones para arrastrarla.
  DMG_DIR="$STAGE/dmg"
  mkdir -p "$DMG_DIR" ../dist
  ditto --norsrc --noextattr "$APP" "$DMG_DIR/$NAME.app"
  ln -s /Applications "$DMG_DIR/Aplicaciones"
  rm -f "../dist/$NAME.dmg"
  hdiutil create -volname "$NAME" -srcfolder "$DMG_DIR" -fs HFS+ -format UDZO -ov "../dist/$NAME.dmg" >/dev/null
  echo "DMG creado en dist/$NAME.dmg ($(du -h "../dist/$NAME.dmg" | cut -f1))"
fi
