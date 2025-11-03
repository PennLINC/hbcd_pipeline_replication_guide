#!/bin/bash
set -euo pipefail

# Thin wrapper to run the Python implementation next to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "${SCRIPT_DIR}/warp_scalars.py" "$@"