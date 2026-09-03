{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  fleetInventory = import ../inventory.nix;
  serviceCatalog = import ../service-catalog.nix;
  securityWorkflowReady = builtins.pathExists "${inputs.self}/hosts/soc/security-workflow.nix";
in
let
  # SeaweedFS S3 gateway on the NAS. Loki keeps only its WAL and
  # caches on the VM disk; all chunk/index storage lives in the
  # `loki` bucket, so this VM is rebuildable without data loss.
  seaweedfsS3 = "truenas.guildedthorn.arpa:30304";

  # Probe the services users and the monitoring stack actually depend
  # on, from the same network vantage point as soc. `http_alive`
  # deliberately accepts auth responses: a 401/403 from S3 proves the
  # TLS listener and application are alive, while a 5xx still fails.
  blackboxConfig = pkgs.writeText "blackbox-exporter.yml" ''
    modules:
      http_alive:
        prober: http
        timeout: 10s
        http:
          preferred_ip_protocol: ip4
          follow_redirects: true
          valid_status_codes: [200, 204, 301, 302, 401, 403]
          tls_config:
            ca_file: ${config.security.pki.caBundle}
  '';

  telemetryServerCertificate = "${inputs.self}/certs/soc.guildedthorn.arpa.crt";
  telemetryServerKey = config.sops.secrets.grafana_tls_key.path;
  # A host can belong to production before it is physically present.
  # Its inventory readiness files keep staged machines out of scrape,
  # probe, canary, and missing-log rules until telemetry enrollment is
  # committed alongside the installed SSH host key.
  monitoringReady =
    name:
    let
      host = fleetInventory.${name};
    in
    builtins.all (path: builtins.pathExists "${inputs.self}/${path}") host.monitoring.readyFiles;
  monitoredNames = lib.filter (
    name: fleetInventory.${name}.monitoring.mode == "scrape" && monitoringReady name
  ) (builtins.attrNames fleetInventory);
  monitoredServiceCatalog = lib.filter (
    service:
    let
      inventoryHost = service.inventoryHost or null;
    in
    inventoryHost == null || builtins.elem inventoryHost monitoredNames
  ) serviceCatalog;
  blackboxServiceTargets = map (service: {
    targets = [ service.probeUrl ];
    labels = {
      service_host = service.host;
      service_icon = service.icon;
      service_id = service.id;
      service_launchable = if service.launchUrl == "" then "false" else "true";
      service_name = service.name;
      service_role = service.role;
      service_url = service.launchUrl;
    };
  }) monitoredServiceCatalog;
  houndTelemetryReady = monitoringReady "hound";
  heraldTelemetryReady = monitoringReady "herald";
  lureTelemetryReady = monitoringReady "lure";
  loomTelemetryReady = monitoringReady "loom";

  # Both public telemetry ports use the same server identity and
  # ThornCloud_CA client trust. The per-location CN checks below
  # reduce each certificate to its intended read or write role.
  telemetryVhost = port: {
    serverName = "soc.guildedthorn.arpa";
    # `onlySSL` also tells the NixOS nginx module to emit the
    # certificate directives when an explicit SSL listen is used.
    onlySSL = true;
    listen = [
      {
        addr = "0.0.0.0";
        inherit port;
        ssl = true;
      }
    ];
    sslCertificate = telemetryServerCertificate;
    sslCertificateKey = telemetryServerKey;
    extraConfig = ''
      ssl_client_certificate ${inputs.self}/certs/ThornCloud_CA.crt;
      ssl_verify_client on;
      ssl_verify_depth 1;

      client_max_body_size 32m;

      allow 172.16.25.0/24;
      allow 192.168.1.6;
      allow 10.10.10.4/31;
      deny all;
    '';
  };

  writerOnly = ''
    if ($ssl_client_s_dn !~ "(^|,)CN=thornix-telemetry-writer(,|$)") {
      return 403;
    }
    if ($request_method != POST) {
      return 405;
    }
  '';

  readerOnly = ''
    if ($ssl_client_s_dn !~ "(^|,)CN=thornix-telemetry-reader(,|$)") {
      return 403;
    }
    if ($request_method !~ "^(GET|POST)$") {
      return 405;
    }
  '';

  fleet = map (
    name:
    let
      host = fleetInventory.${name};
    in
    {
      deploymentEnabled = host.deployment.enable;
      journalHost = name;
      metricsHost = host.fqdn;
      shipsJournal = host.monitoring.journal;
    }
  ) monitoredNames;
  fleetJournalHosts = map (host: host.journalHost) (lib.filter (host: host.shipsJournal) fleet);
  cominFleet = lib.filter (host: host.deploymentEnabled) fleet;
  fleetNodeMetricsTargets = map (host: "${host.metricsHost}:9100") fleet;
  fleetCominMetricsTargets = map (host: "${host.metricsHost}:4243") cominFleet;
  escapePrometheusRegex = value: builtins.replaceStrings [ "." ] [ "[.]" ] value;
  cominFetchInstanceRegex = lib.concatStringsSep "|" (
    map (host: escapePrometheusRegex "${host.metricsHost}:4243") cominFleet
  );
  # These endpoints intentionally use Anvil's 24-hour leaves. Keep
  # them out of the public 21/7-day expiry bands and instead alert
  # when automatic ACME renewal leaves less than four hours.
  internalAcmeProbeRegex = "https://(anvil|atlas|sieve|hound|casebook|oracle|forge|loom|herald|courier|mitm|vault|search|feeds)[.]guildedthorn[.]arpa/.*";

  # Hosts running services-canary — i.e. those with
  # thorn.audit.execScope = "all", where a systemd-timer process is
  # actually visible to the execve rule. Desktops are deliberately
  # absent: under the "sessions" scope the canary would never be
  # recorded, and they generate continuous real user exec activity
  # anyway, which is its own liveness signal.
  canaryHosts = lib.filter (name: fleetInventory.${name}.monitoring.canary) monitoredNames;
in
{
  _module.args.socMonitoring = {
    inherit
      blackboxConfig
      blackboxServiceTargets
      canaryHosts
      cominFetchInstanceRegex
      fleet
      fleetJournalHosts
      fleetCominMetricsTargets
      fleetNodeMetricsTargets
      heraldTelemetryReady
      houndTelemetryReady
      internalAcmeProbeRegex
      loomTelemetryReady
      lureTelemetryReady
      readerOnly
      seaweedfsS3
      securityWorkflowReady
      telemetryServerCertificate
      telemetryServerKey
      telemetryVhost
      writerOnly
      ;
  };
}
