{
  pkgs ? import <nixpkgs> { },
  moonRegistryIndex ? builtins.fetchGit {
    url = "https://mooncakes.io/git/index";
    ref = "main";
  },
  ...
}:
pkgs.callPackage ./package.nix { inherit moonRegistryIndex; }
