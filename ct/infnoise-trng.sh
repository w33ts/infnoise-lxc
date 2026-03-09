#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2034,SC2154
: "${SSH_CLIENT:=}"
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
set -euo pipefail

APP="Infinite Noise TRNG Sidecar"
INFNOISE_LXC_REPO="${INFNOISE_LXC_REPO:-w33ts/infnoise-lxc}"
INFNOISE_LXC_REF="${INFNOISE_LXC_REF:-}"
INFNOISE_LXC_TARBALL_URL="${INFNOISE_LXC_TARBALL_URL:-}"
HOST_TMP_DIR=""
HOST_STAGE_DIR=""
CT_STAGE_DIR="/tmp/infnoise-lxc"
CT_CONFIG_PATH=""
var_tags="security;randomness;api"
var_cpu="1"
var_ram="512"
var_disk="4"
var_os="debian"
var_version="13"
var_unprivileged="1"

cleanup() {
  if [[ -n "$HOST_TMP_DIR" && -d "$HOST_TMP_DIR" ]]; then
    rm -rf "$HOST_TMP_DIR"
  fi
}

get_tarball_url() {
  if [[ -n "$INFNOISE_LXC_TARBALL_URL" ]]; then
    printf '%s\n' "$INFNOISE_LXC_TARBALL_URL"
    return
  fi

  if [[ -z "$INFNOISE_LXC_REF" ]]; then
    printf 'INFNOISE_LXC_REF must be set to a release tag such as v0.1.0\n' >&2
    exit 1
  fi

  printf 'https://github.com/%s/releases/download/%s/infnoise-lxc-%s.tar.gz\n' \
    "$INFNOISE_LXC_REPO" "$INFNOISE_LXC_REF" "$INFNOISE_LXC_REF"
}

prepare_stage_dir() {
  local tarball_url archive_path extracted_root

  tarball_url="$(get_tarball_url)"
  HOST_TMP_DIR="$(mktemp -d /tmp/infnoise-lxc.XXXXXX)"
  archive_path="$HOST_TMP_DIR/infnoise-lxc.tar.gz"

  msg_info "Downloading release payload ${INFNOISE_LXC_REF:-custom}"
  curl -fsSL "$tarball_url" -o "$archive_path"
  tar -xzf "$archive_path" -C "$HOST_TMP_DIR"

  for extracted_root in "$HOST_TMP_DIR"/*; do
    if [[ -d "$extracted_root" ]]; then
      HOST_STAGE_DIR="$extracted_root"
      break
    fi
  done

  if [[ -z "$HOST_STAGE_DIR" ]]; then
    msg_error "Release payload did not contain an extracted directory"
    exit 1
  fi

  msg_ok "Release payload ready"
}

push_stage_file() {
  local source_path="$1"
  local dest_path="$2"
  pct push "$CTID" "$source_path" "$dest_path" >/dev/null
}

ensure_config_line() {
  local line="$1"

  if [[ -z "$CT_CONFIG_PATH" ]]; then
    CT_CONFIG_PATH="/etc/pve/lxc/${CTID}.conf"
  fi

  if [[ ! -f "$CT_CONFIG_PATH" ]]; then
    msg_error "Container config not found at $CT_CONFIG_PATH"
    exit 1
  fi

  if ! grep -Fxq "$line" "$CT_CONFIG_PATH"; then
    printf '%s\n' "$line" >>"$CT_CONFIG_PATH"
  fi
}

trap cleanup EXIT

header_info "$APP"
variables
color
catch_errors
start
build_container
description

msg_info "Attaching FTDI USB permissions to CT $CTID"
ensure_config_line "lxc.cgroup2.devices.allow: c 189:* rwm"
pct set "$CTID" -mp0 /dev/bus/usb,mp=/dev/bus/usb >/dev/null || true
pct reboot "$CTID" >/dev/null
msg_ok "USB access configured"

prepare_stage_dir

msg_info "Creating installer staging directory inside CT $CTID"
pct exec "$CTID" -- bash -lc "rm -rf '$CT_STAGE_DIR' && mkdir -p '$CT_STAGE_DIR/install' '$CT_STAGE_DIR/scripts' '$CT_STAGE_DIR/systemd' '$CT_STAGE_DIR/udev'"
msg_ok "Installer staging ready"

msg_info "Copying release payload into CT $CTID"
push_stage_file "$HOST_STAGE_DIR/install/infnoise-trng-install.sh" "$CT_STAGE_DIR/install/infnoise-trng-install.sh"
push_stage_file "$HOST_STAGE_DIR/scripts/trng-push.py" "$CT_STAGE_DIR/scripts/trng-push.py"
push_stage_file "$HOST_STAGE_DIR/systemd/infnoise-trng.service" "$CT_STAGE_DIR/systemd/infnoise-trng.service"
push_stage_file "$HOST_STAGE_DIR/systemd/infnoise-trng.timer" "$CT_STAGE_DIR/systemd/infnoise-trng.timer"
push_stage_file "$HOST_STAGE_DIR/udev/99-infnoise.rules" "$CT_STAGE_DIR/udev/99-infnoise.rules"
push_stage_file "$HOST_STAGE_DIR/.env.example" "$CT_STAGE_DIR/.env.example"
msg_ok "Release payload copied"

msg_info "Running in-container installer"
pct exec "$CTID" -- bash -lc "chmod +x '$CT_STAGE_DIR/install/infnoise-trng-install.sh' && INSTALL_ROOT='$CT_STAGE_DIR' '$CT_STAGE_DIR/install/infnoise-trng-install.sh' && rm -rf '$CT_STAGE_DIR'"
msg_ok "Installer completed"

echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "Edit /etc/default/infnoise-trng inside CT ${CTID}, set your ingest token, then start infnoise-trng.timer."
