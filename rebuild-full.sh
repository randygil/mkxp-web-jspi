#!/bin/bash
# ENGINE FIX rebuild: recompile libmruby.a AND mkxp with matching C++ exception
# config so mruby's raise/rescue is catchable. Copies only wasm/js into build/.
set -e
source /opt/emsdk/emsdk_env.sh
cd /src/mkxp-web

echo ">>> Rebuilding mruby with exception catching enabled"
rm -rf deps/mruby/build
cd deps/mruby
cp -f ../../extra/build_config.rb ./
patch -p0 --forward < ../../extra/vm.c.patch || true
patch -p0 --forward < ../../extra/mruby-web.patch || true
make clean || true
make
cd /src/mkxp-web
test -f deps/mruby/build/wasm32-unknown-gnu/lib/libmruby.a || { echo "MRUBY BUILD FAILED"; exit 1; }

echo ">>> Rebuilding mkxp engine"
emcmake cmake .
emmake make -j"$(nproc)"
cp -f mkxp.wasm mkxp.js build/
echo ">>> FULL REBUILD DONE; wasm:"; ls -la build/mkxp.wasm
