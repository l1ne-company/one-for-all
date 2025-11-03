# Trusted Prover Public Keys

This directory contains public keys trusted for signing build proofs.

## Format

Public keys should be stored as hex-encoded Ed25519 public keys (64 hex characters = 32 bytes).

## Trusted Keys List

If you want to enforce a list of trusted keys in CI, create a `trusted.txt` file here with one public key per line:

```
# trusted.txt format (lines starting with # are comments)
a1b2c3d4e5f6...  # Developer 1
f6e5d4c3b2a1...  # Developer 2
```

## Adding Your Public Key

When you generate a keypair using `scripts/generate-keypair.sh`, your public key will be automatically included in any `proof.json` you generate. To add it to the trusted list:

1. Sign a build with your private key
2. Extract the public key from the generated `proof.json`:
   ```bash
   jq -r '.public_key' proofs/yourcommit.json
   ```
3. Add it to `trusted.txt` (optional, for CI enforcement)

## Security

- **Never commit private keys** - only public keys belong in this directory
- Public keys are safe to share and commit to the repository
- The verifier uses these keys to validate signatures on build proofs
