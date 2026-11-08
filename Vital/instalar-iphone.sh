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
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
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
LOG="$(mktemp)"
trap 'rm -f "$JSON" "$LOG"' EXIT

# Busca el iPhone emparejado. Prefiere uno ya conectado (cable, o Wi-Fi con conexión abierta).
find_iphone() {
  xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
  /usr/bin/python3 -I - "$JSON" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
phones = [d for d in devices
          if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"]
phones.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") != "connected")
for d in phones[:1]:
    c = d.get("connectionProperties", {})
    print("\t".join([d["hardwareProperties"].get("udid", ""), d.get("deviceProperties", {}).get("name", "iPhone"),
                     c.get("transportType", "?"), c.get("tunnelState", "?")]))
EOF
}

IFS=$'\t' read -r UDID NAME TRANSPORT TUNNEL <<< "$(find_iphone)" || true
if [ -z "${UDID:-}" ]; then
  echo "No encuentro un iPhone emparejado con este Mac."
  echo "Desbloquéalo y ponlo en la misma Wi-Fi (o conéctalo por cable y acepta «Confiar»),"
  echo "con Ajustes › Privacidad y seguridad › Modo desarrollador activado. Luego vuelve a intentarlo."
  exit 1
fi
echo "== iPhone: $NAME ($([ "$TRANSPORT" = wired ] && echo cable || echo Wi-Fi), $TUNNEL)"

# 3. Compilar para iPhone en general: no hace falta que el teléfono responda mientras compila.
#    La firma usa la cuenta de Apple de Xcode › Ajustes › Cuentas.
APP="build/Build/Products/Debug-iphoneos/Vital.app"
rm -rf "$APP"
echo "== Compilando… (la primera vez tarda unos minutos)"
if ! xcodebuild -project Vital.xcodeproj -scheme Vital -configuration Debug \
     -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build >"$LOG" 2>&1; then
  grep -E "error:|requires a provisioning|Signing for" "$LOG" | sort -u | head -20
  mkdir -p build && cp "$LOG" build/ultima-compilacion.log
  echo "La compilación falló. El registro completo está en Vital/build/ultima-compilacion.log"
  exit 1
fi
[ -d "$APP" ] || { echo "Compiló pero no encuentro $APP."; exit 1; }
echo "   Compilado."

# 4. Instalar y abrir. Por Wi-Fi el iPhone tiene que estar despierto: se reintenta durante 1 minuto.
echo "== Instalando…"
for intento in 1 2 3 4 5 6; do
  if xcrun devicectl device install app --device "$UDID" "$APP" >"$LOG" 2>&1; then
    break
  fi
  if [ "$intento" = 6 ]; then
    grep -E "ERROR|error" "$LOG" | head -5
    echo
    echo "No pude llegar al iPhone. Desbloquéalo, déjalo con la pantalla encendida y cerca, en la misma Wi-Fi."
    echo "Si sigue igual: Xcode › Window › Devices and Simulators › elige el iPhone y marca «Connect via network»,"
    echo "o conéctalo por cable una vez. Luego vuelve a ejecutar el script (ya no recompila desde cero)."
    exit 1
  fi
  echo "   El iPhone no responde; desbloquéalo y deja la pantalla encendida… (intento $intento de 6)"
  sleep 10
done
echo "== Abriendo Vital ${ARGS[*]:-}"
xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" ${ARGS[@]+"${ARGS[@]}"} >/dev/null
echo "Listo. Si el iPhone dice «Desarrollador no fiable»: Ajustes › General › VPN y gestión de dispositivos › confía en tu cuenta, y vuelve a ejecutar."
