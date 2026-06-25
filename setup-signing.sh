#!/bin/bash
# Create a stable self-signed code-signing identity so the macOS Accessibility
# grant survives rebuilds (TCC keys on the cert identity, not the binary hash).
#
# Run once. Idempotent: does nothing if the identity already exists.
set -euo pipefail

CN="ClipHistory Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CN"; then
    echo "Identity '$CN' already present — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/ext.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = $CN
[ v3 ]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

echo "[1/3] Generating self-signed code-signing certificate (valid 10 years)..."
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/ext.cnf" >/dev/null 2>&1

echo "[2/3] Packaging as PKCS#12..."
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CN" -out "$TMP/identity.p12" -passout pass:cliphistory >/dev/null 2>&1

echo "[3/3] Importing into login keychain (allowing codesign to use the key)..."
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P cliphistory \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1

echo "Done. Identity '$CN' is now available:"
security find-identity -v -p codesigning | grep "$CN" || true
echo
echo "Next: run ./build-app.sh. macOS will prompt once -> click 'Always Allow'."
