# ThornixOS security workflow

The production path is:

```text
Grafana critical security rule
  -> loopback-only thorn-security-relay on SOC
  -> extract IP/domain/URL/hash observables
  -> enrich public observables through Oracle/OpenCTI
  -> create one idempotent alert in Casebook/TheHive
  -> keep the existing Discord page
```

Only alerts labeled both `severity=critical` and `category=security` enter
Casebook. Operational failures remain in Discord. Grafana HMAC-signs the raw
body and a timestamp; the loopback relay rejects tampering and replays older
than five minutes. Resolved notifications are disabled because a detection
stopping is not evidence that an incident has been investigated. TheHive's
`sourceRef` and the relay's persistent state prevent hourly Grafana reminders
from creating duplicates.

## One-time activation

1. In TheHive, activate a valid license using **Platform management -> License
   -> Update the current license** and StrangeBee's challenge-response portal.
   The default trial becomes read-only when it expires; there is no safe local
   configuration switch that replaces this license. The least-privilege custom
   profile in step 2 requires Gold or Platinum according to StrangeBee's profile
   documentation:
   <https://docs.strangebee.com/thehive/administration/profiles/create-a-profile/>.
   A free Community license keeps TheHive writable, but its built-in Analyst
   profile grants the relay more authority than `manageAlert/create`; do not
   assume a profile created during the Platinum trial remains available after a
   Community cutover.

2. In TheHive's operational organization, create an organization profile named
   `SOC-Alert-Writer` with only `manageAlert/create`. Create a **Service** account
   named `thornix-siem`, assign that profile, generate its API key, and save the
   key directly to a mode-0600 local file. Do not paste it into chat or a shell
   command line.

3. In OpenCTI, create a role with only knowledge-read access and **Allow token
   usage**, attach it through a dedicated group to a service account named
   `thornix-siem-enrichment`, and save its API token directly to a mode-0600
   local file.

4. Generate an independent webhook authentication key and encrypt all three
   files into SOC's existing SOPS document:

```bash
sops set --value-file hosts/soc/secrets.yaml \
  '["thehive_alert_writer_api_key"]' /path/to/thehive-api-key

sops set --value-file hosts/soc/secrets.yaml \
  '["opencti_enrichment_reader_token"]' /path/to/opencti-api-token

umask 077
openssl rand -hex 32 > /path/to/grafana-security-webhook-hmac
sops set --value-file hosts/soc/secrets.yaml \
  '["grafana_security_webhook_hmac"]' /path/to/grafana-security-webhook-hmac

cp hosts/soc/security-workflow.nix.example hosts/soc/security-workflow.nix
```

The marker must be committed in the same commit as the encrypted secrets. Hydra
then evaluates the relay tests, and the production promotion enables the
Grafana contact point and systemd service atomically.

## Verification

After SOC deploys:

```bash
systemctl status thorn-security-relay.service
curl --fail http://127.0.0.1:9088/health
curl --fail http://127.0.0.1:9088/metrics
```

Use Grafana's **Alerting -> Contact points -> security-casebook -> Test** with a
payload carrying `severity=critical` and `category=security`. Confirm one alert
appears in TheHive with extracted observables and an OpenCTI enrichment section.
Sending the same fingerprint again must increment the duplicate counter without
creating another TheHive alert.
