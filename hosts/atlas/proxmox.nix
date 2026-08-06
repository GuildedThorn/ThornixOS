{
  vmid = 106;
  address = "172.16.25.54";
  isoLabel = "THORNIX_ATLAS";
  diskSerial = "THORNIX_ATLAS_106";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Atlas";
    label = "Atlas NetBox stack";
    units = [
      "netbox.service"
      "netbox-rq.service"
      "nginx.service"
      "postgresql.service"
      "redis-netbox.service"
    ];
    # HTTP exists only as a redirect to HTTPS. Checking it proves nginx is
    # online without teaching the provisioner to trust the temporary leaf.
    httpChecks = [ { url = "http://172.16.25.54/login/"; } ];
    readyLines = [
      "Atlas: https://atlas.guildedthorn.arpa/ (temporary certificate until CA enrollment)"
      "Create the first local administrator with:"
      "  ssh -t root@172.16.25.54 netbox-manage createsuperuser"
    ];
  };
}
