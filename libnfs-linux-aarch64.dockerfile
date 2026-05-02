FROM libnfs-base AS linux-arm64

LABEL maintainer="NoMercy Entertainment"
LABEL description="libnfs for Linux aarch64 (cross-compile from x86_64)"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update >/dev/null 2>&1 \
    && apt-get install -y --no-install-recommends \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    >/dev/null 2>&1 \
    && apt-get autoremove -y >/dev/null 2>&1 \
    && apt-get clean -y >/dev/null 2>&1 \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PREFIX=/libnfs_build/linux-arm64
ENV ARCH=aarch64
ENV CROSS_PREFIX=${ARCH}-linux-gnu-
ENV CC=${CROSS_PREFIX}gcc
ENV CXX=${CROSS_PREFIX}g++
ENV STRIP=${CROSS_PREFIX}strip
RUN mkdir -p ${PREFIX}

# CMake toolchain file for aarch64 cross-compile
RUN echo "[cmake toolchain]" \
    && cat > /build/toolchain-aarch64.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

RUN echo "Building libnfs for linux-arm64 (cross)" \
    && cd /build/libnfs \
    && cmake -B build \
       -DCMAKE_TOOLCHAIN_FILE=/build/toolchain-aarch64.cmake \
       -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_INSTALL_PREFIX=${PREFIX} \
       -DBUILD_SHARED_LIBS=ON \
       -DENABLE_TESTS=OFF \
       -DENABLE_EXAMPLES=OFF \
       -DENABLE_UTILS=OFF \
       -DENABLE_KERBEROS=OFF \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build

RUN SOFILE=$(find ${PREFIX}/lib -name "libnfs.so.*" | head -1) \
    && ${CROSS_PREFIX}strip --strip-unneeded "${SOFILE}" \
    && cp "${SOFILE}" /output/libnfs.so \
    && echo "Build complete: $(du -sh /output/libnfs.so)"

FROM scratch AS export-linux-arm64
COPY --from=linux-arm64 /output/libnfs.so /libnfs.so
CMD []
