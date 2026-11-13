#!/bin/bash
# Compila las apps y genera en dist/ un .zip por app, listo para compartir,
# junto con las instrucciones de instalación (INSTALAR.md).
# Uso: ./empaquetar.sh
set -euo pipefail
cd "$(dirname "$0")"

rm -rf dist
mkdir -p dist
for app in Captura Portapapeles Puntos Monitor Ventanas Volumen Barra Historietas Compresor Lazo Grabador Revela Batido Antena; do
  echo "== $app"
  (cd "$app" && ./build.sh | tail -1)
  codesign --verify --strict "/Applications/$app.app"
  # ditto conserva la firma y los permisos del paquete dentro del zip.
  ditto -c -k --norsrc --noextattr --keepParent "/Applications/$app.app" "dist/$app.zip"
done
cp INSTALAR.md dist/
echo
ls -lh dist
