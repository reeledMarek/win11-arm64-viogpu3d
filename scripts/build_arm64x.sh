#!/usr/bin/env bash
# Build ARM64EC objects and link ARM64X hybrid Mesa + Vulkan loader DLLs.
# Requires build_mesa.sh and build_vulkan_runtime.sh to have been run first.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPTS/build_mesa_arm64ec.sh"
python3 "$SCRIPTS/link_arm64x.py"
"$SCRIPTS/build_vulkan_arm64x.sh"
