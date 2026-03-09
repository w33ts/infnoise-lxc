# Releasing

This project ships a versioned install payload for the Proxmox host helper.

Each release publishes these GitHub assets:

- `infnoise-lxc-<tag>.tar.gz`
- `infnoise-lxc-<tag>.sha256`

The host-side helper script downloads that tarball, pushes the payload into the new container, and runs the in-container installer.

## Release checklist

1. Make sure `main` contains the changes you want to ship.
2. Pick a new semantic version tag such as `v0.1.2`.
3. Update `VERSION` and run `scripts/update-release-version.sh`.
4. Commit the regenerated docs.
5. Create and push the tag.
6. Wait for the `Release` GitHub Actions workflow to finish.
7. Confirm the GitHub Release contains the tarball, checksum assets, and install commands.
8. Test the Proxmox host install flow with the new tag.

## Local validation

Run these checks before tagging:

```bash
scripts/update-release-version.sh --check
bash -n ct/infnoise-trng.sh install/infnoise-trng-install.sh scripts/release-package.sh scripts/update-release-version.sh scripts/render-release-body.sh
python3 -m py_compile scripts/trng-push.py
./scripts/release-package.sh test-build
```

If `shellcheck` is installed locally, also run:

```bash
shellcheck ct/infnoise-trng.sh install/infnoise-trng-install.sh scripts/release-package.sh scripts/update-release-version.sh scripts/render-release-body.sh
```

## Create a release tag

```bash
git checkout main
git pull --ff-only
printf '%s\n' v0.1.2 > VERSION
scripts/update-release-version.sh
git commit -am "Prepare v0.1.2 release"
git tag v0.1.2
git push origin v0.1.2
```

The tag push triggers `.github/workflows/release.yml`, which:

- validates the shell scripts
- verifies `README.md` and `RELEASING.md` match `VERSION`
- builds the release tarball with `scripts/release-package.sh`
- uploads the tarball and checksum to the GitHub Release page
- adds install commands for that exact tag to the release body

## Verify the published assets

After the workflow completes, verify that these files exist on the release page:

- `infnoise-lxc-v0.1.2.tar.gz`
- `infnoise-lxc-v0.1.2.sha256`

You can also verify the checksum after downloading:

```bash
sha256sum -c infnoise-lxc-v0.1.2.sha256
```

## Test the published release

On the Proxmox host, run:

```bash
export INFNOISE_LXC_REF="v0.1.2"
bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
```

Then update `/etc/default/infnoise-trng` inside the container, start the timer, and confirm the service is healthy.
