{
  vmid = 103;
  address = "172.16.25.51";
  isoLabel = "THORNIX_SOC";
  diskSerial = "THORNIX_SOC_103";
  adminSshKeys = import ./admin-ssh-keys.nix;

  # Match the existing VM 103 hardware so a future clean rebuild does not
  # silently resize the SOC while replacing it.
  resources = {
    cores = 4;
    memoryMiB = 8096;
    diskGiB = 60;
  };

  readiness = {
    displayName = "SOC";
    label = "SOC observability stack";
    units = [
      "alloy.service"
      "grafana.service"
      "loki.service"
      "nginx.service"
      "prometheus.service"
      "prometheus-blackbox-exporter.service"
    ];
    httpChecks = [
      {
        url = "https://soc.guildedthorn.arpa:3000/api/health";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "soc.guildedthorn.arpa:3000:172.16.25.51";
        expectPattern = ''"database"[[:space:]]*:[[:space:]]*"ok"'';
      }
    ];
    readyLines = [
      "Grafana: https://soc.guildedthorn.arpa:3000/"
      "Prometheus and Loki remain available through their existing mTLS endpoints."
    ];
  };
}
