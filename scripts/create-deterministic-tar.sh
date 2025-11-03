#!/usr/bin/env bash
#
# Create a deterministic tarball from a Nix build output
# Usage: create-deterministic-tar.sh <nix-store-path> <output-tar-path>
#

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <nix-store-path> <output-tar-path>"
    echo "Example: $0 /nix/store/abcd...-mypackage /tmp/artifact.tar"
    exit 1
fi

NIX_STORE_PATH="$1"
OUTPUT_TAR="$2"

if [ ! -e "$NIX_STORE_PATH" ]; then
    echo "Error: Path does not exist: $NIX_STORE_PATH"
    exit 1
fi

# Get the basename for the tar
BASENAME=$(basename "$NIX_STORE_PATH")
PARENT_DIR=$(dirname "$NIX_STORE_PATH")

echo "Creating deterministic tarball..."
echo "  Source: $NIX_STORE_PATH"
echo "  Output: $OUTPUT_TAR"

# Create deterministic tar with:
# - sorted file names
# - normalized timestamps
# - normalized ownership
cd "$PARENT_DIR"
tar --sort=name \
    --mtime='UTC 2020-01-01' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -cf "$OUTPUT_TAR" \
    "$BASENAME"

# Compute and display hash
HASH=$(sha256sum "$OUTPUT_TAR" | awk '{print $1}')
echo "✓ Tarball created: $OUTPUT_TAR"
echo "  SHA256: $HASH"
