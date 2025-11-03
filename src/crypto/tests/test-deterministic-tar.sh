#!/usr/bin/env bash
#
# Test deterministic tar creation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "Testing deterministic tar creation..."

# Create a test directory structure
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/test-package/bin"
echo "#!/bin/sh" > "$TEST_DIR/test-package/bin/test"
echo 'echo "test"' >> "$TEST_DIR/test-package/bin/test"
chmod +x "$TEST_DIR/test-package/bin/test"

# Test 1: Script shows usage
echo -n "  [1/3] Script shows usage message... "
OUTPUT=$("$REPO_ROOT/scripts/create-deterministic-tar.sh" 2>&1 || true)
if echo "$OUTPUT" | grep -q "Usage"; then
    echo "✓"
else
    echo "✗ Failed"
    echo "Output was: $OUTPUT"
    rm -rf "$TEST_DIR"
    exit 1
fi

# Test 2: Creates tarball successfully
echo -n "  [2/3] Creates tarball successfully... "
TAR1="$TEST_DIR/tar1.tar"
if "$REPO_ROOT/scripts/create-deterministic-tar.sh" \
    "$TEST_DIR/test-package" \
    "$TAR1" >/dev/null 2>&1; then
    if [ -f "$TAR1" ]; then
        echo "✓"
    else
        echo "✗ Tarball not created"
        rm -rf "$TEST_DIR"
        exit 1
    fi
else
    echo "✗ Script failed"
    rm -rf "$TEST_DIR"
    exit 1
fi

# Test 3: Produces deterministic output
echo -n "  [3/3] Produces deterministic output... "
sleep 1  # Ensure different timestamp if not deterministic
TAR2="$TEST_DIR/tar2.tar"
"$REPO_ROOT/scripts/create-deterministic-tar.sh" \
    "$TEST_DIR/test-package" \
    "$TAR2" >/dev/null 2>&1

HASH1=$(sha256sum "$TAR1" | awk '{print $1}')
HASH2=$(sha256sum "$TAR2" | awk '{print $1}')

if [ "$HASH1" = "$HASH2" ]; then
    echo "✓"
else
    echo "✗ Hashes differ: $HASH1 != $HASH2"
    rm -rf "$TEST_DIR"
    exit 1
fi

rm -rf "$TEST_DIR"
echo "✅ All deterministic tar tests passed"
