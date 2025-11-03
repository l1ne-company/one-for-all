#!/usr/bin/env bash
#
# Sign a Nix build and generate proof.json
# Usage: sign-build.sh [options]
#

set -euo pipefail

# Default values
FLAKE_PATH="."
BUILD_COMMAND="nix build"
PRIVATE_KEY="${BUILD_SIGNER_KEY:-}"
OUTPUT_DIR="proofs"
BUILD_LOG=""

# Parse command line arguments
usage() {
    cat <<EOF
Usage: $0 [options]

Options:
    -f, --flake PATH         Path to flake directory (default: .)
    -c, --command CMD        Build command to run (default: "nix build")
    -k, --key PATH           Path to private key (or set BUILD_SIGNER_KEY env var)
    -o, --output-dir DIR     Output directory for proof (default: proofs/)
    -l, --log PATH           Save build log to this path
    -h, --help               Show this help message

Environment variables:
    BUILD_SIGNER_KEY         Path to private key (alternative to -k)

Example:
    $0 -k ~/.ssh/build-signer.key -c "nix build .#mypackage"
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--flake)
            FLAKE_PATH="$2"
            shift 2
            ;;
        -c|--command)
            BUILD_COMMAND="$2"
            shift 2
            ;;
        -k|--key)
            PRIVATE_KEY="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -l|--log)
            BUILD_LOG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: Private key not specified. Use -k/--key or set BUILD_SIGNER_KEY environment variable."
    exit 1
fi

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Private key not found: $PRIVATE_KEY"
    exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo "  Build Signing Workflow"
echo "═══════════════════════════════════════════════════════"
echo ""

cd "$FLAKE_PATH"

# Get commit SHA
COMMIT=$(git rev-parse HEAD)
echo "📝 Git commit: $COMMIT"

# Compute flake.lock hash
if [ ! -f "flake.lock" ]; then
    echo "Error: flake.lock not found in $FLAKE_PATH"
    exit 1
fi

FLAKE_LOCK_HASH=$(sha256sum flake.lock | awk '{print $1}')
echo "🔒 flake.lock hash: $FLAKE_LOCK_HASH"

# Run build
echo ""
echo "🔨 Running build: $BUILD_COMMAND"
if [ -n "$BUILD_LOG" ]; then
    $BUILD_COMMAND 2>&1 | tee "$BUILD_LOG"
    BUILD_LOG_HASH=$(sha256sum "$BUILD_LOG" | awk '{print $1}')
    echo "📋 Build log saved: $BUILD_LOG (hash: $BUILD_LOG_HASH)"
else
    $BUILD_COMMAND
    BUILD_LOG_HASH=""
fi

# Find the build result
if [ -L "result" ]; then
    BUILD_RESULT=$(readlink -f result)
    echo "✓ Build output: $BUILD_RESULT"
else
    echo "Error: No 'result' symlink found. Did the build succeed?"
    exit 1
fi

# Create deterministic tarball
TEMP_DIR=$(mktemp -d)
ARTIFACT_TAR="$TEMP_DIR/artifact.tar"

echo ""
echo "📦 Creating deterministic tarball..."
"$(dirname "$0")/create-deterministic-tar.sh" "$BUILD_RESULT" "$ARTIFACT_TAR"
ARTIFACT_HASH=$(sha256sum "$ARTIFACT_TAR" | awk '{print $1}')

# Get derivation hash (optional)
DRV_HASH=""
if command -v nix &> /dev/null; then
    # Try to get derivation path
    DRV_PATH=$(nix derivation show "$BUILD_RESULT" 2>/dev/null | jq -r 'keys[0]' || echo "")
    if [ -n "$DRV_PATH" ]; then
        DRV_HASH=$(basename "$DRV_PATH")
        echo "🔗 Derivation: $DRV_HASH"
    fi
fi

# Sign the build
mkdir -p "$OUTPUT_DIR"
PROOF_FILE="$OUTPUT_DIR/$COMMIT.json"

echo ""
echo "✍️  Signing build..."

BUILD_SIGNER_ARGS=(
    --commit "$COMMIT"
    --flake-lock-hash "$FLAKE_LOCK_HASH"
    --artifact-tar-hash "$ARTIFACT_HASH"
    --build-command "$BUILD_COMMAND"
    --private-key "$PRIVATE_KEY"
    --out "$PROOF_FILE"
)

if [ -n "$DRV_HASH" ]; then
    BUILD_SIGNER_ARGS+=(--drv-hash "$DRV_HASH")
fi

if [ -n "$BUILD_LOG_HASH" ]; then
    BUILD_SIGNER_ARGS+=(--build-log-hash "$BUILD_LOG_HASH")
fi

# Check if build-signer is in PATH
if ! command -v build-signer &> /dev/null; then
    echo "Error: build-signer not found in PATH"
    echo "Build it with: nix build .#build-signer"
    echo "Or use: nix run .#build-signer -- [args]"
    exit 1
fi

build-signer "${BUILD_SIGNER_ARGS[@]}"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ Build signed successfully!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Proof saved to: $PROOF_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the proof: cat $PROOF_FILE"
echo "  2. Add to git: git add $PROOF_FILE"
echo "  3. Commit: git commit -m 'Add build proof for $COMMIT'"
echo "  4. Push and create PR"
echo ""
