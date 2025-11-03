#!/usr/bin/env bash
#
# Test build-signer functionality
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEST_KEY="$SCRIPT_DIR/fixtures/test-key.key"

echo "Testing build-signer..."

# Test 1: Signer shows help
echo -n "  [1/4] Signer shows help message... "
if nix run "$REPO_ROOT#build-signer" -- --help >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ Failed"
    exit 1
fi

# Test 2: Signer creates valid proof
echo -n "  [2/4] Signer creates valid proof... "
TEMP_PROOF=$(mktemp)
if nix run "$REPO_ROOT#build-signer" -- \
    --commit "test-commit-sha" \
    --flake-lock-hash "test-flake-hash" \
    --artifact-tar-hash "test-artifact-hash" \
    --build-command "test build" \
    --private-key "$TEST_KEY" \
    --out "$TEMP_PROOF" >/dev/null 2>&1; then

    if [ -f "$TEMP_PROOF" ] && [ -s "$TEMP_PROOF" ]; then
        echo "✓"
    else
        echo "✗ Proof file not created"
        rm -f "$TEMP_PROOF"
        exit 1
    fi
else
    echo "✗ Signer failed"
    rm -f "$TEMP_PROOF"
    exit 1
fi

# Test 3: Proof has valid JSON structure
echo -n "  [3/4] Proof has valid JSON structure... "
if jq -e '.payload.commit' "$TEMP_PROOF" >/dev/null 2>&1 && \
   jq -e '.signature' "$TEMP_PROOF" >/dev/null 2>&1 && \
   jq -e '.public_key' "$TEMP_PROOF" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ Invalid JSON structure"
    rm -f "$TEMP_PROOF"
    exit 1
fi

# Test 4: Proof contains expected values
echo -n "  [4/4] Proof contains expected values... "
COMMIT=$(jq -r '.payload.commit' "$TEMP_PROOF")
if [ "$COMMIT" = "test-commit-sha" ]; then
    echo "✓"
    rm -f "$TEMP_PROOF"
else
    echo "✗ Commit mismatch: got $COMMIT"
    rm -f "$TEMP_PROOF"
    exit 1
fi

echo "✅ All signer tests passed"
