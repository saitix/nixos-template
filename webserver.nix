{ config, pkgs, ... }:

let
  # nixpkgs' ioncube-loader package doesn't mark itself as a zend_extension,
  # so withExtensions would emit "extension=..." instead of "zend_extension=...".
  # ionCube itself requires the zend_extension directive (it's a Zend-Engine
  # extension, not a regular module) - override the derivation to fix that.
  ioncubeZend = pkgs.php85Extensions.ioncube-loader.overrideAttrs (old: {
    zendExtension = true;
  });

  # withExtensions passes an attrset { enabled, all }; `enabled` is the default
  # extension list and `all` is the full set of available extensions.
  # Keep the defaults and append ionCube (and any others) from `all`.
  phpWithIoncube = pkgs.php85.withExtensions ({ enabled, all }:
    enabled ++ [
      ioncubeZend
      # add other extensions you need, e.g. all.curl, all.opcache, ...
    ]);
in
{
  ###########################################################################
  # webserver
  services.httpd = {
    enable = true;
    adminAddr = "admin@example.com";

    # mod_proxy_fcgi isn't loaded by default; it's required for the
    # SetHandler "proxy:unix:..." directive below to actually forward
    # .php requests to PHP-FPM instead of serving them as static files.
    extraModules = [ "proxy_fcgi" ];

    # Example vhost
    virtualHosts."example.local" = {
      documentRoot = "/var/www/example";
      extraConfig = ''
        <FilesMatch "\.php$">
          SetHandler "proxy:unix:/run/phpfpm/example.sock|fcgi://localhost/"
        </FilesMatch>
      '';
    };
  };

  # open firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Ensure the vhost document root exists with the right ownership.
  # 'd' creates the dir if missing (and fixes perms/owner if it already exists);
  # it does not recurse into or touch existing contents.
  systemd.tmpfiles.rules = [
    "d /var/www/example 0755 wwwrun wwwrun -"
  ];

  ###########################################################################
  # PHP-FPM with ionCube loader
  # the PHP‑FPM module defines per‑pool systemd units under services.phpfpm.pools.<name>, like phpfpm-example.service
  services.phpfpm.pools.example = {
    user = "wwwrun";         # or "nginx", "apache", etc., match your httpd user
    group = "wwwrun";
    phpPackage = phpWithIoncube;

    phpOptions = ''
      memory_limit = 256M
      post_max_size = 20M
      upload_max_filesize = 20M
      date.timezone = "Europe/Copenhagen"
      session.gc_maxlifetime = 21600
      opcache.enable = 0
    '';

    settings = {
      "listen" = "/run/phpfpm/example.sock";
      # FPM's master process runs as root and creates the socket before
      # dropping privileges, so it defaults to root:root ownership.
      # Explicitly hand it to the httpd user/group so Apache can connect.
      "listen.owner" = "wwwrun";
      "listen.group" = "wwwrun";
      "listen.mode" = "0660";
      "pm" = "dynamic";
      "pm.max_children" = 5;
      "pm.start_servers" = 2;
      "pm.min_spare_servers" = 1;
      "pm.max_spare_servers" = 3;
    };
  };
}