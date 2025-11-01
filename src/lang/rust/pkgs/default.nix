{ pkgs, myLib }:

{
  book =
    let
      inherit (pkgs) lib;
      cleanedSrc = lib.fileset.toSource {
        root = ./..;
        fileset = lib.fileset.unions [
          ./../docs
          ./../examples
          ./../README.md
          ./../CHANGELOG.md
        ];
      };
    in
    pkgs.runCommand "one-for-all-book" { } ''
      ${pkgs.mdbook}/bin/mdbook build --dest-dir $out ${cleanedSrc}/docs
    '';

  one-for-all-utils = myLib.callPackage ./one-for-all-utils { };
}
