# Build Verification Examples

This guide shows how to use the build verification system with different one-for-all templates.

## Overview

The build verification system provides cryptographic proof that builds were executed by authorized developers without rerunning expensive computations in CI.

**Key Benefits:**
- ✅ No rebuild in CI - just signature verification
- ✅ Minimal cost - only hash checks + Ed25519 verification
- ✅ Deterministic artifacts - reproducible build outputs
- ✅ Metadata binding - ties signatures to commit SHA & flake.lock

## Prerequisites

```bash
# 1. Generate your keypair (one-time setup)
./scripts/generate-keypair.sh your-name
# This creates: your-name.key (keep secret!)

# 2. Ensure build tools are available
nix build .#build-signer
nix build .#build-verifier
```

## Example 1: Quick Start Simple

The simplest template for building a basic Rust project.

### Create Project

```bash
# Initialize from template
mkdir my-project && cd my-project
nix flake init -t github:l1ne-company/one-for-all#quick-start-simple

# Initialize git
git init
git add .
git commit -m "Initial commit"
```

### Build and Sign

```bash
# Build the project
nix build

# The build produces: result/bin/quick-start-simple
./result/bin/quick-start-simple
# Output: Hello, world!

# Create deterministic tarball
~/path/to/one-for-all/scripts/create-deterministic-tar.sh \\
  $(readlink -f result) \\
  /tmp/artifact.tar

# Get metadata
COMMIT=$(git rev-parse HEAD)
FLAKE_HASH=$(sha256sum flake.lock | awk '{print $1}')
ARTIFACT_HASH=$(sha256sum /tmp/artifact.tar | awk '{print $1}')

# Sign the build
mkdir -p proofs
nix run github:l1ne-company/one-for-all#build-signer -- \\
  --commit "$COMMIT" \\
  --flake-lock-hash "$FLAKE_HASH" \\
  --artifact-tar-hash "$ARTIFACT_HASH" \\
  --build-command "nix build" \\
  --private-key ~/your-name.key \\
  --out "proofs/$COMMIT.json"
```

### Verify Proof

```bash
# Verify the signed proof
nix run github:l1ne-company/one-for-all#build-verifier -- \\
  proofs/$COMMIT.json \\
  --expected-commit "$COMMIT"

# Output:
# 📋 Verifying build proof...
# 🔐 Verifying signature... ✓
# 📝 Verifying commit SHA... ✓
# 🔒 Verifying flake.lock hash... ✓
# ✅ Verification successful!
```

### Example Proof File

```json
{
  "payload": {
    "commit": "edd9986988b23c9355be2ba6482f36b0a26868d2",
    "flake_lock_hash": "1fb14460652960652a2a75357d20414aef4d34eb81130f3089d08441943d292f",
    "build_command": "nix build",
    "artifact_tar_hash": "aeb6d321fa6325e2d511ea62765734e584e22fdf857b4b1f5d2ccfddb5d2f2e9",
    "timestamp": "2025-11-21T14:32:00Z",
    "nonce": "fc8b210450fb3c3d15a7b0c8bd7aaf66"
  },
  "signature": "a2f55b2115fe86c44e3970b0d982fef229e043dce18e6ee4e531c4a9b59e5f7033528fd85503b66c291829756087843001079b58313f7f0e333f7af29c5d4f09",
  "public_key": "f0f65bae20a3256c55f5669c4f8ac97aaac9072c4c79c95188f40320b6ab7d33",
  "format_version": 1
}
```

## Example 2: Cross-Compilation (musl)

Building static binaries with musl for maximum portability.

### Create Project

```bash
mkdir my-static-binary && cd my-static-binary
nix flake init -t github:l1ne-company/one-for-all#cross-musl

git init && git add . && git commit -m "Init cross-musl project"
```

### Build for musl

```bash
# Build static binary
nix build

# Verify it's static
file result/bin/cross-musl
# Output: ELF 64-bit LSB executable, x86-64, statically linked

# Run it
./result/bin/cross-musl
# Output: hello world
```

### Sign Cross-Compiled Build

```bash
# Same signing workflow as Example 1
~/path/to/one-for-all/scripts/create-deterministic-tar.sh \\
  $(readlink -f result) \\
  /tmp/artifact-musl.tar

# Sign with metadata
nix run github:l1ne-company/one-for-all#build-signer -- \\
  --commit "$(git rev-parse HEAD)" \\
  --flake-lock-hash "$(sha256sum flake.lock | awk '{print $1}')" \\
  --artifact-tar-hash "$(sha256sum /tmp/artifact-musl.tar | awk '{print $1}')" \\
  --build-command "nix build (musl cross-compile)" \\
  --private-key ~/your-name.key \\
  --out "proofs/$(git rev-parse HEAD).json"
```

## Example 3: Workspace Projects

Building Rust workspaces with multiple crates.

### Create Project

```bash
mkdir my-workspace && cd my-workspace
nix flake init -t github:l1ne-company/one-for-all#quick-start-workspace

git init && git add . && git commit -m "Init workspace"
```

### Build Workspace

```bash
# Build all workspace members
nix build

# The workspace contains multiple crates
ls crates/
# Output: my-cli  my-common  my-server  my-workspace-hack
```

### Sign Workspace Build

```bash
# For workspaces, you can sign the entire workspace or individual members

# Option A: Sign entire workspace
nix build
~/path/to/one-for-all/scripts/create-deterministic-tar.sh \\
  $(readlink -f result) \\
  /tmp/workspace.tar

# Sign as usual
nix run github:l1ne-company/one-for-all#build-signer -- \\
  --commit "$(git rev-parse HEAD)" \\
  --flake-lock-hash "$(sha256sum flake.lock | awk '{print $1}')" \\
  --artifact-tar-hash "$(sha256sum /tmp/workspace.tar | awk '{print $1}')" \\
  --build-command "nix build (workspace)" \\
  --private-key ~/your-name.key \\
  --out "proofs/$(git rev-parse HEAD).json"

# Option B: Sign individual workspace members
# Build specific member
nix build .#my-cli
# Then follow same signing process for each member
```

## Using the Automated Script

For simpler workflow, use the `sign-build.sh` script:

```bash
# From your project directory
~/path/to/one-for-all/scripts/sign-build.sh \\
  -k ~/your-name.key \\
  -c "nix build"

# This automatically:
# 1. Runs the build
# 2. Creates deterministic tar
# 3. Computes all hashes
# 4. Signs everything
# 5. Creates proofs/<commit>.json
```

## GitHub Actions Integration

Once you have proofs in your repository, GitHub Actions will automatically verify them.

### Workflow

1. Developer makes changes locally
2. Runs build and signs: `./scripts/sign-build.sh -k key.key -c "nix build"`
3. Commits proof: `git add proofs/*.json && git commit -m "Add build proof"`
4. Pushes to PR
5. GitHub Actions runs verification (no rebuild!)

### Example CI Workflow

The verification workflow is already included in `.github/workflows/verify-build-proof.yml`:

```yaml
name: "Verify build proof"
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  verify-proof:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v31

      - name: Build verifier
        run: nix build .#build-verifier

      - name: Verify proof
        run: |
          ./result/bin/build-verifier \\
            proofs/${{ github.sha }}.json
```

## Security Considerations

### Key Management

- **Never** commit private keys
- Store private keys in encrypted storage (LUKS, hardware token, etc.)
- Use `chmod 600` on private key files
- Consider hardware security modules (YubiKey) for production

### Trusted Keys

Create `prover_keys/trusted.txt` to enforce a whitelist:

```bash
# Add trusted public keys (one per line)
echo "f0f65bae20a3256c55f5669c4f8ac97aaac9072c4c79c95188f40320b6ab7d33  # Alice" >> prover_keys/trusted.txt
echo "a1b2c3d4e5f6...  # Bob" >> prover_keys/trusted.txt
```

The verifier will reject proofs from unknown keys.

## All Available Templates

- **quick-start** - Standard Rust project with checks
- **quick-start-simple** - Minimal Rust project
- **quick-start-workspace** - Rust workspace with hakari
- **cross-musl** - Static binary compilation
- **cross-windows** - Windows cross-compilation
- **cross-rust-overlay** - Cross-compile with rust-overlay
- **custom-toolchain** - Custom Rust toolchain
- **build-std** - Compile standard library
- **alt-registry** - Alternative crate registries
- **trunk** - WASM web applications
- **trunk-workspace** - WASM workspace
- **sqlx** - Projects using SQLx
- **end-to-end-testing** - E2E test setup

All templates work with the same signing workflow!

## Troubleshooting

### "Signature verification failed"

The proof was tampered with or the wrong private key was used.

```bash
# Re-sign with correct key
rm proofs/*.json
./scripts/sign-build.sh -k correct-key.key -c "nix build"
```

### "flake.lock hash mismatch"

The flake.lock in your PR differs from what was signed.

```bash
# Update lock and re-sign
nix flake update
nix build
./scripts/sign-build.sh -k key.key -c "nix build"
```

### "Commit SHA mismatch"

You need to sign the current commit, not an old one.

```bash
# Sign the latest commit
git add .
git commit -m "Your changes"
./scripts/sign-build.sh -k key.key -c "nix build"
```

## Next Steps

- Read `src/crypto/README.md` for architecture details
- See `prover_keys/README.md` for key management
- Check `.github/workflows/verify-build-proof.yml` for CI setup
- Explore template examples in `src/lang/rust/examples/`

## References

- [Ed25519 Signatures](https://ed25519.cr.yp.to/)
- [Reproducible Builds](https://reproducible-builds.org/)
- [Nix Build System](https://nixos.org/manual/nix/stable/)
- [one-for-all Documentation](https://l1ne-company.github.io/one-for-all/)
