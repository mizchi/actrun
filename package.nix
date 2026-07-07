{
  lib,
  git,
  openssl,
  autoPatchelfHook,
  stdenv,
  moonPlatform,
  moonRegistryIndex,
}:
moonPlatform.buildMoonPackage {
  src = ./.;
  moonModJson = ./moon.mod.json;
  inherit moonRegistryIndex;

  doCheck = false;
  propagatedBuildInputs = [ git ];
  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  runtimeDependencies = lib.optionals stdenv.isLinux [ (lib.getLib openssl) ];

  meta = {
    description = "Run GitHub Actions locally";
    homepage = "https://github.com/mizchi/actrun";
    mainProgram = "actrun";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
