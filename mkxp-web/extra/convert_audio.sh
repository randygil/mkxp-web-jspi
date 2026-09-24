#!/bin/bash
# Convert a game's Audio/ tree to OGG Vorbis in place (run from the game root).
# MIDI -> OGG (timidity), OGG re-encode, WAV -> OGG. Each original is replaced only
# after its conversion succeeded, so a failed/missing tool never deletes audio.
# (Previously every file was written to a non-existent "CONV/" folder and the originals
# were deleted anyway, wiping the game's audio.)
shopt -s globstar nullglob

convert() {   # convert <src> <dst.ogg>
  local tmp="${2%.ogg}.__conv.ogg"
  if ffmpeg -nostdin -loglevel error -y -i "$1" -c:a libvorbis -qscale:a 0 "$tmp"; then
    mv -f "$tmp" "$2"
    return 0
  fi
  rm -f "$tmp"
  echo "  FAILED: $1 (kept)" >&2
  return 1
}

# MID2OGG
for file in Audio/**/*.mid Audio/**/*.midi; do
  filename="${file%.*}"
  echo "MIDI $filename"
  if timidity "$file" -Ow -o "$filename.__mid.wav" >/dev/null && convert "$filename.__mid.wav" "$filename.ogg"; then
    rm -f "$file"
  fi
  rm -f "$filename.__mid.wav"
done

# OGG REENCODE
for file in Audio/**/*.ogg; do
  echo "${file%.*}"
  convert "$file" "$file"
done

# WAV TO OGG
for file in Audio/**/*.wav; do
  filename="${file%.*}"
  echo "$filename"
  convert "$file" "$filename.ogg" && rm -f "$file"
done
