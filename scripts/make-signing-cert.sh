#!/bin/zsh
# Optional, once per Mac: a self-signed code-signing certificate ("Onyx Local Signing") in the
# login keychain. bundle.sh signs with it when present, so rebuilt copies of Onyx keep the same
# identity and macOS keeps their privacy permissions (microphone, folders) across updates.
# Without it, bundle.sh signs ad hoc and macOS may ask for those permissions again after each build.
set -euo pipefail
NAME="Onyx Local Signing"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" is already in your keychain."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/onyx.p12" -passout "pass:$PASS"
# -T lets codesign use the key without asking each time.
security import "$TMP/onyx.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "Added \"$NAME\" to your login keychain."
