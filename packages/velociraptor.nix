{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "velociraptor";
  version = "0.77.1";

  src = fetchurl {
    url = "https://github.com/Velocidex/velociraptor/releases/download/v0.77.1/velociraptor-v0.77.1-linux-amd64-musl";
    hash = "sha256-w54NQCd2VV01yVVd9B1ZAb+38y9Lq6HQZ5XRKGICik8=";
  };

  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -Dm0555 "$src" "$out/bin/velociraptor"
    runHook postInstall
  '';

  meta = {
    description = "Endpoint visibility and digital forensic collection platform";
    homepage = "https://docs.velociraptor.app/";
    license = lib.licenses.agpl3Only;
    mainProgram = "velociraptor";
    platforms = [ "x86_64-linux" ];
  };
}
