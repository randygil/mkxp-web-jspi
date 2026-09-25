#!/usr/bin/env python3
"""
WEB PORT: build the offline game pack (build/gamepack-<id>.zip + build/gamepack.json).

The "Download game" button fetches this ONE zip into the browser's Origin Private File
System (OPFS) instead of fetching the ~26k game files one by one. At boot, js/gamepack.js
reads the zip's central directory and drive.js serves every game asset straight out of it
(local File.slice reads), so the game plays with no network at all.

Layout of the zip:
  * one entry per real file in mapping.js, arcname = the mapping path (e.g.
    "Graphics/Pictures/title.png"), so lookups use the same keys as the loader;
  * each entry's central-directory COMMENT is its md5 from mapping.js. The loader only
    uses a pack entry whose md5 matches the CURRENT mapping.js, so after a content
    redeploy a stale pack is used for the unchanged files and the rest load from the
    network (and the button offers "Update game");
  * already-compressed media (png/ogg/mp3/...) is STORED (zero decode cost), everything
    else (rxdata, rb, ttf, ...) is DEFLATEd (inflated in the browser with the native
    DecompressionStream).

Run AFTER regen-mapping.sh (it reads the md5s from mapping.js), and again whenever
mapping.js is regenerated:
    python3 gen-pack.py [path/to/mkxp-web/build]
"""
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, "mkxp-web", "build")
GA = os.path.join(BUILD, "gameasync")
MAPJS = os.path.join(GA, "mapping.js")

# Already compressed: deflating them only costs CPU on both ends.
STORED_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ogg", ".oga", ".opus", ".mp3",
              ".m4a", ".aac", ".mp4", ".webm", ".ogv", ".zip", ".7z", ".gz", ".br"}

ENTRY_RE = re.compile(r'^\["[^"]*", "(.*)\?h=([0-9a-fA-F]*)"\],?\s*$')


def read_mapping():
    entries = []
    with open(MAPJS, encoding="utf-8") as f:
        for line in f:
            m = ENTRY_RE.match(line)
            if not m or not m.group(2):
                continue  # not an entry, or a directory marker (empty hash)
            entries.append((m.group(1), m.group(2).lower()))
    return entries


def main():
    if not os.path.isfile(MAPJS):
        sys.exit("ERROR: %s not found (run regen-mapping.sh first)" % MAPJS)
    entries = read_mapping()
    if not entries:
        sys.exit("ERROR: no file entries in mapping.js")

    missing = [p for p, _ in entries if not os.path.isfile(os.path.join(GA, p))]
    if missing:
        sys.exit("ERROR: %d mapping.js file(s) missing on disk, e.g. %s (regen mapping.js)"
                 % (len(missing), missing[0]))

    # Content id: changes whenever any file (or the file list) changes.
    h = hashlib.md5()
    for path, md5 in sorted(entries):
        h.update(("%s:%s\n" % (path, md5)).encode("utf-8"))
    pack_id = h.hexdigest()[:16]
    name = "gamepack-%s.zip" % pack_id
    out = os.path.join(BUILD, name)
    tmp = out + ".tmp"

    print(">>> Packing %d files into %s" % (len(entries), name))
    total_in = 0
    with zipfile.ZipFile(tmp, "w", allowZip64=True) as zf:
        for i, (path, md5) in enumerate(entries, 1):
            src = os.path.join(GA, path)
            # Reproducible bytes: same content -> same zip, whatever the checkout mtimes or
            # build OS. The pack is rebuilt on every deploy (deploy/Dockerfile), and a client
            # resuming a download (HTTP Range) across a redeploy must get the same bytes.
            zi = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            zi.file_size = os.path.getsize(src)
            zi.create_system = 3                  # "Unix", also when built on Windows
            zi.external_attr = 0o100644 << 16     # regular file, rw-r--r--
            ext = os.path.splitext(path)[1].lower()
            if ext in STORED_EXT:
                zi.compress_type = zipfile.ZIP_STORED
            else:
                zi.compress_type = zipfile.ZIP_DEFLATED  # zlib default level (6)
            zi.comment = md5.encode("ascii")
            with open(src, "rb") as fin, zf.open(zi, "w") as fout:
                shutil.copyfileobj(fin, fout, 1 << 20)
            total_in += zi.file_size
            if i % 3000 == 0:
                print("   ...%d / %d" % (i, len(entries)))
    os.replace(tmp, out)

    # Drop packs from previous builds so they don't pile up in build/.
    for f in os.listdir(BUILD):
        if f.startswith("gamepack-") and f.endswith(".zip") and f != name:
            os.remove(os.path.join(BUILD, f))

    size = os.path.getsize(out)
    meta = {"id": pack_id, "file": name, "size": size, "count": len(entries)}
    with open(os.path.join(BUILD, "gamepack.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f)
        f.write("\n")
    print(">>> %s: %.1f MB (%.1f MB of game files), id %s"
          % (name, size / 1048576.0, total_in / 1048576.0, pack_id))


if __name__ == "__main__":
    main()
