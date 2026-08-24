{
  autoPatchelfHook,
  fetchFromGitHub,
  fetchPypi,
  lib,
  python313Packages,
  stdenv,
}:

let
  ps = python313Packages;

  websockets12 = ps.buildPythonPackage rec {
    pname = "websockets";
    version = "12.0";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-gd+cvLtsJg3h4AfljAEb/r4tr8hDUQewU385PdOMixs=";
    };

    build-system = [ ps.setuptools ];
    doCheck = false;
    pythonImportsCheck = [ "websockets" ];

    meta = {
      description = "WebSocket implementation for Python";
      homepage = "https://websockets.readthedocs.io/";
      license = lib.licenses.bsd3;
    };
  };

  pymicroFeatures = ps.buildPythonPackage rec {
    pname = "pymicro-features";
    version = "2.0.2";
    pyproject = true;

    src = fetchPypi {
      pname = "pymicro_features";
      inherit version;
      hash = "sha256-DQvteEPseLbO2C0aLc3etP5d9hs6+AooHQhoyOJ5xyc=";
    };

    build-system = [
      ps.setuptools
      ps.wheel
    ];
    doCheck = false;
    pythonImportsCheck = [ "pymicro_features" ];

    meta = {
      description = "TFLite Micro-compatible speech feature extraction";
      homepage = "https://github.com/OHF-Voice/pymicro-features";
      license = lib.licenses.asl20;
      platforms = lib.platforms.linux;
    };
  };

  pymicroWakeword = ps.buildPythonPackage rec {
    pname = "pymicro-wakeword";
    version = "2.4.1";
    pyproject = true;

    src = fetchPypi {
      pname = "pymicro_wakeword";
      inherit version;
      hash = "sha256-QyuKLhpvuJ2Rad3b2luognr2lH56t6DrGp2y7399Y14=";
    };

    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
    build-system = [ ps.setuptools ];
    dependencies = [
      ps.numpy
      pymicroFeatures
    ];
    doCheck = false;
    pythonImportsCheck = [ "pymicro_wakeword" ];

    meta = {
      description = "Local microWakeWord inference for Python";
      homepage = "https://github.com/OHF-Voice/pymicro-wakeword";
      license = lib.licenses.asl20;
      platforms = [ "x86_64-linux" ];
    };
  };
in
ps.buildPythonApplication rec {
  pname = "linux-voice-assistant";
  version = "0.0.0+adcef575";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "OHF-Voice";
    repo = "linux-voice-assistant";
    rev = "adcef575b714b469b3437aec13b388d3cf0bb22f";
    hash = "sha256-nRAP/9NATqiSK9JHvjHmxTuFOyD9Cq+ZeH94zNWhSKk=";
  };

  SETUPTOOLS_SCM_PRETEND_VERSION = version;

  postPatch = ''
    substituteInPlace version.txt \
      --replace-fail placeholder ${version}
  '';

  build-system = [
    ps.setuptools
    ps.setuptools-scm
    ps.wheel
  ];

  dependencies = [
    ps.aioesphomeapi
    ps.getmac
    ps.mpv
    ps.netifaces2
    ps.numpy
    ps.pyopen-wakeword
    ps.soundcard
    ps.types-protobuf
    ps.webrtc-noise-gain
    ps.zeroconf
    pymicroWakeword
    websockets12
  ];

  # nixpkgs packages the python-mpv distribution as `mpv`; the import and
  # runtime library are still supplied by ps.mpv above.
  pythonRemoveDeps = [ "python-mpv" ];

  postInstall = ''
    resource_dir="$out/${ps.python.sitePackages}"
    cp -R wakewords sounds "$resource_dir/"
    install -Dm0444 version.txt "$resource_dir/version.txt"
  '';

  doCheck = false;
  pythonImportsCheck = [ "linux_voice_assistant" ];

  passthru = {
    inherit pymicroFeatures pymicroWakeword websockets12;
    resourcePath = "${ps.python.sitePackages}";
  };

  meta = {
    description = "Linux voice assistant for Home Assistant using the ESPHome protocol";
    homepage = "https://github.com/OHF-Voice/linux-voice-assistant";
    license = lib.licenses.asl20;
    mainProgram = "linux-voice-assistant";
    platforms = [ "x86_64-linux" ];
  };
}
