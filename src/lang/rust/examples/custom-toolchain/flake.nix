{
  description = "Build a cargo project with a custom toolchain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    one-for-all.url = "path:../../../../..";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      one-for-all,
      flake-utils,
      rust-overlay,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        # NB: we don't need to overlay our custom toolchain for the *entire*
        # pkgs (which would require rebuidling anything else which uses rust).
        # Instead, we just want to update the scope that one-for-all will use by appending
        # our specific toolchain there.
        oneForAllLib = (one-for-all.mkLib pkgs).overrideToolchain (
          p:
          p.rust-bin.stable.latest.default.override {
            targets = [ "wasm32-wasip1" ];
          }
        );

        my-crate = oneForAllLib.buildPackage {
          src = oneForAllLib.cleanCargoSource ./.;
          strictDeps = true;

          cargoExtraArgs = "--target wasm32-wasip1";

          # Tests currently need to be run via `cargo wasi` which
          # isn't packaged in nixpkgs yet...
          doCheck = false;

          buildInputs = [
            # Add additional build inputs here
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # Additional darwin specific inputs can be set here
            pkgs.libiconv
          ];
        };
      in
      {
        checks = {
          inherit my-crate;
        };

        packages.default = my-crate;

        apps.default = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "my-app" ''
            ${pkgs.wasmtime}/bin/wasmtime run ${my-crate}/bin/custom-toolchain.wasm
          '';
        };

        devShells.default = oneForAllLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};

          # Extra inputs can be added here; cargo and rustc are provided by default
          # from the toolchain that was specified earlier.
          packages = [
          ];
        };
      }
    );
}
