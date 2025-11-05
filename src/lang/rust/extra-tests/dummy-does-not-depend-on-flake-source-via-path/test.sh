#!/bin/sh

set -eu

scriptDir=$(dirname "$0")
cd "${scriptDir}"

repoRoot=$(git rev-parse --show-toplevel)
nixpkgsOverride="$("${repoRoot}/ci/ref-from-lock.sh" "${repoRoot}/src/lang/rust/test#nixpkgs")"
overrideInputs="--override-input one-for-all path:${repoRoot} --override-input nixpkgs ${nixpkgsOverride}"
flakeSrc=$(nix flake metadata ${overrideInputs} --json 2>/dev/null | jq -r '.path')

# Get information about the default derivation
# Then pull out any input sources
drvSrcs=$(nix show-derivation ${overrideInputs} '.#dummy' 2>/dev/null |
  jq -r 'to_entries[].value.inputSrcs[]')

# And lastly make sure we DO NOT find the flake root source listed
# or else the dummy derivation will depend on _too much_ (and get
# invalidated with irrelevant changes)
if echo "${drvSrcs}" | grep -q -F "${flakeSrc}"; then
  echo "error: dummy derivation depends on flake source"
  exit 1
fi
