#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build .deb package for genectl from a release binary
#
# Env:
#   TAG      version tag to package (default: current git tag or HEAD)
#   ARCH     override architecture (default: host architecture)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/../.." && pwd)"

# Determine architecture
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  x86_64)  DEB_ARCH=amd64 ;;
  aarch64) DEB_ARCH=arm64 ;;
  arm64)   DEB_ARCH=arm64 ;;
  *) echo "unsupported architecture: $ARCH"; exit 1 ;;
esac

# Determine version
if [ -z "${TAG:-}" ]; then
  TAG="$(cd "$PROJECT_ROOT" && git describe --tags --always 2>/dev/null || echo "0.0.0")"
fi
VERSION="${TAG#v}"

echo "==> Building .deb for genectl ${VERSION} (${DEB_ARCH})"

# Build the binary first
echo "==> Building binary..."
(cd "$PROJECT_ROOT" && swift build -c release)

WORK="$HERE/build"
mkdir -p "$WORK"

PKG="genectl"
stage="$WORK/${PKG}_${VERSION}_${DEB_ARCH}"
rm -rf "$stage"
mkdir -p "$stage/DEBIAN" "$stage/usr/bin"

# Copy binary
cp "$PROJECT_ROOT/.build/release/genectl" "$stage/usr/bin/genectl"
chmod 0755 "$stage/usr/bin/genectl"

# Generate control file
sed -e "s/@VERSION@/${VERSION}/" -e "s/@ARCH@/${DEB_ARCH}/" \
    "$HERE/packages/$PKG/control" > "$stage/DEBIAN/control"

# Install license documentation
install -D -m 0644 "$HERE/LICENSE" "$stage/usr/share/doc/$PKG/copyright"

# Build package
dpkg-deb --build --root-owner-group "$stage" "$WORK/${PKG}_${VERSION}_${DEB_ARCH}.deb"
rm -rf "$stage"

echo "==> Package:"
ls -lh "$WORK"/*.deb
