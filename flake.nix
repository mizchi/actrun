{
  description = "actrun – Run GitHub Actions locally";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    moonbit-overlay.url = "github:moonbit-community/moonbit-overlay";
    moon-registry = {
      url = "git+https://mooncakes.io/git/index";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      moonbit-overlay,
      moon-registry,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ moonbit-overlay.overlays.default ];
          config.allowBroken = true;
        };

      mkActrun =
        system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.moonPlatform.buildMoonPackage {
          src = ./.;
          moonModJson = ./moon.mod.json;
          moonRegistryIndex = moon-registry;

          doCheck = false;
          propagatedBuildInputs = [ pkgs.git ];
          nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];

          meta.platforms = supportedSystems;
        };
    in
    {
      overlays.default = _final: prev: {
        actrun = mkActrun prev.stdenv.hostPlatform.system;
      };

      packages = forAllSystems (
        system:
        let
          pkg = mkActrun system;
        in
        {
          default = pkg;
          actrun = pkg;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          moonHome = pkgs.moonPlatform.bundleWithRegistry {
            cachedRegistry = pkgs.moonPlatform.buildCachedRegistry {
              moonModJson = ./moon.mod.json;
              registryIndexSrc = moon-registry;
            };
          };
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              moonHome
              pkgs.git
              pkgs.just
              pkgs.pnpm
              pkgs.nodejs
            ];
            env.MOON_HOME = "${moonHome}";
          };
        }
      );

      apps = forAllSystems (
        system:
        let
          pkg = mkActrun system;
        in
        {
          default = {
            type = "app";
            program = "${pkg}/bin/actrun";
          };
          actrun = {
            type = "app";
            program = "${pkg}/bin/actrun";
          };
        }
      );
    };
}
