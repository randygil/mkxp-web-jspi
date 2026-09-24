#!/bin/bash

# Install OS deps
# sudo apt install mm-common libtool rake ruby

# Fail immediately
set -e

# Set optimization level
export CFLAGS="-O3 -g0"
export CXXFLAGS="-O3 -g0"
export CPPFLAGS="-O3 -g0"
export LDFLAGS="-O3 -g0"

# Make deps folder
mkdir -p deps
cd deps

# Get libsigc++
if [ ! -d "libsigc++" ]
then
    wget https://github.com/libsigcplusplus/libsigcplusplus/releases/download/2.12.0/libsigc++-2.12.0.tar.xz -O libsigc++.tar.xz
    tar xf libsigc++.tar.xz && rm libsigc++.tar.xz
    mv libsigc++* libsigc++
fi

# Get pixman
if [ ! -d "pixman" ]
then
    wget https://www.cairographics.org/releases/pixman-0.42.0.tar.gz -O pixman.tar.gz
    tar xf pixman.tar.gz && rm pixman.tar.gz
    mv pixman* pixman
fi

# Get physfs
if [ ! -d "physfs" ]
then
    wget https://icculus.org/physfs/downloads/physfs-3.0.2.tar.bz2 -O physfs.tar.bz2
    tar xf physfs.tar.bz2 && rm physfs.tar.bz2
    mv physfs* physfs
fi

# Get mruby
if [ ! -d "mruby" ]
then
    wget https://github.com/mruby/mruby/archive/2.1.2.tar.gz -O mruby.tar.gz
    tar xf mruby.tar.gz && rm mruby.tar.gz
    mv mruby* mruby
fi

# Get emscripten
if [ ! -d "emsdk" ]
then
    echo "Downloading emscripten"
    git clone https://github.com/emscripten-core/emsdk.git
    cd emsdk
    git pull
    ./emsdk install latest
    ./emsdk activate latest
    cd ..
fi

# Activate emscripten
source emsdk/emsdk_env.sh

# Build libsigc++
if [ ! -f "libsigc++/sigc++/.libs/libsigc-2.0.a" ]
then
    cd libsigc++
    emconfigure ./autogen.sh
    emconfigure ./configure --enable-static --disable-shared
    emmake make clean
    emmake make -j4 || true
    cd ..
fi

# Build pixman
if [ ! -f "pixman/pixman/.libs/libpixman-1.a" ]
then
    cd pixman
    emconfigure ./configure --enable-static --disable-shared
    emmake make clean
    cd pixman
    emmake make -j4 libpixman-1.la
    cd ../..
fi

# Build physfs
if [ ! -f "physfs/libphysfs.a" ]
then
    cd physfs
    emcmake cmake .
    emmake make clean
    emmake make -j4 physfs-static
    cd ..
fi

# Build mruby
if [ ! -f "mruby/build/wasm32-unknown-gnu/lib/libmruby.a" ]
then
    cd mruby
    cp ../../extra/build_config.rb ../../extra/vm.c.patch ../../extra/mruby-web.patch ./
    patch -p0 --forward < vm.c.patch
    patch -p0 --forward < mruby-web.patch
    make clean
    make
    cd ..
fi

# Done building deps
echo "Finished building dependencies"
cd ..

# Build mkxp
emcmake cmake .
emmake make -j4

# Done building
echo "Finished building MKXP"

# Copy to build directory
mkdir -p build
cp -R mkxp.html mkxp.wasm mkxp.js extra/*.webmanifest extra/js build/

# ==========================
# GAME_PROCESSING
# ==========================
cd build

if [ ! -d "gameasync" ]
then
    # Get sample game
    wget https://github.com/pulsejet/knight-blade-web-async/archive/gh-pages.zip -O game.zip
    unzip game.zip "knight-blade-web-async-gh-pages/gameasync/*"
    mv knight-blade-web-async-gh-pages/gameasync .
    rm -rf knight-blade-web-async-gh-pages
    rm -f game.zip

    # Begin processing
    cd gameasync

    # Copy standard rgss1 if custom not present
    if [ ! -f "rgss.rb" ]
    then
        cp ../../extra/rgss.rb .
    fi

    # Make mappings
    ../../extra/make_mapping.sh

    # Preload data
    rm -rf preload ../preload
    cp ../../extra/dump* .
    for f in Data/*
    do
        ./dump.sh "$f" > /dev/null
        echo "Processed file: $f"
    done
    rm dump*
    mv preload ..

    # Game processing done
    cd ..
fi

# Make deployable
mv mkxp.html index.html
touch .nojekyll

# Done
echo "Finished everything"
cd ..
