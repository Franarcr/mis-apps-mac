#!/bin/bash
# Compila Vital, la instala en el iPhone conectado y la abre.
#
# Uso:
#   ./instalar-iphone.sh                 instala y abre con tus datos reales
#   ./instalar-iphone.sh --ayuno-demo    además carga una semana de ayunos de ejemplo
#   ./instalar-iphone.sh --borrar-demo   borra los ayunos de ejemplo
#   ./instalar-iphone.sh --demo          todo con datos inventados (salud, entreno, peso), sin leer Salud
#
# Se pueden combinar: ./instalar-iphone.sh --demo --ayuno-demo
# Los argumentos solo valen para esa apertura; si luego abres Vital desde el iPhone, usa tus datos.
#
# Necesita Xcode (no basta con las Command Line Tools) y el iPhone emparejado con este Mac, por cable
# o por Wi-Fi (misma red, como cuando Xcode instala sin cable), desbloqueado y con el Modo desarrollador activado.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="com.francho.vital"
ARGS=()
for a in "$@"; do
  case "$a" in
    --ayuno-demo) ARGS+=("-ayuno-demo") ;;
    --borrar-demo) ARGS+=("-ayuno-demo-borrar") ;;
    --demo) ARGS+=("-demo") ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $a (usa --help)"; exit 1 ;;
  esac
done

# 1. Xcode
if ! xcodebuild -version >/dev/null 2>&1; then
  if [ -d /Applications/Xcode.app ]; then
    echo "Xcode está instalado pero no seleccionado. Ejecuta una vez:"
    echo "  sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -runFirstLaunch"
  else
    echo "Falta Xcode. Instálalo gratis desde la App Store, ábrelo una vez y vuelve a ejecutar este script."
  fi
  exit 1
fi

# 2. iPhone conectado
JSON="$(mktemp)"
trap 'rm -f "$JSON"' EXIT
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
UDID="$(/usr/bin/python3 -I - "$JSON" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("deviceType") == "iPhone" and d.get("connectionProperties", {}).get("pairingState") == "paired":
        print(hw.get("udid", "")); break
EOF
)"
if [ -z "$UDID" ]; then
  echo "No encuentro un iPhone emparejado. Desbloquéalo y ponlo en la misma Wi-Fi que este Mac"
  echo "(o conéctalo por cable y acepta «Confiar»)"
  echo "y activa Ajustes › Privacidad y seguridad › Modo desarrollador. Luego vuelve a intentarlo."
  exit 1
fi
echo "== iPhone: $UDID"

# 3. Compilar (la firma usa la cuenta de Apple que tengas en Xcode › Ajustes › Cuentas)
echo "== Compilando…"
xcodebuild -project Vital.xcodeproj -scheme Vital -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build -allowProvisioningUpdates build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="build/Build/Products/Debug-iphoneos/Vital.app"
[ -d "$APP" ] || { echo "La compilación falló (mira los errores de arriba)."; exit 1; }

# 4. Instalar y abrir
echo "== Instalando…"
xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null
echo "== Abriendo Vital ${ARGS[*]:-}"
xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" ${ARGS[@]+"${ARGS[@]}"} >/dev/null
echo "Listo. Si el iPhone dice «Desarrollador no fiable»: Ajustes › General › VPN y gestión de dispositivos › confía en tu cuenta, y vuelve a ejecutar."
