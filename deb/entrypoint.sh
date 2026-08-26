#!/bin/bash

set -e

# Workaround for stale gpg-agent socket causing auth failures on restart
# Cleans up leftover sockets in the GPG home directory
if [ -d /root/.gnupg ]; then
    rm -f /root/.gnupg/S.gpg-agent*
fi

TLS_DIR="${BRIDGE_TLS_DIR:-/root/tls}"
TLS_CERT="${TLS_DIR}/bridge.crt"
TLS_KEY="${TLS_DIR}/bridge.key"
TLS_PEM="${TLS_DIR}/bridge.pem"

# Proton Bridge always offers STARTTLS on its own listeners, but the
# certificate it generates is issued for 127.0.0.1 only, and it never listens
# on anything other than loopback. Once the connection is forwarded out of the
# container that certificate can no longer be validated by name, so we
# terminate TLS here instead, using a certificate that matches how the
# container is actually reached, and forward to the bridge over the
# container's own loopback interface.
ensure_tls_cert() {
    if [[ -s $TLS_CERT && -s $TLS_KEY ]]; then
        echo "Using existing TLS certificate at ${TLS_CERT}"
    else
        echo "Generating a self-signed TLS certificate at ${TLS_CERT}"
        mkdir -p "$TLS_DIR"
        openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
            -keyout "$TLS_KEY" -out "$TLS_CERT" \
            -subj "/CN=${BRIDGE_TLS_CN:-protonmail-bridge}" \
            -addext "subjectAltName=${BRIDGE_TLS_SAN:-DNS:localhost,DNS:protonmail-bridge,IP:127.0.0.1}"
    fi

    # socat wants the key and the certificate in a single file.
    cat "$TLS_CERT" "$TLS_KEY" > "$TLS_PEM"
    chmod 600 "$TLS_PEM"
    # Best effort: a bring-your-own key may be mounted read-only.
    chmod 600 "$TLS_KEY" 2>/dev/null || true

    # Clients have to pin or import this certificate, so make the fingerprint
    # easy to find in the container logs.
    echo "TLS certificate fingerprint:"
    openssl x509 -in "$TLS_CERT" -noout -fingerprint -sha256 -subject -ext subjectAltName
}

# Initialize
if [[ $1 == init ]]; then

    set -x

    # Initialize pass
    gpg --generate-key --batch /protonmail/gpgparams
    pass init pass-key

    # Login
    protonmail-bridge --cli

else

    ensure_tls_cert

    set -x

    # Implicit TLS: IMAPS and SMTPS, terminated here and forwarded to the
    # bridge on loopback.
    socat OPENSSL-LISTEN:993,fork,reuseaddr,cert="$TLS_PEM",verify=0 TCP:127.0.0.1:1143,nodelay &
    socat OPENSSL-LISTEN:465,fork,reuseaddr,cert="$TLS_PEM",verify=0 TCP:127.0.0.1:1025,nodelay &

    # The plain listeners forward the bridge's own sockets untouched, so they
    # still offer STARTTLS - but nothing forces a client to use it. Set
    # BRIDGE_TLS_ONLY=true to publish only the implicit TLS ports above.
    if [[ ${BRIDGE_TLS_ONLY:-false} != true ]]; then
        # socat will make the conn appear to come from 127.0.0.1
        # ProtonMail Bridge currently expects that.
        # It also allows us to bind to the real ports :)
        socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025,nodelay &
        socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143,nodelay &
    fi

    # Start protonmail
    # Fake a terminal, so it does not quit because of EOF...
    rm -f faketty
    mkfifo faketty

    # Keep faketty open
    sleep infinity > faketty &

    # Start bridge reading from faketty
    protonmail-bridge --cli < faketty &

    # Wait for the bridge to exit
    wait $!
    exit $?

fi
