FROM libnfs-base AS linux-x64

LABEL maintainer="NoMercy Entertainment"
LABEL description="libnfs for Linux x86_64"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update >/dev/null 2>&1 \
    && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    >/dev/null 2>&1 \
    && apt-get autoremove -y >/dev/null 2>&1 \
    && apt-get clean -y >/dev/null 2>&1 \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PREFIX=/libnfs_build/linux-x64
RUN mkdir -p ${PREFIX}

RUN echo "Building libnfs for linux-x64" \
    && cd /build/libnfs \
    && cmake -B build \
       -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_INSTALL_PREFIX=${PREFIX} \
       -DBUILD_SHARED_LIBS=ON \
       -DENABLE_TESTS=OFF \
       -DENABLE_EXAMPLES=OFF \
       -DENABLE_UTILS=OFF \
       -DENABLE_KERBEROS=OFF \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build

# Strip and normalize to bare soname
RUN SOFILE=$(find ${PREFIX}/lib -name "libnfs.so.*" | head -1) \
    && strip --strip-unneeded "${SOFILE}" \
    && cp "${SOFILE}" /output/libnfs.so \
    && echo "Build complete: $(du -sh /output/libnfs.so)"

FROM scratch AS export-linux-x64
COPY --from=linux-x64 /output/libnfs.so /libnfs.so
CMD []
