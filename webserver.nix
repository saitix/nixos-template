{ config, pkgs, ... }:

{
  services.httpd = {
    enable = true;
    adminAddr = "admin@example.com";
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
