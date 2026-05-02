FROM libnfs-base AS windows-x64

LABEL maintainer="NoMercy Entertainment"
LABEL description="libnfs for Windows x86_64 (MinGW cross-compile)"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update >/dev/null 2>&1 \
    && apt-get install -y --no-install-recommends \
    mingw-w64 \
    mingw-w64-tools \
    mingw-w64-x86-64-dev \
    mingw-w64-common \
    >/dev/null 2>&1 \
    && apt-get autoremove -y >/dev/null 2>&1 \
    && apt-get clean -y >/dev/null 2>&1 \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PREFIX=/libnfs_build/win-x64
ENV ARCH=x86_64
ENV CROSS_PREFIX=${ARCH}-w64-mingw32-
ENV CC=${CROSS_PREFIX}gcc
ENV CXX=${CROSS_PREFIX}g++
ENV WINDRES=${CROSS_PREFIX}windres
ENV DLLTOOL=${CROSS_PREFIX}dlltool
ENV STRIP=${CROSS_PREFIX}strip
RUN mkdir -p ${PREFIX}

# CMake toolchain file for MinGW cross-compile
RUN cat > /build/toolchain-mingw-x86_64.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

RUN echo "Building libnfs for win-x64 (MinGW)" \
    && cd /build/libnfs \
    && cmake -B build \
       -DCMAKE_TOOLCHAIN_FILE=/build/toolchain-mingw-x86_64.cmake \
       -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_INSTALL_PREFIX=${PREFIX} \
       -DBUILD_SHARED_LIBS=ON \
       -DENABLE_TESTS=OFF \
       -DENABLE_EXAMPLES=OFF \
       -DENABLE_UTILS=OFF \
       -DENABLE_KERBEROS=OFF \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build

# Collect the DLL (may land in bin/ or lib/ depending on CMake config)
RUN DLL=$(find ${PREFIX} -name "libnfs*.dll" | head -1) \
    && [ -n "${DLL}" ] || (find /build/libnfs/build -name "*.dll" && false) \
    && DLL=$(find ${PREFIX} /build/libnfs/build -name "libnfs*.dll" | head -1) \
    && ${CROSS_PREFIX}strip --strip-unneeded "${DLL}" \
    && cp "${DLL}" /output/libnfs.dll \
    && echo "Build complete: $(du -sh /output/libnfs.dll)"

# Verify expected exports are present
RUN ${CROSS_PREFIX}objdump -p /output/libnfs.dll | grep "DLL Name\|nfs_init_context\|nfs_destroy_context\|nfs_mount\|nfs_opendir\|mount_getexports\|mount_free_export_list" || true \
    && ${CROSS_PREFIX}objdump -p /output/libnfs.dll | grep -c "nfs_init_context" \
    | xargs -I{} sh -c '[ "{}" -ge 1 ] || (echo "MISSING: nfs_init_context not exported" && exit 1)'

FROM scratch AS export-win-x64
COPY --from=windows-x64 /output/libnfs.dll /libnfs.dll
CMD []
