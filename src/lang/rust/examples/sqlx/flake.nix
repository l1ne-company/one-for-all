{
  description = "Build a cargo project which uses SQLx";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    one-for-all.url = "github:l1ne-company/one-for-all";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      one-for-all,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        inherit (pkgs) lib;

        oneForAllLib = one-for-all.lib.mkLib pkgs;

        unfilteredRoot = ./.; # The original, unfiltered source
        src = lib.fileset.toSource {
          root = unfilteredRoot;
          fileset = lib.fileset.unions [
            # Default files from one-for-all (Rust and cargo files)
            (oneForAllLib.fileset.commonCargoSources unfilteredRoot)
            # Include all the .sql migrations as well
            ./migrations
          ];
        };

        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          inherit src;
          strictDeps = true;

          nativeBuildInputs = [
            pkgs.pkg-config
          ];

          buildInputs = [
            # Add additional build inputs here
            pkgs.openssl
          ];

          # Additional environment variables can be set directly
          # MY_CUSTOM_VAR = "some value";
        };

        # Build *just* the cargo dependencies, so we can reuse
        # all of that work (e.g. via cachix) when running in CI
        cargoArtifacts = oneForAllLib.buildDepsOnly commonArgs;

        # Build the actual crate itself, reusing the dependency
        # artifacts from above.
        my-crate = oneForAllLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;

            nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [
              pkgs.sqlx-cli
            ];

            preBuild = ''
              export DATABASE_URL=sqlite:./db.sqlite3
              sqlx database create
              sqlx migrate run
            '';
          }
        );
      in
      {
        checks = {
          # Build the crate as part of `nix flake check` for convenience
          inherit my-crate;
        };

        packages = {
          default = my-crate;
          inherit my-crate;
        };

        devShells.default = oneForAllLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};

          # Additional dev-shell environment variables can be set directly
          # MY_CUSTOM_DEVELOPMENT_VAR = "something else";

          # Extra inputs can be added here; cargo and rustc are provided by default.
          packages = [
            pkgs.sqlx-cli
          ];
        };
      }
    );
}
