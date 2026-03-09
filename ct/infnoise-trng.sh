#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Infinite Noise TRNG Sidecar"
REPO_URL="${INFNOISE_LXC_REPO_URL:-https://github.com/your-user/infnoise-lxc.git}"
var_tags="security;randomness;api"
var_cpu="1"
var_ram="512"
var_disk="4"
var_os="debian"
var_version="13"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors
start
build_container
description

msg_info "Attaching FTDI USB permissions to CT $CTID"
pct set "$CTID" -lxc.cgroup2.devices.allow "c 189:* rwm" >/dev/null
pct set "$CTID" -mp0 /dev/bus/usb,mp=/dev/bus/usb >/dev/null || true
msg_ok "USB access configured"

msg_info "Fetching infnoise-lxc repo inside container"
pct exec "$CTID" -- bash -lc "apt-get update && apt-get install -y git ca-certificates && rm -rf /opt/infnoise-lxc && git clone $REPO_URL /opt/infnoise-lxc"
msg_ok "Repo cloned"

msg_info "Running in-container installer"
pct exec "$CTID" -- bash -lc "/opt/infnoise-lxc/install/infnoise-trng-install.sh"
msg_ok "Installer completed"

echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "Edit /etc/default/infnoise-trng inside CT ${CTID}, set your ingest token, then start infnoise-trng.timer."
