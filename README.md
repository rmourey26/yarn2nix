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

### Git dependencies

For retrieving git dependencies, we use `builtins.fetchGit` exclusively while
providing it with all the information necessary to work in restricted mode. This
seems to work as expected in most use-cases. One limitation of
`builtins.fetchGit`, however, is that it must be given a ref (branch or tag)
from which the desired revision is reachable. Most commonly, one is provided in
`package.json`: `git+https://github.com/org/repo#branch`. But sometimes during
development it might be convenient to call for a specific commit in
`package.json` to prevent the resolved revision in the lock file from advancing
on an update. In that case, we currently don't have a way to guess what the
branch is. For that reason, `mkYarnPackage` can take two additional arguments:

- `refHints`: an attribute set that maps dependency names to branches. (default:
  `{}`)
- `defaultRef`: the branch we would fallback to if `package.json` calls for a
  specific revision and `refHints` does not have a corresponding entry.
  (default: `master`)

Example:

We want to pin commit `f18d6829ef` from the `develop` branch of `@foo/bar`.

package.json:

```json
{
   ...
   "dependencies": {
     "@foo/bar": "git+https://github.com/foo-corp/barjs#f18d6829ef"
   }

}
```

`default.nix`:

```nix
# ...
mkYarnPackage {
  src = ./.;
  defaultRef = "develop";
}
```

or, if we also have other dependencies that require different branches:

```nix
# ...
mkYarnPackage {
  src = ./.;
  refHints."@foo/bar" = "develop";
  refHints."@foo/baz" = "main";
}
```

### Run tests locally

```sh
./run-tests.sh
```

## License

`yarn2nix` is released under the terms of the GPL-3.0 license.
