{
  config,
  lib,
  pkgs,
  ...
}:
let
  isPrimary = config.networking.hostName == "resolver";
  blockListUrls = [
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/ultimate-onlydomains.txt"
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/tif.mini-onlydomains.txt"
  ];
  blockListUrlsCsv = lib.concatStringsSep "," blockListUrls;
in
{
  systemd.services.technitium-config = {
    description = "Reconcile Technitium DNS settings and internal forwarding";
    wantedBy = [ "multi-user.target" ];
    after = [ "technitium-dns-server.service" ];
    requires = [ "technitium-dns-server.service" ];
    partOf = [ "technitium-dns-server.service" ];
    unitConfig.ConditionPathExists = "/root/technitium-admin-password";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5min";
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

      api=http://127.0.0.1:5380/api
      password=$(</root/technitium-admin-password)
      token=
      for _ in $(seq 1 120); do
        token=$(
          printf 'user=admin&pass=%s' "$password" \
            | curl --fail --silent --show-error \
                --header 'Content-Type: application/x-www-form-urlencoded' \
                --data-binary @- \
                "$api/user/login" \
            | jq --exit-status --raw-output .token
        ) && break
        sleep 2
      done
      [[ -n "$token" ]]

      settings=$(
        curl --fail --silent --show-error \
          --header "Authorization: Bearer $token" \
          "$api/settings/get"
      )

      if ! jq --exit-status '
        .response.enableDnsOverHttp == true
        and .response.dnsOverHttpPort == 8053
        and .response.dnsReverseProxyNetworkACL == ["127.0.0.1"]
      ' <<<"$settings" >/dev/null; then
        curl --fail --silent --show-error \
          --request POST \
          --header "Authorization: Bearer $token" \
          --get "$api/settings/set" \
          --data-urlencode enableDnsOverHttp=true \
          --data-urlencode dnsOverHttpPort=8053 \
          --data-urlencode dnsReverseProxyNetworkACL=127.0.0.1/32 \
          | jq --exit-status '.status == "ok"' >/dev/null
      fi

      ${lib.optionalString isPrimary ''
        if ! jq --exit-status \
          --arg block_list_1 ${lib.escapeShellArg (builtins.elemAt blockListUrls 0)} \
          --arg block_list_2 ${lib.escapeShellArg (builtins.elemAt blockListUrls 1)} '
            .response.dnssecValidation == true
            and .response.recursion == "AllowOnlyForPrivateNetworks"
            and .response.qnameMinimization == true
            and .response.saveCache == true
            and .response.serveStale == true
            and .response.enableBlocking == true
            and .response.allowTxtBlockingReport == true
            and .response.blockingType == "NxDomain"
            and .response.blockingAnswerTtl == 30
            and .response.blockListUrls == [$block_list_1, $block_list_2]
            and .response.blockListUpdateIntervalHours == 24
          ' <<<"$settings" >/dev/null; then
          curl --fail --silent --show-error \
            --request POST \
            --header "Authorization: Bearer $token" \
            --get "$api/settings/set" \
            --data-urlencode dnssecValidation=true \
            --data-urlencode recursion=AllowOnlyForPrivateNetworks \
            --data-urlencode qnameMinimization=true \
            --data-urlencode saveCache=true \
            --data-urlencode serveStale=true \
            --data-urlencode enableBlocking=true \
            --data-urlencode allowTxtBlockingReport=true \
            --data-urlencode blockingType=NxDomain \
            --data-urlencode blockingAnswerTtl=30 \
            --data-urlencode blockListUrls=${lib.escapeShellArg blockListUrlsCsv} \
            --data-urlencode blockListUpdateIntervalHours=24 \
            | jq --exit-status '.status == "ok"' >/dev/null

          curl --fail --silent --show-error \
            --request POST \
            --header "Authorization: Bearer $token" \
            "$api/settings/forceUpdateBlockLists" \
            | jq --exit-status '.status == "ok"' >/dev/null
        fi
      ''}

      zones=$(
        curl --fail --silent --show-error \
          --header "Authorization: Bearer $token" \
          --get "$api/zones/list" \
          --data-urlencode zonesPerPage=100
      )
      zone_type=$(
        jq --raw-output \
          '.response.zones[] | select(.name == "guildedthorn.arpa") | .type' \
          <<<"$zones"
      )

      if [[ -z "$zone_type" ]]; then
        curl --fail --silent --show-error \
          --request POST \
          --header "Authorization: Bearer $token" \
          --get "$api/zone/create" \
          --data-urlencode zone=guildedthorn.arpa \
          --data-urlencode type=Forwarder \
          --data-urlencode initializeForwarder=true \
          --data-urlencode protocol=Udp \
          --data-urlencode forwarder=172.16.25.1 \
          --data-urlencode dnssecValidation=false \
          --data-urlencode proxyType=NoProxy \
          | jq --exit-status '.status == "ok"' >/dev/null
      elif [[ "$zone_type" != Forwarder ]]; then
        echo "guildedthorn.arpa has unexpected zone type: $zone_type" >&2
        exit 1
      else
        records=$(
          curl --fail --silent --show-error \
            --header "Authorization: Bearer $token" \
            --get "$api/zones/records/get" \
            --data-urlencode zone=guildedthorn.arpa \
            --data-urlencode domain=guildedthorn.arpa
        )
        forwarder_count=$(
          jq '[.response.records[] | select(.type == "FWD")] | length' \
            <<<"$records"
        )
        if [[ "$forwarder_count" != 1 ]]; then
          echo "guildedthorn.arpa must contain exactly one FWD record" >&2
          exit 1
        fi

        forwarder=$(
          jq --compact-output \
            '.response.records[] | select(.type == "FWD") | .rData' \
            <<<"$records"
        )
        if ! jq --exit-status '
          .protocol == "Udp"
          and .forwarder == "172.16.25.1"
          and .priority == 0
          and .dnssecValidation == false
          and .proxyType == "NoProxy"
        ' <<<"$forwarder" >/dev/null; then
          protocol=$(jq --raw-output .protocol <<<"$forwarder")
          address=$(jq --raw-output .forwarder <<<"$forwarder")
          priority=$(jq --raw-output .priority <<<"$forwarder")
          dnssec=$(jq --raw-output .dnssecValidation <<<"$forwarder")
          proxy=$(jq --raw-output .proxyType <<<"$forwarder")

          curl --fail --silent --show-error \
            --request POST \
            --header "Authorization: Bearer $token" \
            --get "$api/zones/records/update" \
            --data-urlencode zone=guildedthorn.arpa \
            --data-urlencode domain=guildedthorn.arpa \
            --data-urlencode type=FWD \
            --data-urlencode protocol="$protocol" \
            --data-urlencode forwarder="$address" \
            --data-urlencode priority="$priority" \
            --data-urlencode dnssecValidation="$dnssec" \
            --data-urlencode proxyType="$proxy" \
            --data-urlencode newProtocol=Udp \
            --data-urlencode newForwarder=172.16.25.1 \
            --data-urlencode newPriority=0 \
            --data-urlencode newDnssecValidation=false \
            --data-urlencode newProxyType=NoProxy \
            | jq --exit-status '.status == "ok"' >/dev/null
        fi
      fi
    '';
  };
}
