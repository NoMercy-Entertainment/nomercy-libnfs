FROM libnfs-base AS darwin-x64

LABEL maintainer="NoMercy Entertainment"
LABEL description="libnfs for macOS x86_64 (osxcross cross-compile)"

# osxcross cross-compile — mirrors the ffmpeg-darwin-x86_64.dockerfile approach.
# Requires macOS SDK tarball at /build/osxcross/tarballs/MacOSX15.1.sdk.tar.xz
# (Apple allows redistribution of SDK headers for development purposes under Xcode license).
# Set build arg SDK_TARBALL_URL to a pre-staged URL or bake the tarball into
# a private base image. Without it, this stage will fail at the SDK step.
ARG SDK_TARBALL_URL=""

ENV DEBIAN_FRONTEND=noninteractive
ENV MACOSX_DEPLOYMENT_TARGET=10.13
ENV SDK_VERSION=15.1
ENV TARGET_ARCH=x86_64

RUN apt-get update >/dev/null 2>&1 \
    && apt-get install -y --no-install-recommends \
    clang \
    patch \
    liblzma-dev \
    libxml2-dev \
    xz-utils \
    bzip2 \
    cpio \
    zlib1g-dev \
    libssl-dev \
    python3 \
    libplist-utils \
    uuid-dev \
    >/dev/null 2>&1 \
    && apt-get autoremove -y >/dev/null 2>&1 \
    && apt-get clean -y >/dev/null 2>&1 \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN git clone --depth=1 https://github.com/tpoechtrager/osxcross.git /build/osxcross >/dev/null 2>&1

# If SDK_TARBALL_URL is provided, fetch the SDK tarball. Otherwise the build will
# fail here with a clear message — set SDK_TARBALL_URL or place the tarball manually.
RUN if [ -n "${SDK_TARBALL_URL}" ]; then \
        wget -q -O /build/osxcross/tarballs/MacOSX${SDK_VERSION}.sdk.tar.xz "${SDK_TARBALL_URL}"; \
    else \
        echo "ERROR: SDK_TARBALL_URL not set. Provide --build-arg SDK_TARBALL_URL=<url>" \
             "or pre-stage MacOSX${SDK_VERSION}.sdk.tar.xz in osxcross/tarballs/" && exit 1; \
    fi

RUN cd /build/osxcross \
    && UNATTENDED=1 SDK_VERSION=${SDK_VERSION} MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
       bash build.sh >/dev/null 2>&1

ENV PATH="/build/osxcross/target/bin:${PATH}"
ENV PREFIX=/libnfs_build/osx-x64
ENV CC=x86_64-apple-darwin24.1-clang
ENV CXX=x86_64-apple-darwin24.1-clang++
RUN mkdir -p ${PREFIX}

RUN cat > /build/toolchain-osx-x86_64.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER x86_64-apple-darwin24.1-clang)
set(CMAKE_CXX_COMPILER x86_64-apple-darwin24.1-clang++)
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.13)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

RUN echo "Building libnfs for osx-x64 (osxcross)" \
    && cd /build/libnfs \
    && cmake -B build \
       -DCMAKE_TOOLCHAIN_FILE=/build/toolchain-osx-x86_64.cmake \
       -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_INSTALL_PREFIX=${PREFIX} \
       -DBUILD_SHARED_LIBS=ON \
       -DENABLE_TESTS=OFF \
       -DENABLE_EXAMPLES=OFF \
       -DENABLE_UTILS=OFF \
       -DENABLE_KERBEROS=OFF \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build

RUN DYLIB=$(find ${PREFIX}/lib -name "libnfs*.dylib" | head -1) \
    && cp "${DYLIB}" /output/libnfs.dylib \
    && echo "Build complete: $(du -sh /output/libnfs.dylib)"

FROM scratch AS export-osx-x64
COPY --from=darwin-x64 /output/libnfs.dylib /libnfs.dylib
CMD []
