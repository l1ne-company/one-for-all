# Repository Guidelines

## Project Structure & Module Organization
This repository is a Nix-first toolkit for reproducible Rust projects and zero-knowledge build proofs. Core library code lives under `src/lang/rust`, split into `lib/`, `pkgs/`, and `examples/` templates consumable via `nix flake init`. Companion integrations sit in `src/lang/python` and `src/lang/zig`. Cryptography workflows reside in `src/crypto`, with the `build-signer` and `build-verifier` crates plus shell-based integration tests under `src/crypto/tests`. Documentation is maintained as an mdBook in `docs/`, while automation lives in `scripts/` and CI helpers in `ci/`. Reusable fixtures, such as proving keys, are stored in `prover_keys/` and `proofs/`.

## Build, Test, and Development Commands
- `nix develop`: enter the project devshell with `cargo`, `clippy`, `rustfmt`, `taplo`, and `nixfmt-tree`.
- `nix flake check`: build primary packages and run default checks; pass `-L` for verbose logs during debugging.
- `nix flake check`: run the complete validation suite, including the `src/lang/rust/checks` suite and compatibility runs against alternate nixpkgs pins.
- `ci/check-example.sh ./src/lang/rust/examples/<name> src/lang/rust/test#nixpkgs`: validate a specific example template before publishing docs.

## Coding Style & Naming Conventions
Rust code must stay `rustfmt` clean with the stable profile bundled in the devshell; prefer `snake_case` modules and `UpperCamelCase` types to align with upstream examples. Nix expressions are formatted with `nix fmt` (nixfmt-tree) and kept free of unused definitions via `deadnix`. TOML manifests should be normalized with `taplo fmt`, and shell utilities mirror the existing `set -euo pipefail` pattern with lowercase, hyphenated filenames.

## Testing Guidelines
Add new example validations beside existing scripts in `src/crypto/tests` or under `scripts/` when they need repository-wide context. Shell tests follow the `test-*.sh` naming seen in `src/crypto/tests` and must be executable. For Rust-oriented checks, ensure `nix flake check` covers the new derivation; if not, wire it into `src/lang/rust/pkgs` and extend the flake `checks` set. Capture fixtures or expected outputs in `src/crypto/tests/fixtures` so they are tracked deterministically.

## Commit & Pull Request Guidelines
Recent history shows short, imperative commit subjects (e.g. “add build proof for current commit”); continue that style and scope each commit to one logical change. Pull requests should outline the motivation, reference relevant docs or issues, and note the exact commands executed (e.g. `nix flake check`). Attach screenshots or log excerpts when altering proof outputs or developer tooling so reviewers can verify changes without rerunning the entire pipeline.
