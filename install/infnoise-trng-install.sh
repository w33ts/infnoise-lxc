#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
APP_DIR="/opt/infnoise-trng"
BUILD_DIR="/usr/local/src/infnoise-src"
ENV_FILE="/etc/default/infnoise-trng"
INFNOISE_REPO_URL="${INFNOISE_REPO_URL:-https://github.com/13-37-org/infnoise.git}"
INFNOISE_REF="${INFNOISE_REF:-0.3.0}"
INSTALL_LOG_FILE="${INFNOISE_INSTALL_LOG_FILE:-/tmp/infnoise-trng-install.log}"

log_step() {
  printf '==> %s\n' "$1"
}

run_step() {
  local message="$1"
  shift

  log_step "$message"
  if ! "$@" >>"$INSTALL_LOG_FILE" 2>&1; then
    printf 'Installation failed during: %s\n' "$message" >&2
    printf 'Full log: %s\n' "$INSTALL_LOG_FILE" >&2
    tail -n 40 "$INSTALL_LOG_FILE" >&2 || true
    exit 1
  fi
}

in_container() {
  systemd-detect-virt --quiet --container
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing required file: %s\n' "$path" >&2
    exit 1
  fi
}

require_file "$INSTALL_ROOT/scripts/trng-push.py"
require_file "$INSTALL_ROOT/systemd/infnoise-trng.service"
require_file "$INSTALL_ROOT/systemd/infnoise-trng.timer"
require_file "$INSTALL_ROOT/udev/99-infnoise.rules"
require_file "$INSTALL_ROOT/.env.example"

: >"$INSTALL_LOG_FILE"

run_step "Updating apt package lists" apt-get update -qq
run_step "Installing build dependencies" apt-get install -y -qq build-essential ca-certificates curl git libftdi-dev libusb-dev python3 python3-venv udev

rm -rf "$BUILD_DIR"
run_step "Cloning infnoise source" git clone --depth 1 --branch "$INFNOISE_REF" "$INFNOISE_REPO_URL" "$BUILD_DIR"
run_step "Building infnoise binary" make -C "$BUILD_DIR/software" -f Makefile.linux
install -m 0755 "$BUILD_DIR/software/infnoise" /usr/local/bin/infnoise

install -d -m 0755 "$APP_DIR"
install -m 0755 "$INSTALL_ROOT/scripts/trng-push.py" "$APP_DIR/trng-push.py"
install -m 0644 "$INSTALL_ROOT/systemd/infnoise-trng.service" /etc/systemd/system/infnoise-trng.service
install -m 0644 "$INSTALL_ROOT/systemd/infnoise-trng.timer" /etc/systemd/system/infnoise-trng.timer
install -m 0644 "$INSTALL_ROOT/udev/99-infnoise.rules" /etc/udev/rules.d/99-infnoise.rules

if [[ ! -f "$ENV_FILE" ]]; then
  install -m 0600 "$INSTALL_ROOT/.env.example" "$ENV_FILE"
fi

udevadm control --reload-rules || true
if ! in_container; then
  run_step "Triggering host udev events" udevadm trigger
fi
run_step "Reloading systemd units" systemctl daemon-reload
run_step "Enabling infnoise timer" systemctl enable infnoise-trng.timer

cat <<EOF

Infinite Noise sidecar installed.

Next steps:
  1. Edit $ENV_FILE and set TRNG_INGEST_TOKEN.
  2. Confirm the USB device is visible inside the container.
  3. Start the timer with: systemctl start infnoise-trng.timer
  4. Check status with: systemctl status infnoise-trng.timer infnoise-trng.service
  5. Review detailed install logs at: $INSTALL_LOG_FILE

EOF
