{
  vmid = 105;
  address = "172.16.25.53";
  isoLabel = "THORNIX_PIXIE";
  diskSerial = "THORNIX_PIXIE_105";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 2048;
    # A current NixOS/PXE closure and one atomic upgrade need more than the
    # original appliance disk. Match the expanded live VM with safe headroom.
    diskGiB = 40;
  };

  readiness = {
    displayName = "Pixie";
    label = "Pixie HTTP and TFTP";
    units = [
      "nginx.service"
      "atftpd.service"
    ];
    httpChecks = [
      {
        url = "http://172.16.25.53/boot.ipxe";
        expectPattern = "^#!ipxe$";
      }
    ];
    tftpChecks = [ "tftp://172.16.25.53/undionly.kpxe" ];
    readyLines = [
      "Boot menu: http://pixie.guildedthorn.arpa/boot.ipxe"
      "pfSense remains the DHCP authority; configure its PXE next-server as 172.16.25.53."
    ];
  };
}
