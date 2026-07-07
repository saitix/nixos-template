{ config, pkgs, ... }:

let
  phpWithIoncube = pkgs.php85.withExtensions (exts: [
    exts.ioncube-loader
    # add other extensions you need, e.g. exts.curl, exts.opcache, ...
  ]);
in
{
  # webserver
  services.httpd = {
    enable = true;
    adminAddr = "admin@example.com";

    # Example vhost
    virtualHosts."example.local" = {
      documentRoot = "/var/www/example";
      extraConfig = ''
        <FilesMatch "\.php$">
          SetHandler "proxy:unix:/run/phpfpm/php-fpm.sock|fcgi://localhost/"
        </FilesMatch>
      '';
    };
  };

  # open firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # PHP-FPM with ionCube loader
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
      "pm" = "dynamic";
      "pm.max_children" = 5;
      "pm.start_servers" = 2;
      "pm.min_spare_servers" = 1;
      "pm.max_spare_servers" = 3;
    };
  };
}