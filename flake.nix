{
  description = "actrun – Run GitHub Actions locally";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # TODO: switch back to "github:moonbit-community/moonbit-overlay" once
    # https://github.com/moonbit-community/moonbit-overlay/pull/39 is merged
    moonbit-overlay.url = "github:ryoppippi/moonbit-overlay/fix/moonplatform-bugs";
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
