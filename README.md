# QInstaller

**QInstaller** is an advanced interactive Bash-based provisioning script for Linux servers. It allows system administrators, developers, and self-hosters to deploy fully functional stacks, control panels, container environments, and monitoring tools with ease.

> ⚠️ **Requires root privileges.** Run as root or with `sudo`.

## Features

- Interactive terminal UI with categorized menu
- OS-aware logic (Debian/Ubuntu and RHEL-based support)
- Optional "Install All" and stack bundles (game server stack, hosting stack, etc.)
- Randomized secure MySQL root/password generation
- Automatic HTTPS via Certbot for supported domains
- System hardening and security tooling

## What It Can Install

### Virtualization & Containers
- Proxmox VE (Debian only)
- Docker + Portainer + Yacht
- Pterodactyl Panel
- Pterodactyl Wings

### Control Panels
- Webmin + Virtualmin
- CyberPanel

### Applications
- WordPress
- Nextcloud
- GitLab CE
- Jenkins
- Grafana + Prometheus

### Stack Options
- LEMP Stack (Linux, Nginx, MariaDB, PHP)
- Hosting Stack (LEMP + panels + WordPress)
- Game Server Stack (LEMP + Docker + Pterodactyl)

### System Tools
- Base utilities (curl, git, vim, build tools)
- Security tools: fail2ban, ufw/firewalld, clamav, chkrootkit, rkhunter

## Supported Operating Systems

- Debian 10+
- Ubuntu 20.04+
- RHEL 8+, AlmaLinux, Rocky Linux

## Usage

```bash
sudo bash <(curl -sL https://raw.githubusercontent.com/QuantumLLC/QInstaller/main/Install.sh)
```

## Notes
Must be run as root (sudo or root shell).

Some installations (like Pterodactyl or GitLab) require significant system resources and may take a while.

Ensure your system has internet access and is up to date before running QInstaller.

-- much love — 0rmn on Discord
