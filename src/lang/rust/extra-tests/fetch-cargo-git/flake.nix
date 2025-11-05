{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    one-for-all.url = "path:../../../../..";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      one-for-all,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages.cargo-git =
        (one-for-all.lib.mkLib nixpkgs.legacyPackages.${system}).downloadCargoPackageFromGit
          {
            git = "https://github.com/rust-lang/cargo";
            rev = "17f8088d6eafd82349630a8de8cc6efe03abf5fb";
          };
    });
}
