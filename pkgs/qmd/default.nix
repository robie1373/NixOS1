{ lib
, buildNpmPackage
, fetchurl
, runCommand
, makeWrapper
, nodejs
, python3
, pkg-config
, sqlite
}:

let
  version = "2.1.0";
  tarball = fetchurl {
    url = "https://registry.npmjs.org/@tobilu/qmd/-/qmd-${version}.tgz";
    hash = "sha256-TxsADFudqjb89dBSKNeWb9ffh2B69XL8ozYFl/ZChuY=";
  };
in

buildNpmPackage {
  pname = "qmd";
  inherit version;

  # npm tarballs have a package/ prefix; extract and inject our package-lock.json
  src = runCommand "qmd-${version}-src" { } ''
    mkdir $out
    tar xf ${tarball} --strip-components=1 -C $out
    cp ${./package-lock.json} $out/package-lock.json
  '';

  npmDepsHash = "sha256-Ebr2RNfI3zD5OaWBKhRpl8wgf/j/MkfLRSm4HHLRkV8=";

  # dist/ is pre-compiled TypeScript — skip the build step
  dontBuild = true;

  # better-sqlite3 compiles a native module via node-gyp; needs Python + sqlite headers
  nativeBuildInputs = [ python3 pkg-config sqlite makeWrapper ];
  buildInputs = [ sqlite ];

  # node-llama-cpp's postinstall downloads pre-built LLAMA backends; skip here.
  # They are fetched to ~/.cache/qmd/models/ at runtime on first use.
  env.NODE_LLAMA_CPP_SKIP_DOWNLOAD = "1";

  # Patch: honour QMD_EMBED_MODEL env var in the embed command (bug in 2.1.0:
  # the CLI hardcodes DEFAULT_EMBED_MODEL_URI instead of checking the env var).
  postPatch = ''
    substituteInPlace dist/cli/qmd.js \
      --replace-fail \
        'await vectorIndex(DEFAULT_EMBED_MODEL_URI, !!cli.values.force,' \
        'await vectorIndex(process.env.QMD_EMBED_MODEL ?? DEFAULT_EMBED_MODEL_URI, !!cli.values.force,'
  '';

  # The npm-install-hook wraps bin/qmd (a shell script) using node, which fails.
  # Replace with a wrapper that calls node on the compiled JS entry point directly.
  postInstall = ''
    rm -f $out/bin/qmd
    makeWrapper ${lib.getExe nodejs} $out/bin/qmd \
      --add-flags "$out/lib/node_modules/@tobilu/qmd/dist/cli/qmd.js"
  '';

  meta = {
    description = "Query Markup Documents — local hybrid search for markdown via BM25, vector search, and LLM reranking";
    homepage = "https://github.com/tobi/qmd";
    license = lib.licenses.mit;
    mainProgram = "qmd";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
