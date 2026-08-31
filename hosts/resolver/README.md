# Resolver Bootstrap

`resolver` is the Technitium primary node. `mitm` will join as the secondary,
and firewall Unbound remains the canonical source for `guildedthorn.arpa`.

Do not advertise either Technitium address through DHCP until this procedure
passes from LAN, OPT1, and WireGuard.

1. Provision VM 118 with `thornix-provision resolver` on `mac`.
2. Retrieve the generated root-only administrator password from VM 118 and
   open `https://resolver.guildedthorn.arpa/`. Nginx terminates a ThornCloud
   ACME certificate; Technitium's self-signed port 53443 is cluster-only.
3. The initialized cluster is `dns-cluster.guildedthorn.arpa`; resolver
   advertises primary address `172.16.25.66`.
4. After deploying `mitm`, change its one-time default password and join it as
   secondary address `172.16.25.2` using resolver's HTTPS URL.
5. The clustered conditional forwarder zone sends `guildedthorn.arpa` to
   firewall Unbound at `172.16.25.1`.
6. Leave global forwarders empty so both Technitium nodes recurse independently.
7. Verify public DNS, known internal records, NXDOMAIN for unknown internal
   names, and resolution with either Technitium service stopped.

After validation, update Kea to advertise `172.16.25.66` and `172.16.25.2`.
Unbound may then forward public queries to both Technitium nodes with
`forward-first: yes`, preserving direct recursion as its final fallback.
