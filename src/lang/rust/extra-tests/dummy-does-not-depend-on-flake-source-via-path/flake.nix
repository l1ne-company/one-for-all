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
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        oneForAllLib = one-for-all.mkLib pkgs;
      in
      {
        packages.dummy = oneForAllLib.mkDummySrc {
          src = ./.;
        };
      }
    );
}
