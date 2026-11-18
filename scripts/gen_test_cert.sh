#!/usr/bin/env bash
# Generate a local self-signed Code Signing test certificate in signing/
# for packaging with package_and_sign_arm64.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING="$ROOT/signing"
mkdir -p "$SIGNING"

cat > "$SIGNING/openssl-codesign.cnf" <<'EOF'
[ req ]
default_bits       = 3072
distinguished_name = req_dn
x509_extensions    = v3_codesign
prompt             = no

[ req_dn ]
CN = Yttrium ARM64 BVM Test Driver Signing
O  = Local Test Signing

[ v3_codesign ]
subjectKeyIdentifier = hash
basicConstraints     = critical, CA:false
keyUsage             = critical, digitalSignature
extendedKeyUsage     = codeSigning
EOF

openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
  -config "$SIGNING/openssl-codesign.cnf" \
  -keyout "$SIGNING/test-signing.key" \
  -out "$SIGNING/test-signing.crt"

openssl x509 -in "$SIGNING/test-signing.crt" -outform DER -out "$SIGNING/test-signing.cer"
date +%s > "$SIGNING/SIGN_TIME"
chmod 600 "$SIGNING/test-signing.key"
rm -f "$SIGNING/openssl-codesign.cnf"

echo "Generated test signing certificate in $SIGNING/"
openssl x509 -in "$SIGNING/test-signing.crt" -noout -subject -dates -fingerprint -sha256
