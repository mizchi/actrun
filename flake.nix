{
  description = "actrun – Run GitHub Actions locally";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    moonbit-overlay.url = "github:moonbit-community/moonbit-overlay";
    moon-registry = {
      url = "git+https://mooncakes.io/git/index";
      flake = false;
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake = {
        overlays.default = _final: prev: {
          actrun = prev.callPackage (
            { moonPlatform, ... }:
            moonPlatform.buildMoonPackage {
              src = ./.;
              moonModJson = ./moon.mod.json;
              moonRegistryIndex = inputs.moon-registry;

              doCheck = false;
              propagatedBuildInputs = [ prev.git ];
              nativeBuildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
            }
          ) { };
        };
      };

      perSystem =
        { pkgs, system, ... }:
        let
          moonPkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.moonbit-overlay.overlays.default ];
            config.allowBroken = true;
          };

          actrun = moonPkgs.moonPlatform.buildMoonPackage {
            src = ./.;
            moonModJson = ./moon.mod.json;
            moonRegistryIndex = inputs.moon-registry;

            doCheck = false;
            propagatedBuildInputs = [ moonPkgs.git ];
            nativeBuildInputs = moonPkgs.lib.optionals moonPkgs.stdenv.isLinux [
              moonPkgs.autoPatchelfHook
            ];
          };

          moonHome = moonPkgs.moonPlatform.bundleWithRegistry {
            cachedRegistry = moonPkgs.moonPlatform.buildCachedRegistry {
              moonModJson = ./moon.mod.json;
              registryIndexSrc = inputs.moon-registry;
            };
          };
        in
        {
          packages = {
            default = actrun;
            inherit actrun;
          };

          apps = {
            default = {
              type = "app";
              program = "${actrun}/bin/actrun";
            };
            actrun = {
              type = "app";
              program = "${actrun}/bin/actrun";
            };
          };

          devShells.default = moonPkgs.mkShellNoCC {
            packages = [
              moonHome
              moonPkgs.git
              moonPkgs.just
              moonPkgs.pnpm
              moonPkgs.nodejs
            ];
            env.MOON_HOME = "${moonHome}";
          };
        };
    };
}
