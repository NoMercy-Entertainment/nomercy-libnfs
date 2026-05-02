FROM ubuntu:24.04 AS libnfs-base

LABEL maintainer="NoMercy Entertainment"
LABEL description="libnfs cross-compile base — shared build deps"

ENV DEBIAN_FRONTEND=noninteractive

# ── Version pin ───────────────────────────────────────────────
# libnfs-6.0.2, latest stable as of 2024-12.
# SHA256 of https://github.com/sahlberg/libnfs/archive/refs/tags/libnfs-6.0.2.tar.gz
# Regenerate: wget -qO- <url> | sha256sum
ENV LIBNFS_TAG=libnfs-6.0.2
ENV LIBNFS_SHA256=8e03a30c5b11a4aebcc69af5b85d9ecc28fa0a4cdd38b76ec50cde38b6d53d45

RUN apt-get update >/dev/null 2>&1 \
    && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    ninja-build \
    pkg-config \
    wget \
    file \
    binutils \
    >/dev/null 2>&1 \
    && apt-get autoremove -y >/dev/null 2>&1 \
    && apt-get clean -y >/dev/null 2>&1 \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /build

RUN git config --global user.email "builder@nomercy.tv" \
    && git config --global user.name "Builder" \
    && git config --global advice.detachedHead false

# Download + verify source tarball
RUN echo "Fetching ${LIBNFS_TAG}" \
    && wget -q -O libnfs.tar.gz \
       https://github.com/sahlberg/libnfs/archive/refs/tags/${LIBNFS_TAG}.tar.gz \
    && echo "${LIBNFS_SHA256}  libnfs.tar.gz" | sha256sum -c - \
    && tar -xzf libnfs.tar.gz \
    && rm libnfs.tar.gz \
    && mv libnfs-${LIBNFS_TAG} libnfs

RUN mkdir -p /output
