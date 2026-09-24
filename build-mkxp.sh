#!/bin/bash
# Runs INSIDE the Docker container. Builds mkxp-web deps + engine, then packages
# the stock demo game. Based on the upstream build.sh, but uses the pinned emsdk
# baked into the image instead of downloading "latest".
set -e

cd /src/mkxp-web

export CFLAGS="-O3 -g0"
export CXXFLAGS="-O3 -g0"
export CPPFLAGS="-O3 -g0"
export LDFLAGS="-O3 -g0"

# Activate the pinned Emscripten toolchain
source /opt/emsdk/emsdk_env.sh
echo ">>> Using: $(emcc --version | head -1)"

mkdir -p deps
cd deps

# --- libsigc++ ---
if [ ! -d "libsigc++" ]; then
  wget -q https://github.com/libsigcplusplus/libsigcplusplus/releases/download/2.12.0/libsigc++-2.12.0.tar.xz -O libsigc++.tar.xz
  tar xf libsigc++.tar.xz && rm libsigc++.tar.xz && mv libsigc++* libsigc++
fi
# --- pixman ---
if [ ! -d "pixman" ]; then
  wget -q https://www.cairographics.org/releases/pixman-0.42.0.tar.gz -O pixman.tar.gz
  tar xf pixman.tar.gz && rm pixman.tar.gz && mv pixman* pixman
fi
# --- physfs ---
if [ ! -d "physfs" ]; then
  wget -q https://icculus.org/physfs/downloads/physfs-3.0.2.tar.bz2 -O physfs.tar.bz2
  tar xf physfs.tar.bz2 && rm physfs.tar.bz2 && mv physfs* physfs
fi
# --- mruby ---
if [ ! -d "mruby" ]; then
  wget -q https://github.com/mruby/mruby/archive/2.1.2.tar.gz -O mruby.tar.gz
  tar xf mruby.tar.gz && rm mruby.tar.gz && mv mruby* mruby
fi

echo ">>> Building libsigc++"
if [ ! -f "libsigc++/sigc++/.libs/libsigc-2.0.a" ]; then
  cd libsigc++
  emconfigure ./autogen.sh --enable-static --disable-shared
  emconfigure ./configure --enable-static --disable-shared
  emmake make clean
  emmake make -j"$(nproc)" || true
  cd ..
fi

echo ">>> Building pixman"
if [ ! -f "pixman/pixman/.libs/libpixman-1.a" ]; then
  cd pixman
  emconfigure ./configure --enable-static --disable-shared
  emmake make clean
  cd pixman
  emmake make -j"$(nproc)" libpixman-1.la
  cd ../..
fi

echo ">>> Building physfs"
if [ ! -f "physfs/libphysfs.a" ]; then
  cd physfs
  emcmake cmake .
  emmake make clean
  emmake make -j"$(nproc)" physfs-static
  cd ..
fi

echo ">>> Building mruby"
if [ ! -f "mruby/build/wasm32-unknown-gnu/lib/libmruby.a" ]; then
  cd mruby
  cp ../../extra/build_config.rb ../../extra/vm.c.patch ../../extra/mruby-web.patch ./
  patch -p0 --forward < vm.c.patch || true
  patch -p0 --forward < mruby-web.patch || true
  make clean
  make
  cd ..
fi

echo ">>> Dependencies built. Building mkxp engine."
cd /src/mkxp-web
emcmake cmake .
# Warm the emcc system-port cache SERIALLY before the parallel make. On a fresh emsdk the
# first build must generate the SDL2/SDL2_image/SDL2_ttf/freetype/harfbuzz/ogg/vorbis/zlib
# ports into the cache; under `make -j` several emcc processes race for the cache lock and
# abort ("attempt to lock the cache while a parent process is holding the lock"). One serial
# compile builds them all up front so the parallel make just reuses them.
echo ">>> Warming emcc port cache (serial)"
echo 'int main(){return 0;}' > /tmp/warm.c
emcc /tmp/warm.c -s USE_SDL=2 -s USE_SDL_IMAGE=2 -s USE_SDL_TTF=2 -s USE_ZLIB=1 -s USE_OGG=1 -s USE_VORBIS=1 -o /tmp/warm.js || true
emmake make -j"$(nproc)"

mkdir -p build
# Copy ONLY the compiled engine into the (hand-authored) web harness in build/.
# We deliberately do NOT overwrite build/index.html (the browser harness) and do
# NOT bundle a game — add your own game with import-game.sh (see
# docs/BRING-YOUR-OWN-GAME.md). This keeps the engine repo game-free and license-clean.
cp -f mkxp.wasm mkxp.js build/

echo ""
echo ">>> DONE. Engine built: mkxp-web/build/mkxp.wasm + mkxp.js"
echo ">>> Next: import a game with import-game.sh, then serve build/ (docs/DEPLOY.md)."
ls -la /src/mkxp-web/build
