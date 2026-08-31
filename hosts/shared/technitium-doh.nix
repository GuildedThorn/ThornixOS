{ pkgs, ... }:
{
  systemd.services.technitium-doh-config = {
    description = "Reconcile Technitium DNS-over-HTTPS settings";
    wantedBy = [ "technitium-dns-server.service" ];
    after = [ "technitium-dns-server.service" ];
    requires = [ "technitium-dns-server.service" ];
    partOf = [ "technitium-dns-server.service" ];
    unitConfig.ConditionPathExists = "/root/technitium-admin-password";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = "read-only";
      ProtectSystem = "strict";
    };
    path = with pkgs; [
      coreutils
      curl
      jq
    ];
    script = ''
      set -o errexit -o nounset -o pipefail

      password=$(</root/technitium-admin-password)
      token=
      for _ in $(seq 1 120); do
        token=$(
          printf 'user=admin&pass=%s' "$password" \
            | curl --fail --silent --show-error \
                --header 'Content-Type: application/x-www-form-urlencoded' \
                --data-binary @- \
                http://127.0.0.1:5380/api/user/login \
            | jq --exit-status --raw-output .token
        ) && break
        sleep 2
      done
      [[ -n "$token" ]]

      curl --fail --silent --show-error \
        --request POST \
        --header "Authorization: Bearer $token" \
        --get http://127.0.0.1:5380/api/settings/set \
        --data-urlencode enableDnsOverHttp=true \
        --data-urlencode dnsOverHttpPort=8053 \
        --data-urlencode dnsReverseProxyNetworkACL=127.0.0.1/32 \
        | jq --exit-status '.status == "ok"' >/dev/null
    '';
  };
}
