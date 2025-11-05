{ pkgs, myLib }:

{
  book =
    let
      inherit (pkgs) lib;
      root = ./../../../..;
      cleanedSrc = lib.fileset.toSource {
        inherit root;
        fileset = lib.fileset.unions [
          (root + "/docs")
          (root + "/src/lang/rust/examples")
          (root + "/README.md")
          (lib.fileset.maybeMissing (root + "/CHANGELOG.md"))
        ];
      };
    in
    pkgs.runCommand "one-for-all-book" { } ''
      ${pkgs.mdbook}/bin/mdbook build --dest-dir $out ${cleanedSrc}/docs
    '';

  one-for-all-utils = myLib.callPackage ./one-for-all-utils { };
}
