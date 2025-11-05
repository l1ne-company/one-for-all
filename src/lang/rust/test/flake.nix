{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-latest-release.url = "github:NixOS/nixpkgs/nixos-25.05";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };

    one-for-all.url = "path:../../../..";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ ... }:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        mkLib = pkgs: pkgs.callPackage ../lib { };
        nixpkgs = inputs.nixpkgs;
        pkgs = import nixpkgs {
          inherit system;
        };

        pkgsChecks = import nixpkgs {
          inherit system;
          overlays = [
            (import inputs.rust-overlay)
          ];
        };
        fenix = import inputs.fenix {
          inherit system;
        };
      in
      {
        checks = pkgsChecks.callPackages ../checks {
          pkgs = pkgsChecks;
          myLib = mkLib pkgsChecks;
          myLibCross = mkLib (
            import nixpkgs {
              localSystem = system;
              crossSystem = "wasm32-unknown-none";
            }
          );
          myLibFenix = (mkLib pkgs).overrideToolchain (
            fenix.latest.withComponents [
              "cargo"
              "rust-src"
              "rustc"
            ]
          );
          myLibWindows = mkLib (
            import nixpkgs {
              localSystem = system;
              crossSystem = {
                config = "x86_64-w64-mingw32";
                libc = "msvcrt";
              };
            }
          );
          myLibWindowsCross = mkLib nixpkgs.legacyPackages.${system}.pkgsCross.mingwW64;
        };
      }
    );
}
