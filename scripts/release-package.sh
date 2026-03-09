#!/usr/bin/env bash
# shellcheck disable=SC2312
set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'usage: %s [version]\n' "$0" >&2
  exit 1
fi

VERSION="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "$VERSION" ]]; then
  printf 'version is required\n' >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PKG_DIR="$DIST_DIR/infnoise-lxc-$VERSION"
ARCHIVE_PATH="$DIST_DIR/infnoise-lxc-$VERSION.tar.gz"
CHECKSUM_PATH="$DIST_DIR/infnoise-lxc-$VERSION.sha256"

REQUIRED_FILES=(
  ".env.example"
  "VERSION"
  "ct/infnoise-trng.sh"
  "install/infnoise-trng-install.sh"
  "RELEASING.md"
  "scripts/render-release-body.sh"
  "scripts/update-release-version.sh"
  "scripts/trng-push.py"
  "systemd/infnoise-trng.service"
  "systemd/infnoise-trng.timer"
  "udev/99-infnoise.rules"
  "README.md"
)

for relative_path in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$ROOT_DIR/$relative_path" ]]; then
    printf 'missing required file: %s\n' "$relative_path" >&2
    exit 1
  fi
done

mkdir -p "$DIST_DIR"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/ct" "$PKG_DIR/install" "$PKG_DIR/scripts" "$PKG_DIR/systemd" "$PKG_DIR/udev"

install -m 0644 "$ROOT_DIR/.env.example" "$PKG_DIR/.env.example"
install -m 0644 "$ROOT_DIR/VERSION" "$PKG_DIR/VERSION"
install -m 0755 "$ROOT_DIR/ct/infnoise-trng.sh" "$PKG_DIR/ct/infnoise-trng.sh"
install -m 0755 "$ROOT_DIR/install/infnoise-trng-install.sh" "$PKG_DIR/install/infnoise-trng-install.sh"
install -m 0644 "$ROOT_DIR/RELEASING.md" "$PKG_DIR/RELEASING.md"
install -m 0755 "$ROOT_DIR/scripts/render-release-body.sh" "$PKG_DIR/scripts/render-release-body.sh"
install -m 0755 "$ROOT_DIR/scripts/update-release-version.sh" "$PKG_DIR/scripts/update-release-version.sh"
install -m 0755 "$ROOT_DIR/scripts/trng-push.py" "$PKG_DIR/scripts/trng-push.py"
install -m 0644 "$ROOT_DIR/systemd/infnoise-trng.service" "$PKG_DIR/systemd/infnoise-trng.service"
install -m 0644 "$ROOT_DIR/systemd/infnoise-trng.timer" "$PKG_DIR/systemd/infnoise-trng.timer"
install -m 0644 "$ROOT_DIR/udev/99-infnoise.rules" "$PKG_DIR/udev/99-infnoise.rules"
install -m 0644 "$ROOT_DIR/README.md" "$PKG_DIR/README.md"

tar -czf "$ARCHIVE_PATH" -C "$DIST_DIR" "infnoise-lxc-$VERSION"
(cd "$DIST_DIR" && sha256sum "infnoise-lxc-$VERSION.tar.gz") > "$CHECKSUM_PATH"

printf 'Created %s\n' "$ARCHIVE_PATH"
printf 'Created %s\n' "$CHECKSUM_PATH"
