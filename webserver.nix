{
  config,
  lib,
  pkgs,
  ...
}:

let
  ###########################################################################
  # Deployment variables — fill these in before deploying.
  # `domain` MUST be a public FQDN that resolves to this server (through the
  # firewall port-forward) for the Let's Encrypt HTTP-01 challenge to work.
  domain = "whmcs.example.com"; # TODO: set real FQDN
  adminEmail = "admin@example.com"; # TODO: set real admin / ACME email
  docroot = "/var/www/whmcs";
  poolName = "whmcs";

  # WHMCS 9 supports PHP 8.2/8.3 only. php83's default extension set
  # includes imap and opcache (both are only defaults for PHP < 8.4/8.5),
  # plus everything else WHMCS needs: curl, gd, xml/dom, soap, mbstring,
  # bcmath, gmp, intl, pdo_mysql (mysqlnd), etc.
  #
  # nixpkgs' ioncube-loader package doesn't mark itself as a zend_extension,
  # so withExtensions would emit "extension=..." instead of "zend_extension=...".
  # ionCube itself requires the zend_extension directive (it's a Zend-Engine
  # extension, not a regular module) - override the derivation to fix that.
  #
  # IMPORTANT: ionCube must be the FIRST entry in php.ini ("The Loader must
  # appear as the first entry" fatal error otherwise). nixpkgs generates the
  # ini lines in list order (textClosureList), so ionCube is PREpended here,
  # not appended — otherwise it lands after opcache's zend_extension line
  # and php-fpm crash-loops with status 254.
  # Loader 15.5.0 satisfies WHMCS' minimum (14.4.0 for PHP 8.3).
  phpWithIoncube = pkgs.php83.withExtensions (
    { enabled, all }:
    [
      (all.ioncube-loader.overrideAttrs (_: {
        zendExtension = true;
      }))
    ]
    ++ enabled
  );
in
{
  ###########################################################################
  # webserver
  services.httpd = {
    enable = true;
    adminAddr = adminEmail;

    # mod_proxy_fcgi isn't loaded by default; it's required for the
    # SetHandler "proxy:unix:..." directive below to actually forward
    # .php requests to PHP-FPM instead of serving them as static files.
    extraModules = [ "proxy_fcgi" ];

    virtualHosts."${domain}" = {
      documentRoot = docroot;

      # HTTPS via Let's Encrypt. forceSSL keeps a port-80 vhost alive for
      # the ACME HTTP-01 challenge and redirects everything else to 443.
      # Requires ports 80+443 forwarded to this host at the firewall
      # and `domain` resolving publicly.
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        <Directory "${docroot}">
            #allow .htaccess files to be loaded
            AllowOverride FileInfo AuthConfig Limit
        </Directory>
        <FilesMatch "\.php$">
          SetHandler "proxy:unix:/run/phpfpm/${poolName}.sock|fcgi://localhost/"
        </FilesMatch>
      '';
    };
  };

  # open firewall for the forwarded web ports (SSH is opened separately
  # by services.openssh). No other inbound ports are needed: the server
  # lives on the internal network only.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Lets the box resolve its own vhost name internally.
  networking.extraHosts = "127.0.0.1 ${domain}";

  security.acme = {
    acceptTerms = true;
    defaults.email = adminEmail;
  };

  # Ensure the vhost document root exists with the right ownership.
  # 'd' creates the dir if missing (and fixes perms/owner if it already exists);
  # it does not recurse into or touch existing contents.
  systemd.tmpfiles.rules = [
    "d ${docroot} 0755 wwwrun wwwrun -"
  ];

  # CLI PHP with ionCube loaded, so WHMCS cron jobs (`php cron.php`) and
  # any CLI WHMCS tooling decode encoded files exactly like the web pool.
  # Do NOT add plain pkgs.php83 to systemPackages - it has no ionCube.
  environment.systemPackages = [ phpWithIoncube ];

  ###########################################################################
  # PHP-FPM with ionCube loader
  # the PHP-FPM module defines per-pool systemd units under services.phpfpm.pools.<name>, like phpfpm-whmcs.service
  services.phpfpm.pools.${poolName} = {
    user = "wwwrun"; # httpd user
    group = "wwwrun";
    phpPackage = phpWithIoncube;

    phpOptions = ''
      memory_limit = 256M
      post_max_size = 20M
      upload_max_filesize = 20M
      date.timezone = "Europe/Copenhagen"
      session.gc_maxlifetime = 21600
      opcache.enable = 0
      short_open_tag = On
    '';

    settings = {
      "listen" = "/run/phpfpm/${poolName}.sock";
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
