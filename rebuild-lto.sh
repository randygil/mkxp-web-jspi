#!/bin/bash
# WEB PORT PERF: LTO rebuild. Builds libmruby.a with -flto (bitcode) then links the
# mkxp engine NATIVELY against it (no -flto in CMakeLists EMS_FLAGS). wasm-ld still
# LTO-optimizes the bitcode libmruby.a members it pulls in, giving mruby whole-VM
# optimization, WITHOUT the full-LTO breakage: linking mkxp with -flto swaps in the
# bitcode system libs (lto/libc.a) and a JS-library dep then pulls libc's fileno in
# AFTER the LTO codegen pass -> "wasm-ld: attempt to add bitcode file after LTO".
# Reuses the mruby build if already present; pins emsdk 3.1.61 for JSPI.
#
# Run from the repo root:
#   docker run --rm --platform linux/amd64 \
#     -v "$PWD/mkxp-web:/src/mkxp-web" -v "$PWD/rebuild-lto.sh:/rebuild-lto.sh" \
#     mkxp-web-builder /rebuild-lto.sh
# Then bump BUILD_VER in build/index.html so clients (and the Service Worker) refetch.
set -e
EMV=3.1.61
echo ">>> installing emsdk ${EMV}"
/opt/emsdk/emsdk install ${EMV}
/opt/emsdk/emsdk activate ${EMV}
source /opt/emsdk/emsdk_env.sh
echo ">>> emcc: $(emcc --version | head -1)"
cd /src/mkxp-web

# mruby with -flto (bitcode libmruby.a). Reuse if present (persists on the host mount).
if [ ! -f deps/mruby/build/wasm32-unknown-gnu/lib/libmruby.a ]; then
  echo ">>> building mruby with -flto (wasm-EH + wasm-setjmp)"
  rm -rf deps/mruby/build
  # --forward skips the vm.c patch if already applied; || true keeps bin-link failures
  # (mirb/mruby/mrbc can't resolve wasm-EH personality syms) non-fatal -- only libmruby.a matters.
  ( cd deps/mruby && cp -f ../../extra/build_config.rb ./ && (patch -p0 --forward < ../../extra/vm.c.patch || true) && (patch -p0 --forward < ../../extra/mruby-web.patch || true) && make clean && make ) || true
  test -f deps/mruby/build/wasm32-unknown-gnu/lib/libmruby.a || { echo "MRUBY BUILD FAILED (no libmruby.a)"; exit 1; }
else
  echo ">>> reusing existing libmruby.a ($(ls -la deps/mruby/build/wasm32-unknown-gnu/lib/libmruby.a | awk '{print $5}') bytes) -- delete deps/mruby/build to force a rebuild"
fi

echo ">>> configuring mkxp (JSPI, native link vs bitcode libmruby.a)"
rm -f CMakeCache.txt
rm -rf CMakeFiles
emcmake cmake . >/tmp/lto-cmake.log 2>&1 || { echo "CMAKE FAILED"; tail -30 /tmp/lto-cmake.log; exit 1; }

# Warm the emcc port cache SERIALLY first so the parallel make doesn't race for the
# cache lock while generating SDL2/SDL2_ttf/freetype/harfbuzz/ogg/vorbis/zlib.
echo ">>> warming emcc port cache (serial)"
echo 'int main(){return 0;}' > /tmp/warm.c
emcc /tmp/warm.c -s USE_SDL=2 -s USE_SDL_IMAGE=2 -s USE_SDL_TTF=2 -s USE_ZLIB=1 -s USE_OGG=1 -s USE_VORBIS=1 -o /tmp/warm.js || true

echo ">>> building mkxp"
emmake make -j"$(nproc)"
cp -f mkxp.wasm mkxp.js build/
echo ">>> LTO BUILD DONE; wasm size:"; ls -la build/mkxp.wasm
