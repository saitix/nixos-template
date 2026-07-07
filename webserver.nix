{ config, pkgs, ... }:

{
  #webserver
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
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  let
    phpWithIoncube = pkgs.php85.withExtensions (exts: [
      exts.ioncube-loader
      # add other extensions you need, e.g. exts.curl, exts.opcache, ...
    ]);
  in
  {
    #php
    services.phpfpm = {
      enable = true;
      phpPackage = phpWithIoncube;

      phpOptions = ''
        memory_limit = 256M
        post_max_size = 20M
        upload_max_filesize = 20M
        date.timezone = "Europe/Copenhagen"
        session.gc_maxlifetime = 21600
        opcache.enable = 0
      '';
    };
  }
}
