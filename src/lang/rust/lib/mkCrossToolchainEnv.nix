{
  lib,
  pkgs,
}:
let
  nativePkgs = pkgs.pkgsBuildBuild;
  oneForAllPrefix = "__ONE_FOR_ALL_EXPORT_";
in
stdenvSelector:
let
  hostStdenv = stdenvSelector pkgs.pkgsBuildHost;
  targetStdenv = stdenvSelector pkgs.pkgsHostTarget;
  chosenStdenv = stdenvSelector pkgs;

  varsForPlatform =
    buildKind: stdenv:
    let
      ccPrefix = stdenv.cc.targetPrefix;
      cargoEnv = stdenv.hostPlatform.rust.cargoEnvVarTarget;
      # Configure an emulator for the platform (if we need one, and there's one available)
      runnerAvailable =
        !(stdenv.buildPlatform.canExecute stdenv.hostPlatform)
        && stdenv.hostPlatform.emulatorAvailable nativePkgs;
    in
    # Most non-trivial crates require this, lots of hacks are done for this.
    (lib.optionalAttrs chosenStdenv.hostPlatform.isMinGW {
      "${oneForAllPrefix}CARGO_TARGET_${cargoEnv}_RUSTFLAGS" =
        "-L native=${pkgs.pkgsHostTarget.windows.pthreads}/lib";
    })
    // (lib.optionalAttrs runnerAvailable {
      "${oneForAllPrefix}CARGO_TARGET_${cargoEnv}_RUNNER" = stdenv.hostPlatform.emulator nativePkgs;
    })
    // {
      # Point cargo to the correct linker
      "${oneForAllPrefix}CARGO_TARGET_${cargoEnv}_LINKER" = "${ccPrefix}cc";

      # Set environment variables for the cc crate (see https://docs.rs/cc/latest/cc/#external-configuration-via-environment-variables)
      "${oneForAllPrefix}CC_${cargoEnv}" = "${ccPrefix}cc";
      "${oneForAllPrefix}CXX_${cargoEnv}" = "${ccPrefix}c++";
      "${oneForAllPrefix}AR_${cargoEnv}" = "${ccPrefix}ar";

      # Set environment variables for the cc crate again, this time using the build kind
      # In theory, this should be redundant since we already set their equivalents above, but we set them again just to be sure
      # This way other potential users of e.g. "HOST_CC" also use the correct toolchain
      "${oneForAllPrefix}${buildKind}_CC" = "${ccPrefix}cc";
      "${oneForAllPrefix}${buildKind}_CXX" = "${ccPrefix}c++";
      "${oneForAllPrefix}${buildKind}_AR" = "${ccPrefix}ar";
    };
in
lib.optionalAttrs (chosenStdenv.buildPlatform != chosenStdenv.hostPlatform) (
  lib.mergeAttrsList [
    {
      # Set the target we want to build for (= our host platform)
      # The configureCargoCommonVars setup hook will set CARGO_BUILD_TARGET to this value if the user hasn't specified their own target to use
      "${oneForAllPrefix}CARGO_BUILD_TARGET" = chosenStdenv.hostPlatform.rust.rustcTarget;

      # Pull in any compilers we need
      nativeBuildInputs = [
        hostStdenv.cc
        targetStdenv.cc
      ];
    }

    # NOTE: "host" here isn't the nixpkgs platform; it's a "build kind" corresponding to the "build" nixpkgs platform
    (varsForPlatform "HOST" hostStdenv)

    # NOTE: "target" here isn't the nixpkgs platform; it's a "build kind" corresponding to the "host" nixpkgs platform
    (varsForPlatform "TARGET" targetStdenv)
  ]
)
