#!/usr/bin/env python3
# WEB PORT test server: serves build/ with no-cache headers so mapping.js /
# Scripts.rxdata / rgss.rb reloads always fetch fresh (the browser's heuristic
# caching otherwise serves a stale mapping.js and ignores our ?h= hash bumps).
# Threaded + single-range "Range: bytes=N-[M]" support, like a real server, so the
# offline game pack download (gamepack-*.zip) can resume and doesn't block the game.
import http.server, os, re, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8124
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else "mkxp-web/build"
RANGE_RE = re.compile(r"bytes=(\d+)-(\d*)$")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=DIRECTORY, **k)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def send_head(self):
        m = RANGE_RE.match(self.headers.get("Range", "").strip())
        path = self.translate_path(self.path)
        if not m or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        start = int(m.group(1))
        end = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
        if start >= size or start > end:
            self.send_response(416)
            self.send_header("Content-Range", "bytes */%d" % size)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        f = open(path, "rb")
        f.seek(start)
        self._remaining = end - start + 1
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.send_header("Content-Length", str(self._remaining))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        return f

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "_remaining", None)
        if remaining is None:
            return super().copyfile(source, outputfile)
        while remaining > 0:
            buf = source.read(min(1 << 20, remaining))
            if not buf:
                break
            outputfile.write(buf)
            remaining -= len(buf)

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer.allow_reuse_address = True
http.server.ThreadingHTTPServer.daemon_threads = True
with http.server.ThreadingHTTPServer(("", PORT), Handler) as httpd:
    print(f"no-cache server on {PORT} serving {DIRECTORY}")
    httpd.serve_forever()
