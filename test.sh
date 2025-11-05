#!/usr/bin/env bash
set -euo pipefail

gitRoot="$(git rev-parse --show-toplevel)"
cd "${gitRoot}"

function flakeCheck() {
  if which nom >/dev/null 2>&1; then
    nix flake check --log-format internal-json -v -L "$@" |& nom --json
  else
    nix flake check -L "$@"
  fi
}

flakeCheck
langTestFlake="./src/lang/rust/test#"
flakeCheck "${langTestFlake}"
flakeCheck "${langTestFlake}" --override-input nixpkgs "$("${gitRoot}/ci/ref-from-lock.sh" "${gitRoot}/src/lang/rust/test#nixpkgs-latest-release")"

for f in $(find ./src/lang/rust/examples -maxdepth 1 -mindepth 1 -type d | sort -u); do
  echo "validating ${f}"
  "${gitRoot}/ci/check-example.sh" "${f}" "${gitRoot}/src/lang/rust/test#nixpkgs"
done
