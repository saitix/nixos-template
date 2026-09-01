# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Allow unfree packages (required for ioncube-loader and similar proprietary software)
  nixpkgs.config.allowUnfree = true;

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./webserver.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.graceful = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
  # Optional: limit boot entries
  boot.loader.systemd-boot.configurationLimit = 5;

  networking.hostName = "whmcs"; # TODO: set real hostname
  networking.domain = "example.com"; #TODO: set the real domain

  # Internal-network-only server; external access arrives via port forwarding
  # on the firewall. IP is assigned by DHCP (optionally reserved for this
  # VM's MAC address on the DHCP server).
  # Interface names aren't hardcoded so the config works on any NIC:
  # with scripted networking, useDHCP enables it on all interfaces.
  networking.useDHCP = true;
  # If you later want DHCP on a specific interface only, uncomment and set:
  # networking.useDHCP = false;
  # networking.interfaces.enp1s0.useDHCP = true;

  # Set your time zone.
  time.timeZone = "Europe/Copenhagen";

  #nix Garbage collector
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 60d";
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  # users.users.alice = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  #   packages = with pkgs; [
  #     tree
  #   ];
  # };

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # Use https://search.nixos.org/ to find packages and options.
  #
  # NOTE: the PHP CLI with ionCube is provided by webserver.nix
  # (environment.systemPackages there). Do NOT add plain `php83` here —
  # it would put an ionCube-less PHP on PATH that breaks WHMCS cron.
  # percona-server is pulled in by services.mysql below; only add it here
  # if you want the `mysql` client CLI on PATH.
  environment.systemPackages = with pkgs; [
    elinks
    git
    hdparm
    htop
    mc
    net-tools
    nmon
    percona-server
    psmisc
    pydf
    tcpdump
    tmux
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  #Enable qemu guest agent
  services.qemuGuest.enable = true;

  #Enable percona mysql
  services.mysql = {
    enable = true;
    package = pkgs.percona-server;
    # WHMCS does NOT support MySQL strict mode (STRICT_TRANS_TABLES /
    # ERROR_FOR_DIVISION_BY_ZERO cause serious problems in WHMCS).
    # Percona 8.x enables them by default - turn them off.
    settings.mysqld = {
      sql-mode = "NO_ENGINE_SUBSTITUTION";
    };

    # WHMCS database + user. NOTE: ensureUsers creates the MySQL user
    # with auth_socket (Unix-socket) authentication — usable only by a
    # same-named UNIX user, which the wwwrun PHP process is not.
    # After first boot you MUST switch it to password auth before WHMCS
    # can connect:
    #   mysql -e "ALTER USER 'whmcs'@'localhost' IDENTIFIED BY '...'; \
    #             FLUSH PRIVILEGES;"
    # then put that password in WHMCS configuration.php.
    ensureDatabases = [ "whmcs" ];
    ensureUsers = [
      {
        name = "whmcs";
        ensurePermissions = {
          "whmcs.*" = "SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, LOCK TABLES, CREATE TEMPORARY TABLES";
        };
      }
    ];
    # Same socket PDO_MySQL is compiled for (php packages set PHP_MYSQL_SOCK
    # to this path), so WHMCS's default localhost connection just works.
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .

  system.stateVersion = "26.05"; # Did you read the comment?

}
