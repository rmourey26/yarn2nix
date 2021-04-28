{
  description = "Package Yarn Projects with Nix";

  inputs.utils.url = "github:kreisys/flake-utils";

  outputs = { self, nixpkgs, utils }:
    utils.lib.simpleFlake
      {
        inherit nixpkgs;
        systems = [ "x86_64-linux" "x86_64-darwin" ];
        overlay = final: prev: {
          inherit (final.callPackage self {}) mkYarnPackage;
        };

        extraOutputs = {
          templates.default = {
            path = ./template;
            description = "A yarn2nix-based package";
          };

          defaultTemplate = self.templates.default;
        };
      };
}
