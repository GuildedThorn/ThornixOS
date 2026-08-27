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
