#!/usr/bin/env bash
set -euo pipefail

# The upstream opencode v2 image runs as root with HOME=/root. Named volumes
# are created root-owned, so just make sure the data directories exist.
mkdir -p /root/.local/share/opencode \
         /root/.local/state/opencode \
         /root/.cache/opencode \
         /root/.config/opencode \
         /root/work

if [ -z "${OPENCODE_PASSWORD:-}" ]; then
  echo "WARNING: OPENCODE_PASSWORD is not set; opencode will generate a random" \
       "password for this run and print it below." >&2
fi

# `opencode serve` uses its working directory as the default project/location,
# so pin it explicitly instead of relying on the image WORKDIR.
cd /root/work

echo "Starting opencode server on 0.0.0.0:4444 (project /root/work)"
exec opencode serve --hostname 0.0.0.0 --port 4444
