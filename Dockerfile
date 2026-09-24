# mkxp-web-jspi build environment
# Pinned to Emscripten 3.1.61 (June 2023): the earliest emsdk with the STANDARD JSPI
# API (-s JSPI / ASYNCIFY=2) this engine relies on, and still close enough to the 2023
# mkxp-web codebase to build it (emsdk "latest" breaks this code). All deps + mkxp are
# built with this one toolchain so there is no 3.1.35-vs-3.1.61 ABI mismatch.
#
# Forced to linux/amd64: this emsdk ships no arm64-linux prebuilt binaries, so on Apple
# Silicon it runs under emulation. The compile target is wasm32 regardless of host arch,
# so the produced .wasm is identical.
FROM --platform=linux/amd64 ubuntu:22.04

ARG EMSDK_VERSION=3.1.61
ENV DEBIAN_FRONTEND=noninteractive

# Build + game-processing dependencies.
# - mm-common/libtool/autoconf/automake: libsigc++ & pixman autotools builds
# - rake/ruby/bison: mruby build
# - imagemagick/xxd(vim-common)/file/coreutils: gameasync processing (make_mapping.sh)
# - rsync: import-game.sh copies the game tree; timidity: MIDI -> OGG (convert_audio.sh)
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git python3 python3-pip wget curl unzip xz-utils \
      ca-certificates pkg-config autoconf automake libtool mm-common \
      ruby rake bison \
      imagemagick vim-common file coreutils ffmpeg rsync timidity \
    && rm -rf /var/lib/apt/lists/*

# Emscripten SDK (pinned)
RUN git clone https://github.com/emscripten-core/emsdk.git /opt/emsdk \
    && cd /opt/emsdk \
    && ./emsdk install ${EMSDK_VERSION} \
    && ./emsdk activate ${EMSDK_VERSION} \
    && rm -rf /opt/emsdk/downloads

# Make emcc/em++/emcmake/emmake available on PATH for all shells
ENV EMSDK=/opt/emsdk
ENV PATH="/opt/emsdk:/opt/emsdk/upstream/emscripten:/opt/emsdk/node/*/bin:${PATH}"

WORKDIR /src
# The repo is bind-mounted at /src at run time, so build artifacts land on the host.
ENTRYPOINT ["/bin/bash"]
