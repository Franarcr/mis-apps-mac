#!/bin/bash
# Compila Kvlt, la instala en el iPad y la abre.
# El iPad tiene que estar emparejado con esta Mac, desbloqueado y con el Modo desarrollador activado.
# La firma del equipo personal caduca a los 7 días: vuelve a ejecutar este script para renovarla.
set -euo pipefail
cd "$(dirname "$0")"

UDID="${IPAD_UDID:-00008101-000674862E01001E}"
BUNDLE_ID="com.francho.kvlt"
APP="build/Build/Products/Debug-iphoneos/Kvlt.app"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

# Xcode reutiliza perfiles viejos (ya caducados): se apartan los de esta app antes de compilar.
mkdir -p "$PROFILES/apartados"
for f in "$PROFILES"/*.mobileprovision; do
  [ -e "$f" ] || continue
  if security cms -D -i "$f" 2>/dev/null | grep -q "$BUNDLE_ID"; then mv "$f" "$PROFILES/apartados/"; fi
done

# Se compila para este iPad (no «iOS genérico») para que Xcode lo incluya en el perfil de firma;
# si no, el iPad rechaza la app con «no fue posible verificar su integridad».
echo "== Compilando…"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
if ! xcodebuild -project Kvlt.xcodeproj -scheme Kvlt -configuration Debug \
     -destination "id=$UDID" -derivedDataPath build -allowProvisioningUpdates build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | head -20
  echo "La compilación falló."
  exit 1
fi

echo "== Instalando en el iPad… (desbloquéalo si está bloqueado)"
for intento in $(seq 1 12); do
  if xcrun devicectl device install app --device "$UDID" "$APP" >"$LOG" 2>&1; then
    xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "Listo. Kvlt está abierta en el iPad."
    exit 0
  fi
  echo "   El iPad no responde (¿bloqueado?). Reintento $intento de 12…"
  sleep 10
done
grep -E "FailureReason|error" "$LOG" | head -3
echo "No pude instalar. Desbloquea el iPad y vuelve a ejecutar el script."
exit 1
