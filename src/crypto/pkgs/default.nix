{ pkgs }:

let
  # Build from the entire workspace
  workspaceSrc = pkgs.lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      let
        baseName = baseNameOf path;
      in
      # Include Cargo files and Rust sources
      (type == "directory")
      || (pkgs.lib.hasSuffix ".rs" path)
      || (pkgs.lib.hasSuffix ".toml" path)
      || (baseName == "Cargo.lock");
  };
in
{
  build-signer = pkgs.rustPlatform.buildRustPackage {
    pname = "build-signer";
    version = "0.1.0";

    src = workspaceSrc;

    # Build only the signer binary
    cargoBuildFlags = [
      "--bin"
      "build-signer"
    ];
    cargoTestFlags = [
      "--bin"
      "build-signer"
    ];

    cargoHash = "sha256-aD7da1xJzL1CAvPfihlpmyE9jByt45ld+ia3OmY0ops=";

    meta = {
      description = "Sign Nix build artifacts with Ed25519";
      mainProgram = "build-signer";
    };
  };

  build-verifier = pkgs.rustPlatform.buildRustPackage {
    pname = "build-verifier";
    version = "0.1.0";

    src = workspaceSrc;

    # Build only the verifier binary
    cargoBuildFlags = [
      "--bin"
      "build-verifier"
    ];
    cargoTestFlags = [
      "--bin"
      "build-verifier"
    ];

    cargoHash = "sha256-aD7da1xJzL1CAvPfihlpmyE9jByt45ld+ia3OmY0ops=";

    meta = {
      description = "Verify signed Nix build artifacts";
      mainProgram = "build-verifier";
    };
  };
}
