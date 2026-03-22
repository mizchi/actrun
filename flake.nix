{
  description = "Nix overlay for actrun";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      version = "0.21.3";

      # aarch64-linux is not supported yet (no release binary available)
      sources = {
        x86_64-linux = {
          url = "https://github.com/mizchi/actrun/releases/download/v${version}/actrun-linux-x64.tar.gz";
          hash = "sha256-pdK1Khe5FeEkkLJWJNQ2+SHlLxH34yi8Ndai79zR69Q=";
        };
        aarch64-darwin = {
          url = "https://github.com/mizchi/actrun/releases/download/v${version}/actrun-macos-arm64.tar.gz";
          hash = "sha256-13/zMfczNPtE0Lh9iWy9V3UtQQJJ2oMQWIy2RA7FD8w=";
        };
      };

      supportedSystems = builtins.attrNames sources;

      mkActrun =
        pkgs:
        let
          src = sources.${pkgs.stdenv.hostPlatform.system} or (throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}");
        in
        pkgs.stdenv.mkDerivation {
          pname = "actrun";
          inherit version;

          src = pkgs.fetchurl {
            inherit (src) url hash;
          };

          sourceRoot = ".";

          nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];

          propagatedBuildInputs = [ pkgs.git ];

          installPhase = ''
            install -Dm755 actrun $out/bin/actrun
          '';

          meta = {
            description = "Run GitHub Actions locally";
            homepage = "https://github.com/mizchi/actrun";
            platforms = supportedSystems;
          };
        };

      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      overlays.default = _final: prev: {
        actrun = mkActrun prev;
      };

      packages = forAllSystems (
        pkgs:
        let
          pkg = mkActrun pkgs;
        in
        {
          default = pkg;
          actrun = pkg;
        }
      );
    };
}
