# Loom starter workflows

These workflows are imported once, inactive, after the n8n owner account
exists. Each JSON file has its own marker under `/var/lib/loom-n8n-seed`, so a
later deployment can add a new workflow without overwriting edits made in the
n8n UI.

| Workflow | Purpose |
| --- | --- |
| `ThornixOS \| Fleet health → Herald` | Probes the service tier every five minutes, requires two failed polls, and reports recovery. |
| `ThornixOS \| Hydra production gate → Herald` | Reports one pass/fail result for each completed Hydra production evaluation. |
| `ThornixOS \| n8n failures → Herald` | Shared Error Trigger workflow referenced by scheduled Loom automations. |
| `Thorn \| Evening drop` | Sends a daily GuildedThorn-styled dashboard covering aggregate home-ops health, Hydra production, Alsip weather, and selected gaming feeds. |
| `ThornixOS \| Threat news ↔ SOC correlation` | Uses two local models to extract threat keys and independently review bounded Loki/OpenCTI evidence before notifying Herald and Discord. |
| `Thorn \| Morning operator brief` | Sends one actionable daily Discord card covering fleet, storage, backups, certificates, deployment, Hydra, and aggregate 24-hour security activity. |
| `ThornixOS \| Weekly maintenance queue` | Turns the same bounded telemetry into an ordered Sunday maintenance checklist and seven-day security pulse. |
| `ThornixOS \| Change window preflight` | Produces a manual GO/CAUTION/NO-GO decision before a fleet rollout from live SOC and Hydra evidence. |

## Operator workflow suite

The operator workflows call `POST /api/v1/ops-summary` on SOC. The request may
select only `24h` or `7d`; it cannot contain PromQL, LogQL, credentials, host
commands, or remediation instructions. SOC runs fixed local queries and returns
bounded aggregate state for node reachability, failed units, root-disk and
memory pressure, blackbox service/TLS probes, backup timers, comin deployment
state, and six security-event counters. Raw logs, alert bodies, IP addresses,
and backend credentials remain on SOC.

- `Morning operator brief` runs at 7:15 AM and always sends one Discord card.
- `Weekly maintenance queue` runs Sunday at 10:00 AM and orders the current
  repair, cleanup, renewal, drift, and reboot work.
- `Change window preflight` is manual-only and blocks GO on incomplete Hydra
  production jobs or unsafe live-fleet conditions. It never deploys anything.

All three import inactive. Select **GuildedThorn Gaming Drop Discord** on their
Discord nodes, test manually, and publish only the two scheduled workflows.

## Threat-news correlation

This workflow is intentionally inactive on import. It runs every six hours once
published and processes at most three previously unseen articles from the official
Microsoft Security and Google Threat Intelligence feeds. The pipeline is:

```text
public RSS summaries
  -> llama3.2:3b entity extraction on nixos
  -> fixed, bounded SOC Loki + OpenCTI lookup
  -> deepseek-r1:1.5b independent evidence review on nixos
  -> deterministic evidence/confidence gate
  -> Herald + mention-safe Discord embed only when the gate passes
```

Deploy `nixos` before enabling it: Ollama remains loopback-only, while nginx
publishes only `POST /api/chat` and `GET /api/tags` on port 11435. Both the host
firewall and nginx admit only Loom (`172.16.25.62`); model-management endpoints
are not reachable. The gateway is plaintext inside the routed ThornCloud LAN,
so it must never be opened to another network.

Deploy `soc` as well. Its TLS listener on port 9443 admits only Loom and exposes
only purpose-built POST endpoints. The news relay validates at most eight high-signal
actor/campaign/malware/CVE/ATT&CK/IOC terms, builds its own fixed LogQL query,
searches only the last 30 days, returns at most 40 short excerpts, and performs
read-only OpenCTI searches using the existing SOC service identity. Loom never
receives a Loki query credential or OpenCTI token.

Article text is capped and marked as untrusted in both prompts. Model output is
schema-constrained, validated again in n8n and on SOC, and cannot provide LogQL
or GraphQL. A notification requires actual returned evidence, a term confirmed
by both the reviewer and the SOC response, and reviewer confidence of at least
72 percent. This is a prioritization aid, not an attribution or containment
authority; it cannot create a TheHive case or change any security control.

After all three hosts are on the new generation, select the existing **Herald
ntfy publisher** credential on `Notify Herald` and **GuildedThorn Gaming Drop
Discord** on `Discord threat finding`. Discord receives the public report title,
model assessment, and aggregate evidence counts, but never raw SIEM excerpts.
Run `Test threat correlation`, inspect the model and SOC payloads, then publish
the workflow.

## Personal Gmail credential

The evening drop is imported without a credential and remains inactive. Create
a dedicated Google app password for Loom; do not reuse another machine's app
password or commit it to this repository.

In n8n:

1. Create an **SMTP** credential named `GuildedThorn Gmail SMTP`.
2. Set the user to `guildedthorn@gmail.com` and the password to the dedicated
   Google app password.
3. Set the host to `smtp.gmail.com`, port to `465`, and enable SSL/TLS.
4. Select that credential on the `Email Thorn` node.
5. Run `Test tonight's drop` once and inspect the received email, then publish
   the workflow. Its configured timezone is `America/Chicago` and it runs at
   5:30 PM daily.

The workflow reads public feeds, Open-Meteo, internal HTTPS readiness endpoints,
and Forge's read-only Hydra JSON API. E-mail and Discord receive only aggregate
reachability and build counts, a short revision, and dashboard links. Raw SIEM
alerts, log lines, IP addresses, credentials, and response bodies are never
included. The workflow uses no AI service and includes no tracking pixel.

Detailed Loki and Prometheus statistics remain behind SOC's read-only mTLS
boundary. Give Loom a dedicated reader identity before adding those queries;
do not copy the workstation reader key or repurpose a telemetry writer key.

## Personal Discord credential

The evening drop can also send a mention-safe Discord embed with bounded
security/fleet, production, weather, gaming-news, and video fields. Its color
changes when an aggregate operational check is degraded. In n8n, create a
**Discord Webhook** credential named
`GuildedThorn Gaming Drop Discord`, paste the private webhook URL, and select it
on the `Discord evening drop` node. Keep the webhook URL in n8n's encrypted
credential store; never add it to the workflow JSON or this repository.

## Herald credential

After Herald is online, create a dedicated user with write-only access to the
operations topic. Run these commands on Herald as root:

```console
sudo -u ntfy-sh ntfy user add loom
sudo -u ntfy-sh ntfy access loom thornixos-ops write-only
sudo -u ntfy-sh ntfy token add --label=loom-n8n loom
```

Use a random password at the first prompt; n8n uses only the resulting token.
Do not commit the token.

In n8n:

1. Create a **Bearer Auth** credential named `Herald ntfy publisher` and paste
   only the `tk_...` token.
2. Select that credential on the `Notify Herald` node in all three workflows.
3. Subscribe to `thornixos-ops` in Herald as the `thorn` administrator.
4. Test the error workflow first, then manually test fleet health and Hydra.
5. Publish the two scheduled workflows. The error workflow is invoked through
   each parent workflow's preconfigured `errorWorkflow` setting.

The critical SOC alert path remains Grafana/Loki/OpenCanary/Suricata → the
HMAC-authenticated SOC relay → OpenCTI → TheHive. Loom observes automation and
deployment health; it is not part of that security-critical delivery path.
