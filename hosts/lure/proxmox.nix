{
  vmid = 110;
  address = "172.16.25.58";
  isoLabel = "THORNIX_LURE";
  diskSerial = "THORNIX_LURE_110";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 1;
    memoryMiB = 2048;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Lure";
    label = "Lure OpenCanary internal deception sensor";
    timeoutSeconds = 1200;
    units = [
      "docker.service"
      "lure-opencanary.service"
      "lure-opencanary-health.timer"
    ];
    readyLines = [
      "Lure is listening on its declared decoy ports at 172.16.25.58."
      "There is intentionally no administration web UI."
      "Add a pfSense host override for lure.guildedthorn.arpa -> 172.16.25.58."
    ];
  };
}
