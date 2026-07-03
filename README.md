# ThornixOS
my nix config, dont mind the name, a friend thought it was funny

## Secrets (sops)

Secrets are encrypted with [sops](https://github.com/getsops/sops) /
[sops-nix](https://github.com/Mic92/sops-nix) and committed to the repo as
ciphertext. Recipients are declared per-file in `.sops.yaml`:

- **My GPG key** (YubiKey-backed) — lets me edit any secrets file from my
  workstation. Decrypting/re-encrypting prompts for the YubiKey PIN.
- **Each host's own age key**, derived from its SSH host key
  (`/etc/ssh/ssh_host_ed25519_key`) via `ssh-to-age`. Lets `sops-nix` decrypt
  unattended during system activation — no YubiKey needed on the host.

`sops` and `ssh-to-age` are in every host's system packages
(`modules/core/base.nix`). If you're on a machine that hasn't been rebuilt
yet, use `nix shell nixpkgs#sops nixpkgs#ssh-to-age` instead.

### Editing an existing secrets file

```sh
sops hosts/<host>/secrets.yaml
```

Opens `$EDITOR` on the decrypted contents; saving re-encrypts to all
recipients configured for that path in `.sops.yaml`.

### Adding a new secret to a host that already has one

1. `sops hosts/<host>/secrets.yaml` and add the key.
2. Declare it in `hosts/<host>/secrets.nix`:
   ```nix
   sops.secrets.my_new_secret = { };
   ```
3. Rebuild. It shows up at `/run/secrets/my_new_secret`, owned by root:root
   0400 by default — use `sops.secrets.<name>.owner`, `.group`, `.mode`, or
   `.path` to change that, and reference it elsewhere in config via
   `config.sops.secrets.<name>.path`.

### Setting up secrets on a new host

1. Get the host's SSH host public key (from `/etc/ssh/ssh_host_ed25519_key.pub`
   after first boot, or from `hosts/<host>/hardware-configuration.nix`
   provisioning if generated ahead of time), then convert it:
   ```sh
   ssh-to-age -i ssh_host_ed25519_key.pub
   ```
2. Add the resulting `age1...` key to `.sops.yaml` under `keys:`, and add a
   `creation_rules:` entry for `hosts/<host>/secrets\.ya?ml$` listing my `pgp`
   fingerprint and that host's `age` key.
3. Create the encrypted file (plaintext YAML first, then encrypt in place):
   ```sh
   sops --encrypt --in-place hosts/<host>/secrets.yaml
   ```
4. Create `hosts/<host>/secrets.nix` with `sops.defaultSopsFile = ./secrets.yaml;`
   and `sops.secrets.<name> = { };` entries, then add it to that host's module
   list (see `modules/computers/nixos.nix` for the pattern).

### Rotating recipients

After changing `.sops.yaml` (adding/removing a key), re-encrypt affected
files to match:

```sh
sops updatekeys hosts/<host>/secrets.yaml
```

### Recovering after an OS reinstall / host key loss

A wipe generates a brand-new `/etc/ssh/ssh_host_ed25519_key`, so the host's
old age key is gone and it can no longer decrypt its `secrets.yaml`. This
never locks *me* out, though — my GPG key is always a co-recipient, so I can
decrypt from my workstation the whole time. Fix the host's unattended path
once it's back up:

1. Reinstall the host as usual (host key regenerates on first boot).
2. Get the new host age key and swap it into `.sops.yaml`:
   ```sh
   ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
   ```
   Replace the old `age1...` value for that host under `keys:` in `.sops.yaml`.
3. Re-encrypt for the new recipient (run from a machine with my GPG key/YubiKey):
   ```sh
   sops updatekeys hosts/<host>/secrets.yaml
   ```
4. Rebuild the host — `sops-nix` can now decrypt again.

Host private keys are never backed up on purpose — losing one just means a
`updatekeys` round-trip, not a lost secret.
