# NixOS WHMCS Template

A NixOS configuration template that builds a VM (QEMU/KVM guest) prepared for a
self-hosted [WHMCS](https://www.whmcs.com/) installation: Apache + PHP-FPM with
ionCube Loader, Percona Server (MySQL), and Let's Encrypt TLS.

The server sits on the internal network only; external access is provided by
port forwarding (80/443) on an external firewall.

## Files

| File                    | Purpose                                                                  |
| ----------------------- | ------------------------------------------------------------------------ |
| `configuration.nix`     | Base system: boot loader, DHCP networking, packages, Percona/MySQL, SSH  |
| `webserver.nix`         | Apache httpd vhost, PHP-FPM pool with ionCube, ACME/TLS, firewall ports  |
| `hardware-configuration.nix` | QEMU guest profile + mounts by filesystem LABEL (`root`, `BOOT`) — no UUIDs, works on any disk. |
| `partition-disk.sh`    | Wipes the target disk, creates the UEFI layout, formats, and rewrites `hardware-configuration.nix` (LABEL= form). |

## Key design decisions

- **PHP 8.3** (`pkgs.php83`) — WHMCS 9 supports PHP 8.2/8.3 only. The default
  extension set already includes everything WHMCS requires (curl, gd, imap,
  soap, mbstring, bcmath, gmp, intl, pdo_mysql with mysqlnd, ...).
- **ionCube Loader** — nixpkgs' `ioncube-loader` does not mark itself as a
  Zend extension, so it is added via `withExtensions` with an
  `overrideAttrs { zendExtension = true; }`. The same PHP build is used for
  both the FPM pool and the CLI (`environment.systemPackages`), so WHMCS cron
  jobs can decode encoded files too. Do **not** add a plain `php83` package to
  the system profile — it would shadow the ionCube-enabled one on PATH.
- **Apache + PHP-FPM** over mod_php — `proxy_fcgi` SetHandler routes `.php`
  to the pool socket `/run/phpfpm/whmcs.sock`. The vhost allows
  `AllowOverride FileInfo AuthConfig Limit` because WHMCS relies on its
  shipped `.htaccess` files.
- **Percona Server 8** with strict SQL mode disabled
  (`sql-mode = NO_ENGINE_SUBSTITUTION`) — WHMCS does not support
  `STRICT_TRANS_TABLES`.
- **TLS via Let's Encrypt** — vhost uses `enableACME` + `forceSSL`; the ACME
  HTTP-01 challenge needs port 80 reachable from the internet through the
  firewall port-forward, and the FQDN must resolve publicly.
- **DHCP networking** (`networking.useDHCP = true`, all interfaces) — reserve
  the VM's IP on the DHCP server by its MAC address so the firewall
  port-forward target never changes.
- Unfree packages are allowed (`nixpkgs.config.allowUnfree = true`) — required
  by ionCube Loader.

## Variables to set before deploying (`webserver.nix`)

- `domain` — public FQDN of the WHMCS instance (must resolve to the firewall's
  forwarded IP)
- `adminEmail` — Apache admin address + ACME account email
- `docroot` — WHMCS install directory (default `/var/www/whmcs`)

## Deploying

From scratch on a new VM (boot the NixOS minimal ISO, clone this repo):

```sh
git clone <this-repo> /tmp/nixos-template && cd /tmp/nixos-template
sudo ./partition-disk.sh /dev/vda --mount   # wipes disk, formats, mounts /mnt
sudo cp -r . /mnt/etc/nixos                 # or rsync -a --exclude .git . /mnt/etc/nixos/
sudo nixos-install --root /mnt              # set root password when prompted
# commit the (identical) rewritten hardware-configuration.nix back to git
```

On an already-installed system:

```sh
# on the target VM (or with NIXOS_CONFIG / -I flags from this repo):
nixos-rebuild switch
```

Disk layout produced by the script (UEFI, entire disk, no swap):

- partition 1: 512 MiB FAT32 ESP, label `BOOT` → `/boot`
- partition 2: rest of the disk, ext4, label `root` → `/`

## Post-boot checklist (manual steps)

1. Set a MySQL password for WHMCS — `ensureUsers` creates the `whmcs` user
   with socket auth only:
   ```sh
   mysql -e "ALTER USER 'whmcs'@'localhost' IDENTIFIED BY '<password>'; FLUSH PRIVILEGES;"
   ```
2. Download and unpack WHMCS into `/var/www/whmcs`, owned by `wwwrun:wwwrun`;
   run the WHMCS installer (browser or CLI) and fill in `configuration.php`
   (DB user `whmcs`, DB name `whmcs`, socket `/run/mysqld/mysqld.sock`).
3. Configure the WHMCS daily cron (not yet in this template), e.g. a systemd
   timer running `php /var/www/whmcs/cron.php` as a scheduled follow-up.
4. Verify https://<domain>/ loads with a valid certificate.

## Not included (TODO)

- WHMCS cron timer.
- Backup/monitoring.
- Swap (neither partition nor swapfile) — add a swapfile later if needed.
