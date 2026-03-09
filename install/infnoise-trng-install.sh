#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/opt/infnoise-trng"
BUILD_DIR="/usr/local/src/infnoise-src"
ENV_FILE="/etc/default/infnoise-trng"
INFNOISE_REPO_URL="${INFNOISE_REPO_URL:-https://github.com/13-37-org/infnoise.git}"
INFNOISE_REF="${INFNOISE_REF:-0.3.0}"

apt-get update
apt-get install -y build-essential ca-certificates curl git libftdi-dev libusb-dev python3 python3-venv udev

rm -rf "$BUILD_DIR"
git clone --depth 1 --branch "$INFNOISE_REF" "$INFNOISE_REPO_URL" "$BUILD_DIR"
make -C "$BUILD_DIR/software" -f Makefile.linux
install -m 0755 "$BUILD_DIR/software/infnoise" /usr/local/bin/infnoise

install -d -m 0755 "$APP_DIR"
install -m 0755 "$REPO_ROOT/scripts/trng-push.py" "$APP_DIR/trng-push.py"
install -m 0644 "$REPO_ROOT/systemd/infnoise-trng.service" /etc/systemd/system/infnoise-trng.service
install -m 0644 "$REPO_ROOT/systemd/infnoise-trng.timer" /etc/systemd/system/infnoise-trng.timer
install -m 0644 "$REPO_ROOT/udev/99-infnoise.rules" /etc/udev/rules.d/99-infnoise.rules

if [[ ! -f "$ENV_FILE" ]]; then
  install -m 0600 "$REPO_ROOT/.env.example" "$ENV_FILE"
fi

udevadm control --reload-rules || true
udevadm trigger || true
systemctl daemon-reload
systemctl enable infnoise-trng.timer

cat <<EOF

Infinite Noise sidecar installed.

Next steps:
  1. Edit $ENV_FILE and set TRNG_INGEST_TOKEN.
  2. Confirm the USB device is visible inside the container.
  3. Start the timer with: systemctl start infnoise-trng.timer
  4. Check status with: systemctl status infnoise-trng.timer infnoise-trng.service

EOF
