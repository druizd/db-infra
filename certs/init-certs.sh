#!/bin/bash
# =============================================================================
# init-certs.sh — Entrypoint para TimescaleDB con TLS auto-generado
# Genera un certificado autofirmado si no existe, luego arranca postgres.
# =============================================================================
set -e

CERT_DIR="/certs"
CERT_FILE="$CERT_DIR/server.crt"
KEY_FILE="$CERT_DIR/server.key"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "[init-certs] Generando certificado TLS autofirmado (RSA 4096, 10 años)..."
    mkdir -p "$CERT_DIR"
    openssl req -new -x509 -days 3650 -nodes \
        -newkey rsa:4096 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=CL/ST=Santiago/L=Santiago/O=EmeCloud/CN=timescaledb-local"
    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    echo "[init-certs] Certificado generado exitosamente."
else
    echo "[init-certs] Certificado existente encontrado, reutilizando."
fi

# Pasar el control al entrypoint original de postgres con los flags TLS
exec docker-entrypoint.sh postgres \
    -c ssl=on \
    -c ssl_cert_file="$CERT_FILE" \
    -c ssl_key_file="$KEY_FILE" \
    -c shared_preload_libraries=timescaledb,pgaudit \
    -c pgaudit.log=write \
    -c pgaudit.log_catalog=off
