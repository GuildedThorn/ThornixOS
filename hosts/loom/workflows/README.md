# Loom starter workflows

These workflows are imported once, inactive, after the n8n owner account
exists. Each JSON file has its own marker under `/var/lib/loom-n8n-seed`, so a
later deployment can add a new workflow without overwriting edits made in the
n8n UI.

| Workflow | Purpose |
| --- | --- |
| `ThornixOS \| Fleet health → Herald` | Probes the service tier every five minutes, requires two failed polls, and reports recovery. |
| `ThornixOS \| Hydra production gate → Herald` | Reports one pass/fail result for each completed Hydra production evaluation. |
| `ThornixOS \| n8n failures → Herald` | Shared Error Trigger workflow referenced by the two scheduled workflows. |
| `Thorn \| Evening gaming drop` | Emails Thorn a daily GuildedThorn-styled digest of Alsip weather, selected gaming channels, and gaming news. |

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

The workflow reads public feeds and Open-Meteo only. It sends no infrastructure
data, uses no AI service, and includes no tracking pixel.

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
