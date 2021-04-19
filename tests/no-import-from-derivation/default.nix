{ mkYarnPackage, fetchFromGitHub }:

mkYarnPackage rec {
  src = fetchFromGitHub {
    owner = "stevemao";
    repo = "left-pad";
    rev = "v1.3.0";
    sha256 = "0mjvb0b51ivwi9sfkiqnjbj2y1rfblydnb0s4wdk46c7lsf1jisg";
  };

  yarnLock = ./yarn.lock;
  packageJSON = ./package.json;

  buildPhase = ''
    source ${../expectShFunctions.sh}

    expectFilePresent ./node_modules/.yarn-integrity

    # test bin
    expectFilePresent ./node_modules/.bin/acorn

    # devDependencies
    expectFilePresent ./node_modules/benchmark/package.json
  '';
}
