{ ... }:

{
  # sops.secrets entries and the env templates built from them are declared by
  # the modules that consume them; this file only points the module at the
  # encrypted source. See modules/services/hashtopolis-server.nix.
  #
  # The Hashtopolis stack runs alongside Home Assistant and Technitium on this
  # host, so its database password has to be distinct from anything else here.
  thorn.hashtopolisServer.sopsFile = ./secrets.yaml;
}
