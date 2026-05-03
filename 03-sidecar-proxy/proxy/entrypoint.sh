#!/bin/bash
set -euo pipefail

CERT_DIR=/app/certs
SHARED_DIR=/certs   # emptyDir shared with main container
mkdir -p "$CERT_DIR"

echo "Generating ephemeral CA and server certificates..."

# Generate CA
openssl genrsa -out "$CERT_DIR/ca-key.pem" 2048 2>/dev/null
openssl req -new -x509 -key "$CERT_DIR/ca-key.pem" \
  -out "$CERT_DIR/ca-cert.pem" -days 1 -subj "/CN=Credential Proxy CA" 2>/dev/null

# Generate server cert for github.com + api.github.com
openssl genrsa -out "$CERT_DIR/server-key.pem" 2048 2>/dev/null
openssl req -new -key "$CERT_DIR/server-key.pem" \
  -out "$CERT_DIR/server.csr" -subj "/CN=github.com" 2>/dev/null
printf "subjectAltName=DNS:github.com,DNS:api.github.com,DNS:*.github.com" \
  > "$CERT_DIR/ext.cnf"
openssl x509 -req -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca-cert.pem" -CAkey "$CERT_DIR/ca-key.pem" \
  -CAcreateserial -out "$CERT_DIR/server-cert.pem" \
  -days 1 -extfile "$CERT_DIR/ext.cnf" 2>/dev/null

# Share CA cert with main container via emptyDir volume
if [ -d "$SHARED_DIR" ]; then
  cp "$CERT_DIR/ca-cert.pem" "$SHARED_DIR/proxy-ca.crt"
  echo "Certs ready. CA written to $SHARED_DIR/proxy-ca.crt"
else
  echo "Shared cert dir $SHARED_DIR not mounted — skipping CA share"
fi

exec node /app/proxy.js
