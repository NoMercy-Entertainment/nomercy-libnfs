# nomercy-libnfs

Pre-built [libnfs](https://github.com/sahlberg/libnfs) native binaries for all platforms
supported by NoMercy Media Server.

**Version:** libnfs-6.0.2
**License:** LGPL-2.1 (see [LICENSE](LICENSE))

## Purpose

`NoMercy.Storage` has a P/Invoke binding (`LibNfs.cs`) that loads the native `libnfs`
shared library. The .NET runtime resolves it via the `runtimes/<rid>/native/` layout
wired in `NoMercy.Storage.csproj`.

## Binaries

Pre-built binaries live in `output/` and are committed to the repo so consumers
don't need Docker. SHA256 checksums are in `output/CHECKSUMS.txt`.

| RID | File |
|-----|------|
| win-x64 | output/win-x64/libnfs.dll |
| linux-x64 | output/linux-x64/libnfs.so |
| linux-arm64 | output/linux-arm64/libnfs.so |
| osx-x64 | output/osx-x64/libnfs.dylib |
| osx-arm64 | output/osx-arm64/libnfs.dylib |

## Rebuilding

```bash
# All platforms
bash packages/nomercy-libnfs/scripts/build.sh

# Single platform
bash packages/nomercy-libnfs/scripts/build.sh win-x64

# Verify checksums + symbols
bash packages/nomercy-libnfs/scripts/verify.sh
```

macOS builds require a macOS SDK tarball (osxcross). Pass `--build-arg SDK_TARBALL_URL=<url>`
or pre-stage `MacOSX15.1.sdk.tar.xz` in the osxcross tarballs dir.
See `libnfs-darwin-*.dockerfile` for details.

## CMake flags

All builds use:
- `BUILD_SHARED_LIBS=ON` — shared library only
- `ENABLE_KERBEROS=OFF` — AUTH_UNIX only, no krb5 dependency
- `ENABLE_TESTS=OFF`, `ENABLE_EXAMPLES=OFF`, `ENABLE_UTILS=OFF` — binary only
