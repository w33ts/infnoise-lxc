#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s [--check]\n' "$0" >&2
}

CHECK_ONLY=0
if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

if [[ $# -eq 1 ]]; then
  if [[ "$1" != "--check" ]]; then
    usage
    exit 1
  fi
  CHECK_ONLY=1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
  printf 'missing VERSION file\n' >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'VERSION must contain a semantic version like v0.1.1\n' >&2
  exit 1
fi

python3 - "$ROOT_DIR" "$VERSION" "$CHECK_ONLY" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
version = sys.argv[2]
check_only = sys.argv[3] == "1"

files = [root / "README.md", root / "RELEASING.md"]
original = {path: path.read_text() for path in files}
updated = dict(original)

updated[files[0]] = re.sub(r"current release tag \(`v[^`]+`\)", f"current release tag (`{version}`)", updated[files[0]])
updated[files[0]] = re.sub(r'INFNOISE_LXC_REF="v[0-9]+\.[0-9]+\.[0-9]+"', f'INFNOISE_LXC_REF="{version}"', updated[files[0]])
updated[files[0]] = re.sub(r'https://github\.com/w33ts/infnoise-lxc/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/infnoise-lxc-v[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz', f'https://github.com/w33ts/infnoise-lxc/releases/download/{version}/infnoise-lxc-{version}.tar.gz', updated[files[0]])
updated[files[0]] = re.sub(r'infnoise-lxc-v[0-9]+\.[0-9]+\.[0-9]+/install/infnoise-trng-install\.sh', f'infnoise-lxc-{version}/install/infnoise-trng-install.sh', updated[files[0]])
updated[files[0]] = re.sub(r'INSTALL_ROOT=/path/to/infnoise-lxc-v[0-9]+\.[0-9]+\.[0-9]+', f'INSTALL_ROOT=/path/to/infnoise-lxc-{version}', updated[files[0]])

updated[files[1]] = re.sub(r'Pick a new semantic version tag such as `v[0-9]+\.[0-9]+\.[0-9]+`\.', f'Pick a new semantic version tag such as `{version}`.', updated[files[1]])
updated[files[1]] = re.sub(r'git tag v[0-9]+\.[0-9]+\.[0-9]+', f'git tag {version}', updated[files[1]])
updated[files[1]] = re.sub(r'git push origin v[0-9]+\.[0-9]+\.[0-9]+', f'git push origin {version}', updated[files[1]])
updated[files[1]] = re.sub(r'infnoise-lxc-v[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz', f'infnoise-lxc-{version}.tar.gz', updated[files[1]])
updated[files[1]] = re.sub(r'infnoise-lxc-v[0-9]+\.[0-9]+\.[0-9]+\.sha256', f'infnoise-lxc-{version}.sha256', updated[files[1]])
updated[files[1]] = re.sub(r'sha256sum -c infnoise-lxc-v[0-9]+\.[0-9]+\.[0-9]+\.sha256', f'sha256sum -c infnoise-lxc-{version}.sha256', updated[files[1]])
updated[files[1]] = re.sub(r'INFNOISE_LXC_REF="v[0-9]+\.[0-9]+\.[0-9]+"', f'INFNOISE_LXC_REF="{version}"', updated[files[1]])

changed = [path for path in files if updated[path] != original[path]]

if check_only:
    if changed:
        print("release documentation is out of date; run scripts/update-release-version.sh", file=sys.stderr)
        for path in changed:
            print(path.relative_to(root), file=sys.stderr)
        sys.exit(1)
    sys.exit(0)

for path in changed:
    path.write_text(updated[path])
PY
