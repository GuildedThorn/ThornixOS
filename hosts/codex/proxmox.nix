{
  vmid = 119;
  address = "172.16.25.67";
  isoLabel = "THORNIX_CODEX";
  diskSerial = "THORNIX_CODEX_119";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    minimumMemoryMiB = 4096;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Codex";
    label = "Codex private search and feed reader";
    timeoutSeconds = 1800;
    units = [
      "codex-news.service"
      "miniflux.service"
      "nginx.service"
      "postgresql.service"
      "uwsgi.service"
    ];
    httpChecks = [
      {
        url = "https://search.guildedthorn.arpa/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "search.guildedthorn.arpa:443:172.16.25.67";
        expectPattern = "SearXNG";
      }
      {
        url = "https://feeds.guildedthorn.arpa/healthcheck";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "feeds.guildedthorn.arpa:443:172.16.25.67";
        expectPattern = "OK";
      }
    ];
    readyLines = [
      "Search: https://search.guildedthorn.arpa/"
      "Feeds: https://feeds.guildedthorn.arpa/"
      "Run 'codex-initial-password' as root for the initial Miniflux login."
    ];
  };
}
