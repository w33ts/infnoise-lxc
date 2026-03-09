# Releasing

This project ships a versioned install payload for the Proxmox host helper.

Each release publishes these GitHub assets:

- `infnoise-lxc-<tag>.tar.gz`
- `infnoise-lxc-<tag>.sha256`

The host-side helper script downloads that tarball, pushes the payload into the new container, and runs the in-container installer.

## Release checklist

1. Make sure `main` contains the changes you want to ship.
2. Pick a new semantic version tag such as `v0.1.1`.
3. Update versioned install commands in `README.md` so they point at that new tag.
4. Create and push the tag.
5. Wait for the `Release` GitHub Actions workflow to finish.
6. Confirm the GitHub Release contains the tarball and checksum assets.
7. Test the Proxmox host install flow with the new tag.

## Local validation

Run these checks before tagging:

```bash
bash -n ct/infnoise-trng.sh install/infnoise-trng-install.sh scripts/release-package.sh
python3 -m py_compile scripts/trng-push.py
./scripts/release-package.sh test-build
```

If `shellcheck` is installed locally, also run:

```bash
shellcheck ct/infnoise-trng.sh install/infnoise-trng-install.sh scripts/release-package.sh
```

## Create a release tag

```bash
git checkout main
git pull --ff-only
git tag v0.1.1
git push origin v0.1.1
```

The tag push triggers `.github/workflows/release.yml`, which:

- validates the shell scripts
- builds the release tarball with `scripts/release-package.sh`
- uploads the tarball and checksum to the GitHub Release page

## Verify the published assets

After the workflow completes, verify that these files exist on the release page:

- `infnoise-lxc-v0.1.1.tar.gz`
- `infnoise-lxc-v0.1.1.sha256`

You can also verify the checksum after downloading:

```bash
sha256sum -c infnoise-lxc-v0.1.1.sha256
```

## Test the published release

On the Proxmox host, run:

```bash
export INFNOISE_LXC_REF="v0.1.1"
bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
```

Then update `/etc/default/infnoise-trng` inside the container, start the timer, and confirm the service is healthy.
