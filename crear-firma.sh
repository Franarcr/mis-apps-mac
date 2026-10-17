#!/bin/bash
# Crea un certificado autofirmado "Fran Firma Local" en el llavero de inicio de sesión,
# solo para firmar código. Así Captura y Portapapeles conservan sus permisos al recompilarlas.
# Se ejecuta una sola vez. Para quitarlo: Acceso a Llaveros › "Fran Firma Local" › Eliminar.
set -euo pipefail
NAME="Fran Firma Local"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "El certificado \"$NAME\" ya existe."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/firma.p12" -passout "pass:$PASS"
security import "$TMP/firma.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign

echo "Certificado \"$NAME\" creado."
