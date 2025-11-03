#!/usr/bin/env bash
#
# End-to-end test: Full signing and verification workflow
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEST_KEY="$SCRIPT_DIR/fixtures/test-key.key"

echo "Testing end-to-end workflow..."

# Setup test environment
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# Create a simple project
cat > hello.txt <<EOF
Hello, World!
EOF
git add hello.txt
git commit -q -m "Initial commit"

COMMIT=$(git rev-parse HEAD)

# Create fake flake.lock
echo '{"nodes": {}}' > flake.lock
FLAKE_HASH=$(sha256sum flake.lock | awk '{print $1}')

# Create fake build output
mkdir -p build/bin
echo "#!/bin/sh" > build/bin/app
echo 'echo "Hello from app"' >> build/bin/app
chmod +x build/bin/app

# Test 1: Create deterministic tar
echo -n "  [1/5] Create deterministic tar... "
"$REPO_ROOT/scripts/create-deterministic-tar.sh" \
    build \
    artifact.tar >/dev/null 2>&1

if [ -f artifact.tar ]; then
    echo "✓"
else
    echo "✗ Failed"
    cd - >/dev/null
    rm -rf "$TEST_DIR"
    exit 1
fi

ARTIFACT_HASH=$(sha256sum artifact.tar | awk '{print $1}')

# Test 2: Sign the build
echo -n "  [2/5] Sign the build... "
mkdir -p proofs
if nix run "$REPO_ROOT#build-signer" -- \
    --commit "$COMMIT" \
    --flake-lock-hash "$FLAKE_HASH" \
    --artifact-tar-hash "$ARTIFACT_HASH" \
    --build-command "test build" \
    --private-key "$TEST_KEY" \
    --out "proofs/$COMMIT.json" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ Failed"
    cd - >/dev/null
    rm -rf "$TEST_DIR"
    exit 1
fi

# Test 3: Verify the proof
echo -n "  [3/5] Verify the proof... "
if nix run "$REPO_ROOT#build-verifier" -- \
    "proofs/$COMMIT.json" \
    --expected-commit "$COMMIT" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ Failed"
    cd - >/dev/null
    rm -rf "$TEST_DIR"
    exit 1
fi

# Test 4: Verification fails with wrong commit
echo -n "  [4/5] Verification fails with wrong commit... "
if nix run "$REPO_ROOT#build-verifier" -- \
    "proofs/$COMMIT.json" \
    --expected-commit "wrong-commit-sha" \
    --skip-flake-lock-check >/dev/null 2>&1; then
    echo "✗ Accepted wrong commit!"
    cd - >/dev/null
    rm -rf "$TEST_DIR"
    exit 1
else
    echo "✓"
fi

# Test 5: Verification fails with wrong flake.lock
echo -n "  [5/5] Verification fails with wrong flake.lock... "
echo '{"nodes": {"modified": true}}' > flake.lock
if nix run "$REPO_ROOT#build-verifier" -- \
    "proofs/$COMMIT.json" \
    --expected-commit "$COMMIT" >/dev/null 2>&1; then
    echo "✗ Accepted wrong flake.lock!"
    cd - >/dev/null
    rm -rf "$TEST_DIR"
    exit 1
else
    echo "✓"
fi

cd - >/dev/null
rm -rf "$TEST_DIR"
echo "✅ All end-to-end tests passed"
