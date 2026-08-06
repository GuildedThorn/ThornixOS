{
  vmid = 105;
  address = "172.16.25.53";
  isoLabel = "THORNIX_PIXIE";
  diskSerial = "THORNIX_PIXIE_105";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 2048;
    diskGiB = 20;
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
