{ pkgs ? import <nixpkgs> {}
, nodejs ? pkgs.nodejs
, yarn ? pkgs.yarn
}:

let
  inherit (pkgs)
    runCommandNoCC gnutar stdenv lib linkFarm git rsync
    makeWrapper;

  inherit (import ./lib.nix { inherit (pkgs) lib; })
    composeAll yarnLockToFetchables fixupYarnLock;

  fetchurl = import <nix/fetchurl.nix>;
  fetchgit = args: let
    repo = builtins.fetchGit {
      inherit (args) url rev ref;
    };
  in
    runCommandNoCC args.name { buildInputs = [gnutar]; } ''
      # Set u+w because tar-fs can't unpack archives with read-only dirs
      # https://github.com/mafintosh/tar-fs/issues/79
      tar cf $out --mode u+w -C ${repo} .
    '';

  fetch = args: {
    git = fetchgit { inherit (args) url name rev ref; };
    url = fetchurl { inherit (args) url name hash; };
  }.${args.type};

in rec {
  # Export yarn again to make it easier to find out which yarn was used.
  inherit yarn;

  # Re-export pkgs
  inherit pkgs;

  unlessNull = item: alt:
    if item == null then alt else item;

  reformatPackageName = pname:
    let
      # regex adapted from `validate-npm-package-name`
      # will produce 3 parts e.g.
      # "@someorg/somepackage" -> [ "@someorg/" "someorg" "somepackage" ]
      # "somepackage" -> [ null null "somepackage" ]
      parts = builtins.tail (builtins.match "^(@([^/]+)/)?([^/]+)$" pname);
      # if there is no organisation we need to filter out null values.
      non-null = builtins.filter (x: x != null) parts;
    in builtins.concatStringsSep "-" non-null;

  # https://docs.npmjs.com/files/package.json#license
  # TODO: support expression syntax (OR, AND, etc)
  spdxLicense = licstr:
    if licstr == "UNLICENSED" then
      lib.licenses.unfree
    else
      lib.findFirst
        (l: l ? spdxId && l.spdxId == licstr)
        { shortName = licstr; }
        (builtins.attrValues lib.licenses);

  # Loads the generated offline cache. This will be used by yarn as
  # the package source.
  importOfflineCache = { yarnLock, refHints, defaultRef }: let
    fetchables = yarnLockToFetchables {
      inherit yarnLock refHints defaultRef;
    };
    entries = lib.forEach fetchables (fetchable: {
      inherit (fetchable) name;
      path = fetch fetchable;
    }); in linkFarm "offline" entries;

  defaultYarnFlags = [
    "--offline"
    "--frozen-lockfile"
    "--ignore-engines"
    "--ignore-scripts"
  ];

  mkYarnModules = {
    name, # safe name and version, e.g. testcompany-one-modules-1.0.0
    pname, # original name, e.g @testcompany/one
    version,
    packageJSON,
    yarnLock,
    yarnFlags ? defaultYarnFlags,
    pkgConfig ? {},
    preBuild ? "",
    postBuild ? "",
    refHints ? {},
    defaultRef ? "master",
    workspaceDependencies ? [], # List of yarn packages
  }:
    let
      offlineCache = importOfflineCache {
        inherit yarnLock refHints defaultRef;
      };

      extraBuildInputs = (lib.flatten (builtins.map (key:
        pkgConfig.${key}.buildInputs or []
      ) (builtins.attrNames pkgConfig)));

      postInstall = (builtins.map (key:
        if (pkgConfig.${key} ? postInstall) then
          ''
            for f in $(find -L -path '*/node_modules/${key}' -type d); do
              (cd "$f" && (${pkgConfig.${key}.postInstall}))
            done
          ''
        else
          ""
      ) (builtins.attrNames pkgConfig));

      workspaceJSON = pkgs.writeText
        "${name}-workspace-package.json"
        (builtins.toJSON { private = true; workspaces = ["deps/**"]; }); # scoped packages need second splat

      workspaceDependencyLinks = lib.concatMapStringsSep "\n"
        (dep: ''
          mkdir -p "deps/${dep.pname}"
          ln -sf ${dep.packageJSON} "deps/${dep.pname}/package.json"
        '')
        workspaceDependencies;

    in stdenv.mkDerivation {
      inherit preBuild postBuild name;
      phases = ["configurePhase" "buildPhase"];
      buildInputs = [ yarn nodejs git ] ++ extraBuildInputs;

      configurePhase = ''
        # Yarn writes cache directories etc to $HOME.
        export HOME=$PWD/yarn_home
      '';

      fixedupYarnLock = fixupYarnLock yarnLock;
      passAsFile = [ "fixedupYarnLock" ];

      buildPhase = ''
        runHook preBuild

        mkdir -p "deps/${pname}"
        cp ${packageJSON} "deps/${pname}/package.json"
        cp ${workspaceJSON} ./package.json

        cp $fixedupYarnLockPath ./yarn.lock
        chmod +w $_

        yarn config --offline set yarn-offline-mirror ${offlineCache}
        ${workspaceDependencyLinks}

        yarn install ${lib.escapeShellArgs yarnFlags}

        ${lib.concatStringsSep "\n" postInstall}

        mkdir $out
        mv node_modules $out/
        mv deps $out/
        patchShebangs $out

        runHook postBuild
      '';
    };

  # This can be used as a shellHook in mkYarnPackage. It brings the built node_modules into
  # the shell-hook environment.
  linkNodeModulesHook = ''
    if [[ -d node_modules || -L node_modules ]]; then
      echo "./node_modules is present. Replacing."
      rm -rf node_modules
    fi

    ln -s "$node_modules" node_modules
  '';

  mkYarnWorkspace = {
    src,
    packageJSON ? src + "/package.json",
    yarnLock ? src + "/yarn.lock",
    packageOverrides ? {},
    ...
  }@attrs:
  let
    package = lib.importJSON packageJSON;

    packageGlobs = package.workspaces;

    globElemToRegex = lib.replaceStrings ["*"] [".*"];

    # PathGlob -> [PathGlobElem]
    splitGlob = lib.splitString "/";

    # Path -> [PathGlobElem] -> [Path]
    # Note: Only directories are included, everything else is filtered out
    expandGlobList = base: globElems:
      let
        elemRegex = globElemToRegex (lib.head globElems);
        rest = lib.tail globElems;
        children = lib.attrNames (lib.filterAttrs (name: type: type == "directory") (builtins.readDir base));
        matchingChildren = lib.filter (child: builtins.match elemRegex child != null) children;
      in if globElems == []
        then [ base ]
        else lib.concatMap (child: expandGlobList (base+("/"+child)) rest) matchingChildren;

    # Path -> PathGlob -> [Path]
    expandGlob = base: glob: expandGlobList base (splitGlob glob);

    packagePaths = lib.concatMap (expandGlob src) packageGlobs;

    packages = lib.listToAttrs (map (src:
      let
        packageJSON = src + "/package.json";

        package = lib.importJSON packageJSON;

        allDependencies = lib.foldl (a: b: a // b) {} (map (field: lib.attrByPath [field] {} package) ["dependencies" "devDependencies"]);

        # { [name: String] : { pname : String, packageJSON : String, ... } } -> { [pname: String] : version } -> [{ pname : String, packageJSON : String, ... }]
        getWorkspaceDependencies = packages: allDependencies:
          let
            packageList = lib.attrValues packages;
          in
            composeAll [
              (lib.filter (x: x != null))
              (lib.mapAttrsToList (pname: _version: lib.findFirst (package: package.pname == pname) null packageList))
            ] allDependencies;

        workspaceDependencies = getWorkspaceDependencies packages allDependencies;

        name = reformatPackageName package.name;
      in {
        inherit name;
        value = mkYarnPackage (
          builtins.removeAttrs attrs ["packageOverrides"]
          // { inherit src packageJSON yarnLock workspaceDependencies; }
          // lib.attrByPath [name] {} packageOverrides
        );
      })
      packagePaths
    );
  in packages;

  mkYarnPackage = {
    name ? null,
    src,
    packageJSON ? src + "/package.json",
    yarnLock ? src + "/yarn.lock",
    yarnFlags ? defaultYarnFlags,
    yarnPreBuild ? "",
    pkgConfig ? {},
    extraBuildInputs ? [],
    publishBinsFor ? null,
    defaultRef ? "master",
    refHints ? {},
    workspaceDependencies ? [], # List of yarnPackages
    ...
  }@attrs:
    let
      package = lib.importJSON packageJSON;
      pname = package.name;
      safeName = reformatPackageName pname;
      version = attrs.version or package.version;
      baseName = unlessNull name "${safeName}-${version}";

      workspaceDependenciesTransitive = lib.unique (
        (lib.flatten (builtins.map (dep: dep.workspaceDependencies) workspaceDependencies))
        ++ workspaceDependencies
      );

      deps = mkYarnModules {
        name = "${safeName}-modules-${version}";
        preBuild = yarnPreBuild;
        workspaceDependencies = workspaceDependenciesTransitive;
        inherit packageJSON pname version yarnLock yarnFlags pkgConfig defaultRef refHints;
      };

      publishBinsFor_ = unlessNull publishBinsFor [pname];

      linkDirFunction = ''
        linkDirToDirLinks() {
          target=$1
          if [ ! -f "$target" ]; then
            mkdir -p "$target"
          elif [ -L "$target" ]; then
            local new=$(mktemp -d)
            trueSource=$(realpath "$target")
            if [ "$(ls $trueSource | wc -l)" -gt 0 ]; then
              ln -s $trueSource/* $new/
            fi
            rm -r "$target"
            mv "$new" "$target"
          fi
        }
      '';

      workspaceDependencyCopy = lib.concatMapStringsSep "\n"
        (dep: ''
          # ensure any existing scope directory is not a symlink
          linkDirToDirLinks "$(dirname node_modules/${dep.pname})"
          mkdir -p "deps/${dep.pname}"
          tar -xf "${dep}/tarballs/${dep.name}.tgz" --directory "deps/${dep.pname}" --strip-components=1
          #if [ ! -e "deps/${dep.pname}/node_modules" ]; then
          #  #ln -s "${deps}/deps/${dep.pname}/node_modules" "deps/${dep.pname}/node_modules"
          #fi
        '')
        workspaceDependenciesTransitive;

    in stdenv.mkDerivation (builtins.removeAttrs attrs [
      "pkgConfig"
      "workspaceDependencies"
      "refHints"
      "defaultRef"
    ] // rec {
      inherit src pname;

      name = baseName;

      buildInputs = [ yarn nodejs rsync ] ++ extraBuildInputs;

      node_modules = deps + "/node_modules";

      configurePhase = attrs.configurePhase or ''
        runHook preConfigure

        for localDir in npm-packages-offline-cache node_modules; do
          if [[ -d $localDir || -L $localDir ]]; then
            echo "$localDir dir present. Removing."
            rm -rf $localDir
          fi
        done

        # move convent of . to ./deps/${pname}
        mv $PWD $NIX_BUILD_TOP/temp
        mkdir -p "$PWD/deps/${pname}"
        rm -fd "$PWD/deps/${pname}"
        mv $NIX_BUILD_TOP/temp "$PWD/deps/${pname}"
        cd $PWD

        ln -s ${deps}/deps/${pname}/node_modules "deps/${pname}/node_modules"

        cp -r $node_modules node_modules
        chmod -R +w node_modules

        ${linkDirFunction}

        linkDirToDirLinks "$(dirname node_modules/${pname})"
        ln -s "deps/${pname}" "node_modules/${pname}"

        ${workspaceDependencyCopy}

        # Help yarn commands run in other phases find the package
        echo "--cwd deps/${pname}" > .yarnrc
        runHook postConfigure
      '';

      # Replace this phase on frontend packages where only the generated
      # files are an interesting output.
      installPhase = attrs.installPhase or ''
        runHook preInstall

        mkdir -p $out/{bin,libexec/${pname}}
        mv node_modules $out/libexec/${pname}/node_modules
        mv deps $out/libexec/${pname}/deps
        patchShebangs $_

        node ${./binHelper.js} $out/bin $out/libexec/${pname}/node_modules \
             ${lib.concatStringsSep " " publishBinsFor_} \
             | xargs -rn2 bash -c 'chmod +x $0 && ln -sr $0 $1'

        runHook postInstall
      '';

      doDist = true;

      distPhase = attrs.distPhase or ''
        # pack command ignores cwd option
        rm -f .yarnrc
        cd $out/libexec/${pname}/deps/${pname}
        mkdir -p $out/tarballs/
        yarn pack --offline --ignore-scripts --filename $out/tarballs/${baseName}.tgz
      '';

      passthru = {
        inherit pname package packageJSON deps;
        workspaceDependencies = workspaceDependenciesTransitive;
      } // (attrs.passthru or {});

      meta = {
        inherit (nodejs.meta) platforms;
        description = packageJSON.description or "";
        homepage = packageJSON.homepage or "";
        version = packageJSON.version or "";
        license = if packageJSON ? license then spdxLicense packageJSON.license else "";
      } // (attrs.meta or {});
    });
}
