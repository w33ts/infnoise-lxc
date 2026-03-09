# infnoise-lxc

Small Proxmox-side companion for the TRNG API on `w33t.io`.

This repository builds a Debian LXC container that talks to an Infinite Noise TRNG over USB, pulls whitened bytes from the `infnoise` driver, samples the driver's health output, and posts refill batches to the portfolio site's ingest endpoint.

## What it does

- builds and installs `infnoise`
- runs a timed refill job with `systemd`
- sends entropy batches to `https://w33t.io/api/trng/refill`
- reports health data so the public status page can show entropy-per-bit, estimated K, and recent device activity

The public API is meant to serve from a prefetched pool in Cloudflare D1. This sidecar is the piece that keeps that pool topped off.

## Repository layout

- `ct/infnoise-trng.sh` - Proxmox helper script that creates a container and runs the installer
- `install/infnoise-trng-install.sh` - in-container setup script
- `scripts/trng-push.py` - refill client
- `systemd/` - service and timer units
- `udev/` - FTDI device rule

## Assumptions

- Proxmox host can pass the USB device into the container
- the Infinite Noise device presents as FTDI vendor `0403` and product `6015`
- the Cloudflare side already has a `TRNG_DB` binding and a `TRNG_INGEST_TOKEN` secret

## Quick start

### Option 1: run the Proxmox helper from the host

Run the helper directly on the Proxmox host and pin it to the current release tag (`v0.1.1`). This section is kept in sync with `VERSION` by `scripts/update-release-version.sh`:

```bash
INFNOISE_LXC_REF="v0.1.1" bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
```

Or, if you prefer two commands:

```bash
export INFNOISE_LXC_REF="v0.1.1"
bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
```

What happens:

1. the helper creates a Debian 13 LXC
2. it mounts `/dev/bus/usb` into the container, writes the needed `lxc.cgroup2.devices.allow` entry into the CT config, and reboots the CT so USB access is applied
3. it downloads the matching release tarball from GitHub
4. it copies the installer payload into the container
5. it runs the in-container installer and enables `infnoise-trng.timer`

After the container is created, edit `/etc/default/infnoise-trng` inside it, set the ingest token, and start the timer.

You can override the release asset URL for testing:

```bash
export INFNOISE_LXC_REF="v0.1.1"
export INFNOISE_LXC_TARBALL_URL="https://github.com/w33ts/infnoise-lxc/releases/download/v0.1.1/infnoise-lxc-v0.1.1.tar.gz"
bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
```

### Troubleshooting

If the helper clears the terminal and exits with:

```text
/dev/fd/62: line 364: SSH_CLIENT: unbound variable
```

you were hitting an upstream `community-scripts` helper bug triggered when `SSH_CLIENT` is unset. `ct/infnoise-trng.sh` now initializes that variable before sourcing the upstream helper, so current versions run correctly from the Proxmox console, Web UI shell, and non-SSH sessions.

If you are running an older helper revision, use:

```bash
SSH_CLIENT='' INFNOISE_LXC_REF="v0.1.1" bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
```

If the helper exits with:

```text
Unknown option: lxc.cgroup2.devices.allow
400 unable to parse option
```

you are running an older revision that tried to pass a low-level LXC config key through `pct set`. Current versions write `lxc.cgroup2.devices.allow: c 189:* rwm` directly to `/etc/pve/lxc/<CTID>.conf`, then reboot the container so the USB permission takes effect.

To repair an already-created container manually from the Proxmox host:

```bash
printf '%s\n' 'lxc.cgroup2.devices.allow: c 189:* rwm' >> /etc/pve/lxc/<CTID>.conf
pct set <CTID> -mp0 /dev/bus/usb,mp=/dev/bus/usb
pct reboot <CTID>
```

Also make sure the environment variable and `bash` command are separated. This is invalid:

```bash
export INFNOISE_LXC_REF="v0.1.1"bash <(curl ...)
```

### Option 2: run the installer inside an existing LXC

1. Create a Debian 13 container.
2. Pass the USB device through to the container.
3. Download and extract a release tarball inside the container.
4. Run:

```bash
INSTALL_ROOT=/path/to/infnoise-lxc-v0.1.1 sudo /path/to/infnoise-lxc-v0.1.1/install/infnoise-trng-install.sh
```

5. Copy `.env.example` to `/etc/default/infnoise-trng` and fill in the token.
6. Enable the timer:

```bash
sudo systemctl enable --now infnoise-trng.timer
```

## Configuration

The installer expects an environment file at `/etc/default/infnoise-trng`.

```bash
TRNG_INGEST_URL="https://w33t.io/api/trng/refill"
TRNG_INGEST_TOKEN="replace-me"
TRNG_SOURCE="proxmox-infnoise"
TRNG_BATCH_BYTES="8192"
INFNOISE_BINARY="/usr/local/bin/infnoise"
INFNOISE_HEALTH_TIMEOUT_SECONDS="3"
INFNOISE_REPO_URL="https://github.com/13-37-org/infnoise.git"
INFNOISE_REF="0.3.0"
```

## Service model

The timer runs every 30 seconds by default.

Each run:

1. reads a batch of whitened bytes from `infnoise`
2. captures health output from `infnoise --debug --no-output`
3. posts both to the Cloudflare ingest endpoint

If the device is unavailable or the API rejects the refill, the unit fails and the problem is visible through `systemctl status` and the journal.

## Useful commands

```bash
systemctl status infnoise-trng.timer infnoise-trng.service
journalctl -u infnoise-trng.service -n 100 --no-pager
python3 /opt/infnoise-trng/trng-push.py
/usr/local/bin/infnoise --debug --no-output
```

## Releases

- Proxmox host installs require `INFNOISE_LXC_REF` to be set to an explicit tag.
- Tagging `v*` publishes `infnoise-lxc-<tag>.tar.gz` and a `.sha256` checksum as GitHub release assets.
- The GitHub release body includes install commands for the exact published tag.
- The release package is built by `scripts/release-package.sh` and contains the helper, installer, service files, udev rule, env template, and docs.
- CI validates the shell scripts and verifies that the release package can be built before merge.
- `RELEASING.md` documents the tag-and-publish workflow.

## Notes

- This sidecar uses the driver's normal whitened output. It does not expose raw `--raw` bits to the public API.
- Health values come from the driver's own debug reporting, which is enough for the status page and refill monitoring.
- The helper script mounts `/dev/bus/usb` into the container and adds the needed cgroup permission, but you may still need to adjust the exact passthrough on your host if your USB topology changes.

## License

MIT
