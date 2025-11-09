{
  description = "A Nix library for building cargo projects. Never build twice thanks to incremental artifact caching.";

  inputs = { };

  outputs =
    { ... }:
    let
      mkLib =
        pkgs:
        import ./default.nix {
          inherit pkgs;
        };
      nodes = (builtins.fromJSON (builtins.readFile ./src/lang/rust/test/flake.lock)).nodes;
      inputFromLock =
        name:
        let
          locked = nodes.${name}.locked;
        in
        fetchTarball {
          url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
          sha256 = locked.narHash;
        };

      eachSystem =
        systems: f:
        let
          # Merge together the outputs for all systems.
          op =
            attrs: system:
            let
              ret = f system;
              op =
                attrs: key:
                attrs
                // {
                  ${key} = (attrs.${key} or { }) // {
                    ${system} = ret.${key};
                  };
                };
            in
            builtins.foldl' op attrs (builtins.attrNames ret);
        in
        builtins.foldl' op { } systems;

      eachDefaultSystem = eachSystem [
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
      ];
    in
    {
      lib = {
        inherit mkLib;
      };

      overlays.default = _final: _prev: { };

      templates = rec {
        alt-registry = {
          description = "Build a cargo project with alternative crate registries";
          path = ./src/lang/rust/examples/alt-registry;
        };

        build-std = {
          description = "Build a cargo project while also compiling the standard library";
          path = ./src/lang/rust/examples/build-std;
        };

        cross-musl = {
          description = "Building static binaries with musl";
          path = ./src/lang/rust/examples/cross-musl;
        };

        cross-rust-overlay = {
          description = "Cross compiling a rust program using rust-overlay";
          path = ./src/lang/rust/examples/cross-rust-overlay;
        };

        cross-windows = {
          description = "Cross compiling a rust program for windows";
          path = ./src/lang/rust/examples/cross-windows;
        };

        custom-toolchain = {
          description = "Build a cargo project with a custom toolchain";
          path = ./src/lang/rust/examples/custom-toolchain;
        };

        end-to-end-testing = {
          description = "Run End-to-End tests for a webapp";
          path = ./src/lang/rust/examples/end-to-end-testing;
        };

        default = quick-start;
        quick-start = {
          description = "Build a cargo project";
          path = ./src/lang/rust/examples/quick-start;
        };

        quick-start-simple = {
          description = "Build a cargo project without extra checks";
          path = ./src/lang/rust/examples/quick-start-simple;
        };

        quick-start-workspace = {
          description = "Build a cargo workspace with hakari";
          path = ./src/lang/rust/examples/quick-start-workspace;
        };

        sqlx = {
          description = "Build a cargo project which uses SQLx";
          path = ./src/lang/rust/examples/sqlx;
        };

        trunk = {
          description = "Build a trunk project";
          path = ./src/lang/rust/examples/trunk;
        };

        trunk-workspace = {
          description = "Build a workspace with a trunk member";
          path = ./src/lang/rust/examples/trunk-workspace;
        };
      };
    }
    // eachDefaultSystem (
      system:
      let
        nixpkgs = inputFromLock "nixpkgs";
        nixpkgsLatest = inputFromLock "nixpkgs-latest-release";
        rustOverlay = import (inputFromLock "rust-overlay");
        fenix = import (inputFromLock "fenix") {
          inherit system;
        };

        mkPkgs =
          src: extra:
          import src (
            (if (extra ? system) || (extra ? localSystem) then { } else { inherit system; }) // extra
          );

        pkgs = mkPkgs nixpkgs { };

        formatter = pkgs.nixfmt-tree;

        myLib = mkLib pkgs;

        ciRunner = pkgs.writeShellApplication {
          name = "one-for-all-ci";
          runtimeInputs = [ pkgs.nix ];
          text = ''
            set -euo pipefail
            exec nix flake check --accept-flake-config --print-build-logs "$@"
          '';
        };

        mkChecksFor =
          name: nixpkgsSrc:
          let
            pkgsBase = mkPkgs nixpkgsSrc { };
            pkgsChecks = mkPkgs nixpkgsSrc {
              overlays = [ rustOverlay ];
            };
            mkLibFor = mkLib pkgsChecks;
            myLibCross = mkLib (
              mkPkgs nixpkgsSrc {
                localSystem = system;
                crossSystem = "wasm32-unknown-none";
              }
            );
            myLibFenix = (mkLib pkgsBase).overrideToolchain (
              fenix.latest.withComponents [
                "cargo"
                "rust-src"
                "rustc"
              ]
            );
            myLibWindows = mkLib (
              mkPkgs nixpkgsSrc {
                localSystem = system;
                crossSystem = {
                  config = "x86_64-w64-mingw32";
                  libc = "msvcrt";
                };
              }
            );
            myLibWindowsCross = mkLib pkgsBase.pkgsCross.mingwW64;
            rawChecks = pkgsChecks.callPackages ./src/lang/rust/checks {
              pkgs = pkgsChecks;
              inherit
                myLibCross
                myLibFenix
                myLibWindows
                myLibWindowsCross
                ;
              myLib = mkLibFor;
            };
          in
          pkgs.lib.mapAttrs' (checkName: drv: pkgs.lib.nameValuePair "${name}-${checkName}" drv) rawChecks;

        checks = (mkChecksFor "nixpkgs" nixpkgs) // (mkChecksFor "nixpkgs-latest" nixpkgsLatest);
      in
      {
        inherit formatter checks;

        packages =
          (import ./src/lang/rust/pkgs {
            inherit pkgs myLib;
          })
          // (import ./src/crypto/pkgs {
            inherit pkgs;
          })
          // {
            local-ci = ciRunner;
          };

        apps.ci = {
          type = "app";
          program = "${ciRunner}/bin/one-for-all-ci";
          meta = {
            description = "Run the one-for-all local CI suite (nix flake check wrapper)";
            mainProgram = "one-for-all-ci";
          };
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            deadnix
            formatter
            jq
            mdbook
            nix-eval-jobs
            taplo
            cargo
            rustc
          ];
        };
      }
    );
}
