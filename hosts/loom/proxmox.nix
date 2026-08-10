{
  vmid = 114;
  address = "172.16.25.62";
  isoLabel = "THORNIX_LOOM";
  diskSerial = "THORNIX_LOOM_114";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Loom";
    label = "Loom n8n workflow-automation platform";
    timeoutSeconds = 1800;
    units = [
      "loom-n8n-secrets.service"
      "n8n.service"
      "n8n-task-runner.service"
      "nginx.service"
      "postgresql.service"
    ];
    httpChecks = [
      {
        url = "https://loom.guildedthorn.arpa/healthz";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "loom.guildedthorn.arpa:443:172.16.25.62";
      }
    ];
    readyLines = [
      "Loom: https://loom.guildedthorn.arpa/"
      "Add a pfSense host override for loom.guildedthorn.arpa -> 172.16.25.62."
      "Open Loom in a trusted browser and create the first n8n owner account."
    ];
  };
}
