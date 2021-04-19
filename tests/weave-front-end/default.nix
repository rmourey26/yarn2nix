{ yarn2nix }:

yarn2nix.mkYarnPackage {
  src = ./.;
  buildPhase = ''
    source ${../expectShFunctions.sh}

    expectFilePresent ./node_modules/.yarn-integrity

    # dependencies
    expectFilePresent ./node_modules/async/package.json

    # devDependencies
    expectFilePresent ./node_modules/chai/package.json
  '';
}
