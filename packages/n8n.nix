{
  stdenv,
  lib,
  nixosTests,
  fetchFromGitHub,
  nodejs,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  python3,
  node-gyp,
  cctools,
  xcbuild,
  libkrb5,
  libmongocrypt,
  libpq,
  sqlite,
  dart-sass,
  makeWrapper,
}:
let
  python = python3.withPackages (
    ps: with ps; [
      websockets
    ]
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "n8n";
  # 2.35.4 is the stable security release fixing
  # GHSA-mwp5-2m32-r54h. Remove this package once the fleet nixpkgs pin
  # carries an equal or newer version.
  version = "2.35.4";

  src = fetchFromGitHub {
    owner = "n8n-io";
    repo = "n8n";
    tag = "n8n@${finalAttrs.version}";
    hash = "sha256-A2whTvIm0rZAo96RNwxBIG1AE+6hWdH8V/LDemFQ/40=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-KhKKr9BXSr93gv+kRPyTLDYRUyQjR1Glp6PeFnHUXNU=";
  };

  nativeBuildInputs = [
    pnpmConfigHook
    pnpm_10
    python3
    node-gyp
    makeWrapper
    dart-sass
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools
    xcbuild
  ];

  buildInputs = [
    nodejs
    libkrb5
    libmongocrypt
    libpq
    sqlite
  ];

  buildPhase = ''
    runHook preBuild

    # Use the packaged compiler instead of sass-embedded's downloaded binary.
    substituteInPlace packages/frontend/editor-ui/node_modules/sass-embedded/dist/lib/src/compiler-path.js \
      --replace-fail 'compilerCommand = (() => {' 'compilerCommand = (() => { return ["${lib.getExe dart-sass}"];'

    pushd packages/cli/node_modules/sqlite3
    npm_config_sqlite=${lib.getDev sqlite} node-gyp rebuild
    popd

    pnpm build --filter=n8n

    runHook postBuild
  '';

  preInstall = ''
    echo "Removing non-deterministic and unnecessary files"

    find -type d -name .turbo -exec rm -rf {} +
    rm node_modules/.modules.yaml
    rm packages/nodes-base/dist/types/nodes.json

    CI=true pnpm --ignore-scripts prune --prod
    find -type f \( -name "*.ts" -o -name "*.map" \) -exec rm -rf {} +
    rm -rf node_modules/.pnpm/{typescript*,prettier*}
    shopt -s globstar
    find node_modules packages/**/node_modules -xtype l -delete

    echo "Removed non-deterministic and unnecessary files"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,lib/n8n}
    cp -r {packages,node_modules} $out/lib/n8n

    makeWrapper $out/lib/n8n/packages/cli/bin/n8n $out/bin/n8n \
      --set N8N_RELEASE_TYPE "stable" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    makeWrapper ${nodejs}/bin/node $out/bin/n8n-task-runner \
      --add-flags "$out/lib/n8n/packages/@n8n/task-runner/dist/start.js"

    mkdir -p $out/lib/n8n-task-runner-python
    cp -r packages/@n8n/task-runner-python/* $out/lib/n8n-task-runner-python/
    makeWrapper ${python}/bin/python $out/bin/n8n-task-runner-python \
      --add-flags "$out/lib/n8n-task-runner-python/src/main.py" \
      --prefix PYTHONPATH : "$out/lib/n8n-task-runner-python"

    runHook postInstall
  '';

  passthru = {
    tests = nixosTests.n8n;
  };

  dontStrip = true;
  dontPatchELF = true;
  dontRewriteSymlinks = true;

  meta = {
    description = "Free and source-available fair-code licensed workflow automation tool";
    homepage = "https://n8n.io";
    changelog = "https://github.com/n8n-io/n8n/releases/tag/n8n@${finalAttrs.version}";
    license = lib.licenses.sustainableUse;
    mainProgram = "n8n";
    platforms = lib.platforms.unix;
  };
})
