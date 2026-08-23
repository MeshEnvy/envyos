#!/usr/bin/env bash
# Deprecated wrapper — use ./envyos build instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/envyos" build "$@"
