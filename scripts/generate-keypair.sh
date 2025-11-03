#!/usr/bin/env bash
#
# Generate an Ed25519 keypair for build signing
# Usage: generate-keypair.sh <key-name>
#

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <key-name>"
    echo "Example: $0 developer-name"
    exit 1
fi

KEY_NAME="$1"
PRIVATE_KEY="$KEY_NAME.key"
PUBLIC_KEY="$KEY_NAME.pub"

# Check if openssl or ssh-keygen is available
if command -v openssl &> /dev/null; then
    echo "Generating Ed25519 keypair using OpenSSL..."

    # Generate private key (32 bytes of randomness)
    openssl rand -out "$PRIVATE_KEY" 32

    echo "✓ Private key saved to: $PRIVATE_KEY"
    echo "⚠️  Keep this file secure and never commit it!"
    chmod 600 "$PRIVATE_KEY"

    echo ""
    echo "To get the public key, use build-signer or manually derive it."
    echo "The public key will be automatically included in proof.json when signing."

elif command -v ssh-keygen &> /dev/null; then
    echo "Generating Ed25519 keypair using ssh-keygen..."

    # Generate keypair
    ssh-keygen -t ed25519 -f "$KEY_NAME" -N "" -C "build-signer-$KEY_NAME"

    # Convert to raw format (note: ssh-keygen creates different format)
    echo "⚠️  Note: ssh-keygen format requires conversion for use with build-signer"
    echo "   Private key: $KEY_NAME"
    echo "   Public key: $KEY_NAME.pub"
    echo ""
    echo "To extract the raw 32-byte private key, you may need to use additional tools."
    echo "For simplicity, use the OpenSSL method or generate keys programmatically."

else
    echo "Error: Neither openssl nor ssh-keygen found."
    echo "Please install openssl: apt-get install openssl (Debian/Ubuntu)"
    echo "                     or: brew install openssl (macOS)"
    exit 1
fi

echo ""
echo "Next steps:"
echo "1. Keep $PRIVATE_KEY secure (chmod 600, encrypted storage)"
echo "2. Never commit the private key to git"
echo "3. Use build-signer with --private-key $PRIVATE_KEY"
echo "4. The public key will be embedded in proof.json automatically"
