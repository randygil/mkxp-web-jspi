#!/bin/bash
# WEB PORT: JSPI build. Installs a JSPI-capable emsdk (>=3.1.61 = standard JSPI API,
# Chrome 126+), then rebuilds mkxp with -s JSPI (set in CMakeLists). First tries to
# REUSE the existing 3.1.35-built deps (libsigc++/pixman/physfs/mruby) and rebuild
# only mkxp -- if the wasm-object versions are link-compatible this is fast. If the
# link fails, rerun with REBUILD_DEPS=1 to rebuild mruby too.
set -e
EMV=3.1.61
echo ">>> installing emsdk ${EMV}"
/opt/emsdk/emsdk install ${EMV}
/opt/emsdk/emsdk activate ${EMV}
source /opt/emsdk/emsdk_env.sh
echo ">>> emcc: $(emcc --version | head -1)"
cd /src/mkxp-web

if [ "${REBUILD_DEPS}" = "1" ]; then
  # Rebuild ALL manual deps with ${EMV} to eliminate version-mixing. The 3.1.35
  # binaries LINKED against 3.1.61 but physfs (C) failed PHYSFS_init at runtime --
  # a 3.1.35-vs-3.1.61 libc ABI mismatch. C++ EH users (libsigc++, mruby) also need
  # wasm-EH to match mkxp's -fwasm-exceptions.
  export CXXFLAGS="-O3 -g0 -fwasm-exceptions -sSUPPORT_LONGJMP=wasm"
  export CFLAGS="-O3 -g0"

  echo ">>> rebuilding pixman (${EMV})"
  rm -f deps/pixman/pixman/.libs/libpixman-1.a
  ( cd deps/pixman && emconfigure ./configure --enable-static --disable-shared && emmake make clean && cd pixman && emmake make -j"$(nproc)" libpixman-1.la ) || true
  test -f deps/pixman/pixman/.libs/libpixman-1.a || { echo "PIXMAN BUILD FAILED"; exit 1; }

  echo ">>> rebuilding physfs (${EMV})"
  rm -f deps/physfs/libphysfs.a
  ( cd deps/physfs && emcmake cmake . && emmake make clean && emmake make -j"$(nproc)" physfs-static )
  test -f deps/physfs/libphysfs.a || { echo "PHYSFS BUILD FAILED"; exit 1; }

  echo ">>> rebuilding libsigc++ (wasm-EH)"
  rm -f deps/libsigc++/sigc++/.libs/libsigc-2.0.a
  ( cd deps/libsigc++ && emconfigure ./configure --enable-static --disable-shared && emmake make clean && emmake make -j"$(nproc)" ) || true
  test -f deps/libsigc++/sigc++/.libs/libsigc-2.0.a || { echo "LIBSIGC BUILD FAILED"; exit 1; }

  echo ">>> rebuilding mruby (wasm-EH + wasm-setjmp) with ${EMV}"
  rm -rf deps/mruby/build
  # `make || true`: mruby also links its bin tools (mirb/mruby/mrbc) against the
  # NOEXCEPT libc++ + emscripten-sjlj, which can't resolve wasm-EH personality
  # symbols (__wasm_lpad_context/_Unwind_CallPersonality). Those bins are NOT needed
  # -- mkxp only links libmruby.a, and mkxp's own link (full libc++ + -fwasm-exceptions)
  # DOES provide them. So a bin-link failure after libmruby.a is archived is fine.
  ( cd deps/mruby && cp -f ../../extra/build_config.rb ./ && (patch -p0 --forward < ../../extra/vm.c.patch || true) && (patch -p0 --forward < ../../extra/mruby-web.patch || true) && make clean && make ) || true
  test -f deps/mruby/build/wasm32-unknown-gnu/lib/libmruby.a || { echo "MRUBY BUILD FAILED (no libmruby.a)"; exit 1; }
fi

echo ">>> configuring + building mkxp (JSPI)"
rm -f CMakeCache.txt
rm -rf CMakeFiles
emcmake cmake . >/tmp/jspi-cmake.log 2>&1 || { echo "CMAKE FAILED"; tail -30 /tmp/jspi-cmake.log; exit 1; }
# Warm the emcc system-port cache SERIALLY first. On a fresh emsdk the first build
# must generate SDL2/SDL2_image/SDL2_ttf/freetype/harfbuzz/ogg/vorbis/zlib into the
# cache; under `make -j8` many emcc procs race for the cache lock and abort
# ("attempt to lock the cache while a parent process is holding the lock"). One
# serial compile builds them all up front so the parallel make just reuses them.
echo ">>> warming emcc port cache (serial)"
echo 'int main(){return 0;}' > /tmp/warm.c
emcc /tmp/warm.c -s USE_SDL=2 -s USE_SDL_IMAGE=2 -s USE_SDL_TTF=2 -s USE_ZLIB=1 -s USE_OGG=1 -s USE_VORBIS=1 -o /tmp/warm.js || true
emmake make -j"$(nproc)"
cp -f mkxp.wasm mkxp.js build/
echo ">>> JSPI BUILD DONE; wasm size:"; ls -la build/mkxp.wasm
