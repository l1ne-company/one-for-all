#!/usr/bin/env bash
#
# Test build-verifier functionality
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEST_KEY="$SCRIPT_DIR/fixtures/test-key.key"

echo "Testing build-verifier..."

# Create a valid proof for testing
TEMP_PROOF=$(mktemp)
nix run "$REPO_ROOT#build-signer" -- \
    --commit "valid-commit-sha" \
    --flake-lock-hash "valid-flake-hash" \
    --artifact-tar-hash "valid-artifact-hash" \
    --build-command "nix build" \
    --private-key "$TEST_KEY" \
    --out "$TEMP_PROOF" >/dev/null 2>&1

# Test 1: Verifier shows help
echo -n "  [1/5] Verifier shows help message... "
if nix run "$REPO_ROOT#build-verifier" -- --help >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ Failed"
    rm -f "$TEMP_PROOF"
    exit 1
fi

# Test 2: Verifier accepts valid proof
echo -n "  [2/5] Verifier accepts valid proof... "
if nix run "$REPO_ROOT#build-verifier" -- \
    "$TEMP_PROOF" \
    --skip-commit-check \
    --skip-flake-lock-check >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ Failed to verify valid proof"
    rm -f "$TEMP_PROOF"
    exit 1
fi

# Test 3: Verifier rejects tampered payload
echo -n "  [3/5] Verifier rejects tampered payload... "
TAMPERED_PROOF=$(mktemp)
jq '.payload.commit = "tampered"' "$TEMP_PROOF" > "$TAMPERED_PROOF"

if nix run "$REPO_ROOT#build-verifier" -- \
    "$TAMPERED_PROOF" \
    --skip-commit-check \
    --skip-flake-lock-check >/dev/null 2>&1; then
    echo "✗ Accepted tampered proof!"
    rm -f "$TEMP_PROOF" "$TAMPERED_PROOF"
    exit 1
else
    echo "✓"
fi

# Test 4: Verifier rejects tampered signature
echo -n "  [4/5] Verifier rejects tampered signature... "
TAMPERED_SIG=$(mktemp)
jq '.signature = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"' "$TEMP_PROOF" > "$TAMPERED_SIG"

if nix run "$REPO_ROOT#build-verifier" -- \
    "$TAMPERED_SIG" \
    --skip-commit-check \
    --skip-flake-lock-check >/dev/null 2>&1; then
    echo "✗ Accepted tampered signature!"
    rm -f "$TEMP_PROOF" "$TAMPERED_PROOF" "$TAMPERED_SIG"
    exit 1
else
    echo "✓"
fi

# Test 5: Verifier checks commit SHA
echo -n "  [5/5] Verifier checks commit SHA... "
if nix run "$REPO_ROOT#build-verifier" -- \
    "$TEMP_PROOF" \
    --expected-commit "wrong-commit-sha" \
    --skip-flake-lock-check >/dev/null 2>&1; then
    echo "✗ Accepted wrong commit!"
    rm -f "$TEMP_PROOF" "$TAMPERED_PROOF" "$TAMPERED_SIG"
    exit 1
else
    echo "✓"
fi

rm -f "$TEMP_PROOF" "$TAMPERED_PROOF" "$TAMPERED_SIG"
echo "✅ All verifier tests passed"
