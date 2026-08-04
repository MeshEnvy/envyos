# Reproducible Linux motatool builds (aarch64 + x86_64 gnu).
# Host only needs Docker — avoids missing linux-gnu cross linkers on macOS.
#
# Build image (once):
#   docker build -t envyos-motatool-build docker/motatool-build
#
# Invoked by scripts/build-motatool.sh (mounts repo at /src).

FROM rust:bookworm

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      $(if [ "$TARGETARCH" = "amd64" ]; then echo gcc-aarch64-linux-gnu libc6-dev-arm64-cross; fi) \
      $(if [ "$TARGETARCH" = "arm64" ]; then echo gcc-x86-64-linux-gnu libc6-dev-amd64-cross; fi) \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu

COPY motatool-build.sh /usr/local/bin/motatool-build
RUN chmod +x /usr/local/bin/motatool-build

WORKDIR /src/motatool
ENTRYPOINT ["/usr/local/bin/motatool-build"]
