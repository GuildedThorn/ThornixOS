# Firewall Cutover

`disko.nix` destroys the pfSense system disk. Before installation, export the
current Kea leases and recover the SSH host-key backup on an administrator
workstation that has the YubiKey-backed PGP identity. The backup's age
recipient is derived from the key being recovered, so the installer cannot
bootstrap the decryption itself.

```sh
umask 077
key_file=$(mktemp)
trap 'shred -u "$key_file"' EXIT
sops --decrypt --extract '["ssh_host_ed25519_key_base64"]' \
  hosts/firewall/secrets.yaml \
  | base64 --decode > "$key_file"
expected=age107ct049vtdxkcyqd50dvkkz94juz0gclxmhsvhdehtllz8m5tpwqxj8k57
actual=$(ssh-keygen -y -f "$key_file" | ssh-to-age)
test "$actual" = "$expected"
```

Keep that shell open so the trap retains and eventually shreds the temporary
key. Shut down pfSense, boot the installer, and confirm the
`firewall-installer` prompt over serial before transferring anything to
`192.168.1.1`:

```sh
scp "$key_file" root@192.168.1.1:/root/firewall-host-key
```

After `nixos-install` creates the target filesystem, install the staged key
before first boot:

```sh
install -Dm600 /root/firewall-host-key /mnt/etc/ssh/ssh_host_ed25519_key
ssh-keygen -y -f /mnt/etc/ssh/ssh_host_ed25519_key \
  > /mnt/etc/ssh/ssh_host_ed25519_key.pub
```

Immediately before shutting pfSense down, stop its DHCP service and copy
`/var/db/kea/dhcp4.leases`. Its `subnet_id` column must contain only `1` and
`2`, matching `networking.nix`:

```sh
awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "subnet_id") n = i; next } { print $n }' \
  dhcp4.leases | sort -nu
```

After `nixos-install` creates target users, install leases with Kea's target
UID/GID before first boot. This preserves clients retaining pfSense leases and
keeps Kea's memfile writable:

```sh
kea_uid=$(awk -F: '$1 == "kea" { print $3 }' /mnt/etc/passwd)
kea_gid=$(awk -F: '$1 == "kea" { print $3 }' /mnt/etc/group)
test -n "$kea_uid" && test -n "$kea_gid"
install -Dm600 -o "$kea_uid" -g "$kea_gid" dhcp4.leases \
  /mnt/var/lib/kea/dhcp4.leases
```

Public port forwards remain disabled. Retired pfSense declarations are noted
in `networking.nix`; validate every target before restoring any DNAT.

## Zone policy

LAN, OPT1, and WireGuard are separate routed trust zones. New cross-zone
connections are denied unless listed in `networking.firewall.extraForwardRules`;
stateful replies and internal-to-WAN egress remain allowed. WireGuard is not a
trusted interface: every peer receives DNS, while only Scout receives the
documented administrative paths.

NixOS automatically accepts traffic carrying conntrack's DNAT status before
the custom zone rules. Keep `networking.nat.forwardPorts` empty unless a public
forward has been separately reviewed; any future DNAT must be treated as an
explicit exception to this zone policy.

The LAN administrator rules match the fixed NixOS workstation and Scout's home
Wi-Fi IP/MAC pairs as defense in depth, not as cryptographic host identity.
Before treating physical LAN administration as a strong security boundary,
place management clients on a dedicated VLAN or switch port with source
binding. OPT1 is also one L2 broadcast domain, so traffic between OPT1 hosts
does not cross this firewall and must be constrained by each host firewall or
by switch ACLs.

Sieve has no permanent forwarding exception into LAN. Add exact targets and
protocols only for an approved scan window, then remove and redeploy the rule.
