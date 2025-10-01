{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "l1ne-for-all-utils";
  version = "0.0.1";

  src = lib.sourceFilesBySuffices ./. [
    ".rs"
    ".toml"
    ".lock"
  ];
  cargoLock.lockFile = ./Cargo.lock;
}
