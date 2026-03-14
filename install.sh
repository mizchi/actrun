#!/usr/bin/env sh
set -e

REPO="mizchi/actrun"
BIN_NAME="actrun"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${VERSION:-${1:-}}"

# Get latest version from GitHub API if not specified
if [ -z "$VERSION" ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
    awk -F '"' '/"tag_name"/ {print $4; exit}')
fi

if [ -z "$VERSION" ]; then
  echo "failed to detect latest version" >&2
  exit 1
fi

# Platform detection
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *)
    echo "unsupported OS: $OS" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="x64" ;;
  *)
    echo "unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac

ASSET="${BIN_NAME}-${OS}-${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"

echo "Downloading ${BIN_NAME} ${VERSION} (${OS}-${ARCH})..."

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

curl -fsSL "$URL" -o "$TMPDIR/$ASSET"
tar -C "$TMPDIR" -xzf "$TMPDIR/$ASSET"

mkdir -p "$INSTALL_DIR"
if command -v install >/dev/null 2>&1; then
  install -m 755 "$TMPDIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
else
  cp "$TMPDIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
  chmod +x "$INSTALL_DIR/$BIN_NAME"
fi

echo "${BIN_NAME} ${VERSION} installed to ${INSTALL_DIR}/${BIN_NAME}"
