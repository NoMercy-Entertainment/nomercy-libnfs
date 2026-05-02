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

# windres only understands a small subset of options. By default CMake leaks
# C compiler flags (-Wall, -Wextra) into the RC compiler invocation which
# windres rejects with "invalid option -- 'W'". Override the RC compile
# command to pass only the bits windres actually accepts.
set(CMAKE_RC_FLAGS "")
set(CMAKE_RC_COMPILE_OBJECT "<CMAKE_RC_COMPILER> -O coff -i <SOURCE> -o <OBJECT>")
EOF

# Disable libnfs's pthread paths globally for the Windows cross-compile.
# MinGW's winpthreads makes libnfs's autoconf flag HAVE_PTHREAD even when
# targeting Windows, which causes:
#   - Header: both pthread and WIN32 typedef branches activate, typedef collisions
#   - Source: #include <sys/syscall.h> (POSIX-only) inside the pthread branch
# Rewriting the guard to a never-defined sentinel kills every pthread path
# surgically; the WIN32 branch handles all threading for the Windows build.
RUN find /build/libnfs -type f \( -name "*.h" -o -name "*.c" \) \
        -exec sed -i 's/\bHAVE_PTHREAD\b/HAVE_PTHREAD_DISABLED_FOR_MINGW_BUILD/g' {} + \
    && echo "Patched files mentioning HAVE_PTHREAD:" \
    && grep -rln "HAVE_PTHREAD_DISABLED_FOR_MINGW_BUILD" /build/libnfs | head -20

# Skip the version.rc resource step. CMake's RC compile invocation under
# MinGW cross-compile leaks gcc-style warning flags (-Wall) to windres,
# which rejects them. The .rc file is metadata-only; the DLL is functional
# without it. The .def file (libnfs-win32.def) stays in SOURCES — it's
# needed for the proper DLL export table.
RUN sed -i '/configure_file.*version\.rc\.template/d' /build/libnfs/lib/CMakeLists.txt \
    && sed -i 's|\${CMAKE_CURRENT_BINARY_DIR}/version\.rc ||g' /build/libnfs/lib/CMakeLists.txt \
    && grep -A 2 -B 1 "version.rc\|win32.def" /build/libnfs/lib/CMakeLists.txt

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
