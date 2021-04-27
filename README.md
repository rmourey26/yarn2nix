# yarn2nix

[![Build Status](https://travis-ci.org/input-output-hk/yarn2nix.svg?branch=master)](https://travis-ci.org/input-output-hk/yarn2nix)

Build Nix derivations from `yarn.lock` files.

1. Make yarn and yarn2nix available in your shell.

   ```sh
   cd $GIT_REPO
   nix-env -i yarn2nix -f .
   nix-env -i yarn -f .
   ```

1. Go to your project dir
1. If you have not generated a yarn.lock file before, run

   ```sh
   yarn install
   ```

1. Create a `default.nix` to build your application (see the example below)

## Requirements

Make sure to generate the lock file with yarn >= 1.10.1

## Example `default.nix`

For example, for the
[`front-end`](https://github.com/microservices-demo/front-end) of weave's
microservice reference application:

```nix
let
  yarn2nixUrl =  "https://github.com/input-output-hk/yarn2nix";
  inherit (builtins) fetchGit
in
{ pkgs     ? import <nixpkgs> {}
, yarn2nix ? pkgs.callPackage (fetchGit yarn2nixUrl) {} }:

mkYarnPackage {
  src = ./.;
}
```

## Example flake

This repository contains a `flake.nix` file that exposes `mkYarnPackage` via an
overlay. Expanding on the previous example:

```nix
{
  description = "My Yarn Package but Flake";

  # NOTE this example won't work with the original numtide/flake-utils
  #      and would have to be adjusted.
  inputs.utils.url = "github:kreisys/flake-utils";
  inputs.yarn2nix.url = "github:input-output-hk/yarn2nix";

  outputs = { self, nixpkgs, yarn2nix, utils }:
    utils.lib.simpleFlake
      {
        inherit nixpkgs;
        systems = [ "x86_64-linux" "x86_64-darwin" ];
        preOverlays = [ yarn2nix ];
        overlay = final: prev: {
          my-yarn-pkg = final.callPackage self {};
        };

        packages = { my-yarn-pkg }: {
          inherit my-yarn-pkg;
          defaultPackage = my-yarn-pkg;
        };
      };
}
```

### Run tests locally

```sh
./run-tests.sh
```

## License

`yarn2nix` is released under the terms of the GPL-3.0 license.
