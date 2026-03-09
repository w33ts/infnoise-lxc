#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <version>\n' "$0" >&2
  exit 1
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'version must look like v0.1.1\n' >&2
  exit 1
fi

cat <<EOF
## Install

Run the Proxmox helper with this release:

\`\`\`bash
INFNOISE_LXC_REF="$VERSION" bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
\`\`\`

Or with two commands:

\`\`\`bash
export INFNOISE_LXC_REF="$VERSION"
bash <(curl -fsSL https://raw.githubusercontent.com/w33ts/infnoise-lxc/main/ct/infnoise-trng.sh)
\`\`\`

Manual installer example:

\`\`\`bash
INSTALL_ROOT=/path/to/infnoise-lxc-$VERSION sudo /path/to/infnoise-lxc-$VERSION/install/infnoise-trng-install.sh
\`\`\`
EOF
