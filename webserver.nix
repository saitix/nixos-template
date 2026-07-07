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

  #php
  services.phpfpm = {
    enable = true;

    phpOptions = ''
      memory_limit = 256M
      post_max_size = 20M
      upload_max_filesize = 20M
      date.timezone = "Europe/Copenhagen"
      session.gc_maxlifetime = 21600
      opcache.enable = 0

      #zend_extension="${ioncube}/lib/php/extensions/ioncube_loader_lin_8.2.so"
    '';
  };
}
