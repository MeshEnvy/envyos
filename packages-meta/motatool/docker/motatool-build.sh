#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/cargo/bin:${PATH}"

case "$(uname -m)" in
  x86_64)
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
    ;;
  aarch64)
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc
    ;;
esac

exec "$@"
