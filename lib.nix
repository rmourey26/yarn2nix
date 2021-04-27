{ lib ? import <nixpkgs/lib> }:

let

  inherit (builtins)
    typeOf length readFile filter foldl' tail head elemAt fromJSON
    replaceStrings substring stringLength;

  inherit (lib)
    all isString flip forEach id importJSON pipe hasPrefix reverseList last take
    mapAttrsToList concatStringsSep optional;

in rec {
  compose = f: g: x: f (g x);
  composeAll = foldl' compose id;

  unescape = fromJSON;

  # only unescape if quoted being lazy here since input is generated
  maybeUnescape = str: if (hasPrefix "\"" str) then fromJSON str else str;

  # Remove last character in a string
  # i.e.: chop "farm"
  # => "far"
  chop = str: substring 0 ((stringLength str) - 1) str;

  # split "/" "/usr/local/bin" -> [ "usr" "local" "bin" ]
  split = separator: flip pipe [
    (builtins.split separator) # -> [ "usr" [ ... ] "local" [ ... ] "bin" ]
    (filter isString)          # -> [ "usr" "local" "bin" ] 👍
  ];

  urlToName = url:
  pipe url [
    (if hasPrefix "git+" url then
      baseNameOf
    else
      flip pipe [
        (split "/")
        reverseList
        (take 4)
        reverseList
        (xs: if (hasPrefix "@" (head xs)) then xs else tail xs)
        (concatStringsSep "_")
      ])
    (replaceStrings ["@" "-"] ["_" "_"])];

  fixupYarnLock = flip pipe [
    readFile
    (split "\n")
    (map (line:
      if hasPrefix "  resolved " line then 
        pipe line [
          (split " ")
          last
          fromJSON
          (split "#")
          (x: "  resolved \"${urlToName (elemAt x 0)}#${elemAt x 1}\"")]
        else line))
    (concatStringsSep "\n")];

  yarnLockToFetchables = { yarnLock, refHints ? {}, defaultRef ? "master" }:
  pipe yarnLock [
    readFile
    (split "\n\n")    # double new line works as a separator between chunks, each chunk is a dependency
    tail              # 🥾 # THIS IS AN AUTOGENERATED FILE. ETC
    (map (flip pipe [
      (split "\n")
      (filter (x: x != ""))
      (filter (x: !hasPrefix "  version" x))       # version "1.7.2" 🔫
      (filter (x: !hasPrefix "  dependencies:" x)) # 🔥 
      (filter (x: !hasPrefix "    " x))            # 🧹 tinycolor2 "^1.4.1" etc
      (map (flip pipe [
        (split " ")
        last ]))]))

    (map (chunk: let
      dep      = elemAt chunk 0;
      resolved = elemAt chunk 1;

      refrev = pipe dep [
        chop
        maybeUnescape
        (split "#")
        last ];

      splittedResolved = pipe resolved [
        fromJSON
        (split "#")];

      hash = if length chunk > 2 then elemAt chunk 2 else null;

      depName = pipe dep [
        chop
        maybeUnescape
        (split "@")
        (list: let
          nth = elemAt list;
          first = nth 0;
          second = nth 1;
        in if first == "" then "@${second}" else first)
      ];

      rev = last splittedResolved;
      ref = if (hasPrefix refrev rev) then
        # package.json specified a revision, use defaultRef
        refHints.${depName} or defaultRef
        else
        # it's ref (branch or tag). we're good.
        refrev;

      npmUrl = head splittedResolved;
      nixUrl = pipe npmUrl [
        (split "git\\+")
        last ];

      name = urlToName npmUrl;
      type = if hash == null then "git" else "url";
    in {
      inherit hash rev ref name type;
      url = nixUrl;
    }))
  ];
}
