#!/usr/bin/env bash
#
# Generate Cargo.lock for the crypto workspace
# This is a helper for development - Nix will also generate it during build
#

set -euo pipefail

cd "$(dirname "$0")/../src/crypto"

echo "Generating Cargo.lock for crypto workspace..."

# Create a temporary minimal main.rs if needed to satisfy cargo
cargo generate-lockfile

echo "✓ Cargo.lock generated at src/crypto/Cargo.lock"
