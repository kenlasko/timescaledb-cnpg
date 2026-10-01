# TimescaleDB extension image for CloudNativePG ImageVolume
#
# Follows the postgres-extensions-containers pattern:
# https://github.com/cloudnative-pg/postgres-extensions-containers
#
# Uses the FULL TimescaleDB package from Timescale's apt repo
# (not the PGDG dfsg repack which strips TSL-licensed code).
# This includes the TSL module needed for compression,
# continuous aggregates, and other licensed features.

ARG BASE=ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
FROM $BASE AS builder

ARG PG_MAJOR=18
ARG EXT_VERSION
# Previous release whose libraries are kept alongside the current ones.
# Defaults to the newest stable release in the apt repo older than EXT_VERSION.
ARG PREV_EXT_VERSION

USER 0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -sL https://packagecloud.io/install/repositories/timescale/timescaledb/script.deb.sh | bash && \
    # Pin the loader (which owns timescaledb.control) to EXT_VERSION; otherwise
    # apt pulls the newest loader and default_version points at a missing .so
    LOADER_VERSION=$(apt-cache madison "timescaledb-2-loader-postgresql-${PG_MAJOR}" \
        | awk -v v="${EXT_VERSION}~" 'index($3, v) == 1 {print $3; exit}') && \
    test -n "${LOADER_VERSION}" || { echo "No loader package for ${EXT_VERSION}" >&2; exit 1; } && \
    apt-get install -y --no-install-recommends \
        "timescaledb-2-loader-postgresql-${PG_MAJOR}=${LOADER_VERSION}" \
        "timescaledb-2-${EXT_VERSION}-postgresql-${PG_MAJOR}" && \
    if [ -z "${PREV_EXT_VERSION}" ]; then \
        PREV_EXT_VERSION=$( \
            { apt-cache pkgnames "timescaledb-2-" \
                | sed -nE "s/^timescaledb-2-([0-9]+\.[0-9]+\.[0-9]+)-postgresql-${PG_MAJOR}\$/\1/p"; \
              echo "${EXT_VERSION}"; } \
            | sort -uV | grep -B1 -xF "${EXT_VERSION}" | grep -vxF "${EXT_VERSION}" || true); \
    fi && \
    test -n "${PREV_EXT_VERSION}" || { echo "No release found before ${EXT_VERSION}" >&2; exit 1; } && \
    echo "Current: ${EXT_VERSION}, previous: ${PREV_EXT_VERSION}" && \
    # Extract (not install) the previous package so it can't clash with the current one
    cd /tmp && \
    apt-get download "timescaledb-2-${PREV_EXT_VERSION}-postgresql-${PG_MAJOR}" && \
    dpkg-deb -x timescaledb-2-"${PREV_EXT_VERSION}"-postgresql-"${PG_MAJOR}"_*.deb /tmp/prev && \
    # Stage exactly: loader + current core/TSL + previous core/TSL
    mkdir -p /out/lib && \
    LIB=/usr/lib/postgresql/${PG_MAJOR}/lib && \
    cp "${LIB}/timescaledb.so" \
       "${LIB}/timescaledb-${EXT_VERSION}.so" \
       "${LIB}/timescaledb-tsl-${EXT_VERSION}.so" \
       "/tmp/prev${LIB}/timescaledb-${PREV_EXT_VERSION}.so" \
       "/tmp/prev${LIB}/timescaledb-tsl-${PREV_EXT_VERSION}.so" \
       /out/lib/ && \
    ls -l /out/lib && \
    rm -rf /tmp/prev /tmp/*.deb /var/lib/apt/lists/*

FROM scratch
ARG PG_MAJOR=18
ARG EXT_VERSION

# Licenses
COPY --from=builder /usr/share/doc/timescaledb-2-loader-postgresql-${PG_MAJOR}/copyright /licenses/timescaledb-loader/
COPY --from=builder /usr/share/doc/timescaledb-2-${EXT_VERSION}-postgresql-${PG_MAJOR}/copyright /licenses/timescaledb/

# Shared libraries: loader, current core + TSL, and the previous release's
# core + TSL. The loader picks timescaledb-<installed version>.so by filename,
# so databases not yet on ALTER EXTENSION ... UPDATE keep loading.
COPY --from=builder /out/lib/ /lib/

# Extension control + SQL files
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/timescaledb* /share/extension/

USER 65532:65532
