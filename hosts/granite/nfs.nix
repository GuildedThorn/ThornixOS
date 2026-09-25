{ ... }:
{
  # Export the existing ZFS dataset. Clients should use NFSv4 with:
  #   172.16.25.4:/platter/media
  services.nfs.server = {
    enable = true;
    exports = ''
      /platter/media 172.16.25.0/24(rw,sync,no_subtree_check) 192.168.1.6/32(rw,sync,no_subtree_check)
    '';
  };

  # NFSv4 uses the single well-known TCP port. Keep the export limited to the
  # local LAN above; root squashing remains enabled by default.
  networking.firewall.allowedTCPPorts = [ 2049 ];
}
