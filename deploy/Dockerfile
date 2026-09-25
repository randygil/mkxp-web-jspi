# Deploy image for the RGSS-Web mkxp-web build. Build from the REPO ROOT:
#   docker build -f deploy/Dockerfile -t rgss-web .
# See deploy/README.md for run + hardening + TLS options.

##############################################################################
# Stage 1 — pre-compress text/wasm assets to .br (Brotli) + .gz so the runtime
# serves them statically with zero per-request CPU. Media (png/jpg/ogg/…) is
# already compressed and is deliberately skipped.
##############################################################################
FROM alpine:3 AS compress
RUN apk add --no-cache brotli gzip
WORKDIR /srv
COPY mkxp-web/build/ ./
# belt-and-suspenders: drop dev-only/non-served files (also excluded by .dockerignore)
RUN rm -rf .claude .htaccess .dockerignore Dockerfile 2>/dev/null || true
# Offline game pack for the "Download game" button (gen-pack.py): one zip of every game
# file + gamepack.json. Built here rather than committed -- GitHub rejects files > 100 MB --
# and reproducible, so an unchanged game yields byte-identical packs across deploys.
RUN apk add --no-cache python3
COPY gen-pack.py /tmp/gen-pack.py
RUN python3 /tmp/gen-pack.py /srv && rm /tmp/gen-pack.py
RUN set -eu; \
    find . -type f \( \
         -name '*.wasm' -o -name '*.js' -o -name '*.mjs' -o -name '*.json' \
      -o -name '*.html' -o -name '*.css'  -o -name '*.svg' -o -name '*.txt' \
      -o -name '*.dat'  -o -name '*.rxdata' -o -name '*.rb' -o -name '*.webmanifest' \
      \) -size +1k -print0 \
    | while IFS= read -r -d '' f; do \
        brotli -q 11 -kf "$f"; \
        gzip  -9    -kf "$f"; \
      done

##############################################################################
# Stage 2 — minimal static server (Caddy, official alpine image). Runs as a
# non-root user on an unprivileged port; TLS/HSTS belong at your reverse proxy.
##############################################################################
FROM caddy:2-alpine

LABEL org.opencontainers.image.title="rgss-web" \
      org.opencontainers.image.description="Client-side RMXP/RGSS game (mkxp-web-jspi) served by Caddy"

COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY --from=compress /srv /srv

# The official caddy binary carries cap_net_bind_service (to bind :80/:443 as
# non-root). We bind the unprivileged :8080 and run with --security-opt
# no-new-privileges, which REFUSES to exec a binary bearing permitted file-caps
# ("operation not permitted") -> strip them; we don't need them on :8080.
RUN apk add --no-cache libcap \
 && setcap -r /usr/bin/caddy \
 && apk del libcap

# Non-root: Caddy writes only to /config and /data (XDG_*_HOME set by the base
# image); /srv is served read-only. UID 10001 = unprivileged, no passwd entry needed.
RUN mkdir -p /data /config && chown -R 10001:10001 /data /config
USER 10001:10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/index.html >/dev/null 2>&1 || exit 1
