{
  vmid = 116;
  address = "172.16.25.64";
  isoLabel = "THORNIX_COURIER";
  diskSerial = "THORNIX_COURIER_116";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    diskGiB = 80;
  };

  readiness = {
    displayName = "Courier";
    label = "Courier Stalwart mail and collaboration server";
    timeoutSeconds = 1800;
    units = [ "stalwart.service" ];
    readyLines = [
      "Courier bootstrap is available only through an SSH tunnel."
      "Run: ssh -L 8080:127.0.0.1:8080 root@172.16.25.64"
      "Then open http://127.0.0.1:8080/admin and use 'courier-bootstrap-password' for the temporary admin credential."
      "Keep automatic public TLS disabled during bootstrap; Courier is internal-only until its public mail prerequisites are configured."
    ];
  };
}
