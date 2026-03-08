#!/usr/bin/env bash
set -euo pipefail

docker run -it --rm \
  -v "${APPDATA_DIR}/bazarr-sync/config.yaml:/usr/src/app/config.yaml" \
  --network traefik \
  ghcr.io/ajmandourah/bazarr-sync:latest \
  bazarr-sync sync shows movies
