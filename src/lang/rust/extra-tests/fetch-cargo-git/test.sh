#!/bin/sh

set -eu

scriptDir=$(dirname "$0")
cd "${scriptDir}"

repoRoot=$(git rev-parse --show-toplevel)
nixpkgsOverride="$("${repoRoot}/ci/ref-from-lock.sh" "${repoRoot}/src/lang/rust/test#nixpkgs")"
overrideInputs="--override-input one-for-all path:${repoRoot} --override-input nixpkgs ${nixpkgsOverride}"

# Try fetching the git verision of cargo
nix build ${overrideInputs} .#cargo-git
