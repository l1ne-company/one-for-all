{
  pkgs ? import <nixpkgs> { },
}:

pkgs.callPackage ./src/lang/rust/lib { }
