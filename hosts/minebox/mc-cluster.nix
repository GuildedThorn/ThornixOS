# Minebox is the first minecraft cluster node: k3s server + Agones game fleets.
# Future OptiPlexes join as `k3s.role = "agent"` with a sops-backed join token.
{ ... }:
{
  thorn.mc-cluster = {
    enable = true;
    environment = "prod";
    k3s = {
      role = "server";
      nodeIp = "172.16.25.102";
    };
  };
}
