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

### Option 1: run the installer inside an existing LXC

1. Create a Debian 13 container.
2. Pass the USB device through to the container.
3. Clone this repository into the container.
4. Run:

```bash
sudo ./install/infnoise-trng-install.sh
```

5. Copy `.env.example` to `/etc/default/infnoise-trng` and fill in the token.
6. Enable the timer:

```bash
sudo systemctl enable --now infnoise-trng.timer
```

### Option 2: use the Proxmox helper script

Set the repo URL first so the helper knows what to clone:

```bash
export INFNOISE_LXC_REPO_URL="https://github.com/w33ts/infnoise-lxc.git"
bash ct/infnoise-trng.sh
```

After the container is created, edit `/etc/default/infnoise-trng` inside it and start the timer.

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

## Notes

- This sidecar uses the driver's normal whitened output. It does not expose raw `--raw` bits to the public API.
- Health values come from the driver's own debug reporting, which is enough for the status page and refill monitoring.
- The helper script mounts `/dev/bus/usb` into the container and adds the needed cgroup permission, but you may still need to adjust the exact passthrough on your host if your USB topology changes.

## License

MIT
