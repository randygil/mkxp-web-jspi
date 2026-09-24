#!/bin/bash
# Package a Pokemon Essentials (v20/v21, mkxp-z) game's scripts for mkxp-web.
# Run INSIDE the build container, after import-game.sh (which extracted scripts_src/):
#
#   docker run --rm -v "$PWD:/src" -v "/path/to/Game:/game:ro" \
#     -e GAME_TITLE="My Game" -e USER_LANGUAGE=es_ES mkxp-web-jspi /src/tools/essentials/pack.sh
#
# Writes build/gameasync/Data/Scripts.rxdata (base scripts + all plugins inlined, with the
# mruby rewrites/patches) and build/gameasync/rgss.rb (extra/rgss.rb + essentials_shim.rb),
# then refreshes their ?h= hashes in mapping.js.
# `pack.sh audio` also re-copies the game's Audio/ unconverted and fully regenerates mapping.js.
# SPLIT=<section name> splits that section at #==== banners to pinpoint load errors.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-/src}
GAME=${GAME:-/game}
GA=$REPO/mkxp-web/build/gameasync
if [ "$1" = audio ]; then
  rm -rf "$GA/Audio"; rsync -a "$GAME/Audio/" "$GA/Audio/"
fi
SPLIT="$SPLIT" ruby "$HERE/build_scripts.rb" "$REPO/scripts_src" "$GAME/Data/PluginScripts.rxdata" \
  "$HERE/patches.rb" "$GA/Data/Scripts.rxdata"
{
  cat "$REPO/mkxp-web/extra/rgss.rb"
  echo
  echo "WEB_GAME_TITLE = $(ruby -e 'p ENV.fetch("GAME_TITLE", "RGSS-Web")')"
  echo "WEB_USER_LANGUAGE = $(ruby -e 'p ENV.fetch("USER_LANGUAGE", "en_US")')"
  cat "$HERE/essentials_shim.rb"
} > "$GA/rgss.rb"
if [ "$1" = audio ]; then
  bash "$REPO/regen-mapping.sh" | tail -1
  cd "$REPO" && ruby gen-bitmap-map.rb | tail -1
else
  for f in Data/Scripts.rxdata rgss.rb; do
    h=$(md5sum "$GA/$f" | awk '{print $1}')
    sed -i -E "s#\"$f\?h=[0-9a-f]*\"#\"$f?h=$h\"#" "$GA/mapping.js"
    grep -o "\"$f?h=[0-9a-f]*\"" "$GA/mapping.js"
  done
fi
