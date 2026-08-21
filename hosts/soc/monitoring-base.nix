{ inputs, ... }:
{
  # pfSense cannot run Alloy itself, so its high-priority IDS source
  # addresses are enriched here after rsyslog receives them.
  thorn.geoip.enable = true;

  # Trust the LAN CA so Loki's S3 client can verify the SeaweedFS
  # gateway's certificate.
  security.pki.certificates = [
    (builtins.readFile "${inputs.self}/certs/ThornCloud_CA.crt")
  ];
}
