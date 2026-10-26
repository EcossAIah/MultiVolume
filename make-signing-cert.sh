#!/usr/bin/env bash
#
# Creates a self-signed code signing certificate in the login keychain.
#
#   ./make-signing-cert.sh            # default name
#   CERT_NAME="My Signing" ./make-signing-cert.sh
#
# Why: an ad-hoc signature changes on every build, so macOS treats each build
# as a new app and drops its Accessibility and Input Monitoring grants. A
# signature from a fixed certificate stays the same across builds, so the
# grants survive updates. It does not satisfy Gatekeeper; only a paid
# Developer ID with notarization does that.
#
# The private key stays in this Mac's login keychain. Anyone who gets it can
# sign an app that macOS treats as this one, so do not share or commit it.
#
set -euo pipefail

CERT_NAME="${CERT_NAME:-EcossAIah Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$CERT_NAME\" already exists. Nothing to do."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# LibreSSL from macOS writes a PKCS#12 file that `security import` accepts.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$CERT_NAME" -passout "pass:$PASS" -out "$WORK/cert.p12"

# -T lets codesign use the key without a keychain prompt.
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo
echo "Created \"$CERT_NAME\". Sign with:"
echo "  SIGN_ID=\"$CERT_NAME\" ./build.sh"
