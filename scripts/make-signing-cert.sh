#!/usr/bin/env bash
# Create a stable, self-signed code-signing identity in the login keychain.
#
# Why this exists: a `swift build` binary is ad-hoc signed, and macOS TCC keys the
# Accessibility grant on the code's cdhash — which changes on every rebuild. So the
# hold-to-talk hotkey (a CGEvent tap, which needs Accessibility) silently dies after
# each build until you re-grant it. Signing the .app with ONE stable identity instead
# gives it a stable designated requirement, so the grant sticks across rebuilds.
#
# Self-signed is enough: TCC records the requirement and matches future launches; it
# does not care whether the cert is trusted by anyone. Idempotent — safe to re-run.
set -euo pipefail

CERT_NAME="whisper-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$CERT_NAME"; then
    echo "Signing identity '$CERT_NAME' already exists. Nothing to do."
    exit 0
fi

echo "Creating self-signed code-signing identity '$CERT_NAME'…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.conf" >/dev/null 2>&1
# -legacy: write the SHA1-MAC/3DES PKCS12 format Apple's `security` can import.
# Modern OpenSSL defaults (AES + SHA-256 MAC) fail with "MAC verification failed".
LEGACY=""
openssl pkcs12 -help 2>&1 | grep -q -- -legacy && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:whisper -name "$CERT_NAME" >/dev/null 2>&1

# Import the key+cert and pre-authorise codesign to use the key.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P whisper \
    -T /usr/bin/codesign -T /usr/bin/security

# Trust it for code signing in the user domain so `find-identity -v` lists it as valid.
# User domain needs no admin; this does not affect anyone else's machine.
security add-trusted-cert -r trustAsRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null || \
    echo "  (trust step skipped — signing still works, identity just isn't marked 'trusted')"

echo
echo "Done. On the FIRST bundle sign, macOS may ask to let codesign use the key —"
echo "click 'Always Allow' once and it won't ask again."
security find-identity -p codesigning | grep "$CERT_NAME" || true
