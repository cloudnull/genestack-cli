#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build RPM for genectl from a release binary
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
  x86_64)  RPM_ARCH=x86_64 ;;
  aarch64) RPM_ARCH=aarch64 ;;
  arm64)   RPM_ARCH=aarch64 ;;
  *) echo "unsupported architecture: $ARCH"; exit 1 ;;
esac

# Determine version
if [ -z "${TAG:-}" ]; then
  TAG="$(cd "$PROJECT_ROOT" && git describe --tags --always 2>/dev/null || echo "0.0.0")"
fi
VERSION="${TAG#v}"

echo "==> Building RPM for genectl ${VERSION} (${RPM_ARCH})"

# Build the binary first
echo "==> Building binary..."
(cd "$PROJECT_ROOT" && swift build -c release)

WORK="$HERE/build"
SOURCES="$WORK/SOURCES"
mkdir -p "$SOURCES"

# Copy binary and license
cp "$PROJECT_ROOT/.build/release/genectl" "$SOURCES/genectl"
chmod 0755 "$SOURCES/genectl"
cp "$HERE/../LICENSE" "$SOURCES/LICENSE"

# Build RPM
echo "==> Building RPM..."
rpmbuild -bb "$HERE/SPECS/genectl.spec" \
  --define "pkgver $VERSION" \
  --define "_topdir $WORK" \
  --define "_sourcedir $SOURCES" \
  --define "dist .el9"

echo "==> Packages:"
find "$WORK/RPMS" -name '*.rpm' -exec ls -lh {} \;
