#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/veeamblksnap-sign.log"

log() {
    echo "$(date +'%F %T') | $*" | tee -a "$LOGFILE"
}

MODNAME="veeamblksnap"
KERNELVER="$(uname -r)"
MODDIR="/lib/modules/$KERNELVER/updates/dkms"
MODFILE="$MODDIR/${MODNAME}.ko.zst"
KOFILE="$MODDIR/${MODNAME}.ko"

PRIVKEY="/var/lib/shim-signed/mok/MOK.priv"
DERCERT="/var/lib/shim-signed/mok/MOK.der"
PEMCERT="/var/lib/shim-signed/mok/MOK.pem"

CALLER="$(basename "$0")"

if [[ "$CALLER" == zzz-sign-veeam ]]; then
    log "--- Invoked from /etc/kernel/postinst.d/zzz-sign-veeam (automatic run after kernel update) ---"
fi

log "=== Starting module signing: $MODNAME for kernel $KERNELVER ==="

# Ensure keys exist
if [[ ! -f "$PRIVKEY" ]]; then
    log "❌ ERROR: Private key not found: $PRIVKEY"
    exit 1
fi

# Convert DER to PEM if needed
if [[ ! -f "$PEMCERT" ]]; then
    if [[ -f "$DERCERT" ]]; then
        log "ℹ️ PEM certificate not found, converting from DER..."
        if openssl x509 -inform der -in "$DERCERT" -out "$PEMCERT"; then
            log "✅ Successfully converted DER to PEM: $PEMCERT"
        else
            log "❌ ERROR: Failed to convert DER to PEM"
            exit 1
        fi
    else
        log "❌ ERROR: No PEM or DER certificate found for signing"
        exit 1
    fi
fi

# Decompress module if needed
if [[ -f "$MODFILE" ]]; then
    log "📦 Found compressed module: $MODFILE, decompressing..."
    if ! zstd -d -f "$MODFILE" -o "$KOFILE"; then
        log "❌ ERROR: Failed to decompress $MODFILE"
        exit 1
    fi
else
    log "ℹ️ No compressed module found, checking for uncompressed version..."
fi

if [[ ! -f "$KOFILE" ]]; then
    log "❌ ERROR: Module file not found: $KOFILE"
    exit 1
fi

# Sign module
log "🔏 Signing module..."
if /usr/src/linux-headers-"$KERNELVER"/scripts/sign-file sha256 "$PRIVKEY" "$PEMCERT" "$KOFILE"; then
    log "✅ Module successfully signed: $KOFILE"
else
    log "❌ ERROR: Failed to sign module: $KOFILE"
    exit 1
fi

log "=== Module signing completed successfully ==="
