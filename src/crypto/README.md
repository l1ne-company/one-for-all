# Build Verification System

Cryptographic signing and verification system for Nix build artifacts. Provides trustworthy attestation that builds were executed by authorized developers without rerunning expensive computations in CI.

## Architecture

- **build-signer**: Signs build artifacts with Ed25519 signatures
- **build-verifier**: Verifies signatures and metadata in CI
- No VM, no heavy ZK tooling, no rebuild required

## Setup

### 1. Generate Cargo.lock

The Rust workspace needs a Cargo.lock file before Nix can build it:

```bash
cd src/crypto
cargo generate-lockfile
# Or use the helper script:
../../scripts/generate-cargo-lock.sh
```

### 2. Build the tools

```bash
nix build .#build-signer
nix build .#build-verifier
```

### 3. Generate a keypair

```bash
./scripts/generate-keypair.sh my-name
```

This creates `my-name.key` (private, keep secure) and instructions for extracting the public key.

### 4. Sign a build

```bash
./scripts/sign-build.sh \
  -k my-name.key \
  -c "nix build .#mypackage"
```

This will:
- Run the build
- Create a deterministic tarball
- Compute hashes (commit, flake.lock, artifact)
- Sign everything with your private key
- Generate `proofs/<commit>.json`

### 5. Commit and push

```bash
git add proofs/<commit>.json
git commit -m "Add build proof"
git push
```

### 6. CI Verification

The GitHub Actions workflow (`.github/workflows/verify-build-proof.yml`) will:
- Build the verifier
- Check for `proofs/<commit>.json`
- Verify signature
- Validate commit SHA and flake.lock hash match

## Proof Format

```json
{
  "payload": {
    "commit": "abc123...",
    "flake_lock_hash": "def456...",
    "artifact_tar_hash": "789ghi...",
    "build_command": "nix build .#package",
    "timestamp": "2025-11-03T12:34:56Z",
    "nonce": "randomhex..."
  },
  "signature": "ed25519signaturehex...",
  "public_key": "ed25519pubkeyhex...",
  "format_version": 1
}
```

## Security Model

### What this proves:
- An entity with the private key ran a build
- The build produced an artifact with hash H
- The build was tied to commit C and flake.lock L
- The signature is authentic

### What this does NOT prove:
- That the builder followed security policies
- That the build environment was clean
- That the private key wasn't compromised
- Reproducibility (though deterministic tarballs help)

### Key Management:
- **Never** commit private keys
- Store private keys in encrypted storage (LUKS, hardware token, etc.)
- For multi-developer teams, maintain `prover_keys/trusted.txt` with authorized public keys
- Consider key rotation policies

## Workflow

### Developer (Local):
1. Make changes, commit
2. Run `nix flake check` and `nix build`
3. Run `./scripts/sign-build.sh -k ~/.keys/build-signer.key`
4. Commit the proof, push, open PR

### CI (GitHub Actions):
1. Checkout PR
2. Build verifier
3. Verify proof signature
4. Check commit SHA matches
5. Check flake.lock hash matches
6. ✅ or ❌

## Advanced Usage

### Trusted Keys List

Create `prover_keys/trusted.txt` to enforce a whitelist in CI:

```
# One public key per line (hex encoded, 64 chars)
a1b2c3d4e5f6...  # Alice
f6e5d4c3b2a1...  # Bob
```

The verifier will reject proofs from unknown keys.

### Multiple Artifacts

To sign multiple build outputs:

```bash
for pkg in package1 package2 package3; do
  ./scripts/sign-build.sh -k my.key -c "nix build .#$pkg"
done
```

### Custom Build Commands

```bash
./scripts/sign-build.sh \
  -k my.key \
  -c "nix build --system aarch64-linux .#cross-compile"
```

## Troubleshooting

### "Cargo.lock not found"

Generate it:
```bash
cd src/crypto && cargo generate-lockfile
```

### "Public key not in trusted keys list"

Add your public key to `prover_keys/trusted.txt`:
```bash
jq -r '.public_key' proofs/<commit>.json >> prover_keys/trusted.txt
```

### "flake.lock hash mismatch"

The flake.lock in your PR differs from what was signed. Either:
- Update the lock and re-sign
- Ensure you committed the correct flake.lock

## Future Enhancements

- [ ] Merkle trees for multi-file artifacts
- [ ] Build log inclusion proofs
- [ ] Hardware security module support
- [ ] Time-stamping service integration
- [ ] Automated key rotation
- [ ] Zero-knowledge proofs for private builds (if needed)

## References

- Ed25519: https://ed25519.cr.yp.to/
- Deterministic builds: https://reproducible-builds.org/
- Nix reproducibility: https://nixos.org/manual/nix/stable/
