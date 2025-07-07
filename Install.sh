#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

QINSTALLER_VERSION="1.2"
SUPPORTED_OS=""
DISTRO=""
PHP_VERSION="8.2"
MYSQL_ROOT_PASSWORD=""
DOMAIN=""
EMAIL=""
PASSWORD=""
INSTALL_DIR="/var/www"
SERVER_IP=""

Func1() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        case $ID in
            ubuntu|debian) SUPPORTED_OS="debian" ;;
            centos|rhel|fedora|rocky|almalinux) SUPPORTED_OS="rhel" ;;
            *) echo -e "${RED}Unsupported OS: $ID${NC}"; exit 1 ;;
        esac
    else
        echo -e "${RED}Cannot detect OS${NC}"; exit 1
    fi
    SERVER_IP=$(hostname -I | awk '{print $1}')
}

Func2() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

Func3() {
    echo -e "${BLUE}Installing base dependencies...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        apt update -y
        apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release build-essential unzip tar git vim htop sudo ufw fail2ban dirmngr
        add-apt-repository -y ppa:ondrej/php
        apt update -y
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        dnf update -y
        dnf install -y epel-release
        dnf groupinstall -y "Development Tools"
        dnf install -y curl wget gnupg2 unzip tar git vim htop sudo firewalld fail2ban
    fi
}

Func4() {
    echo -e "${BLUE}Installing PHP stack...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        apt install -y php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-gd php${PHP_VERSION}-mysql php${PHP_VERSION}-pdo php${PHP_VERSION}-mbstring php${PHP_VERSION}-tokenizer php${PHP_VERSION}-bcmath php${PHP_VERSION}-xml php${PHP_VERSION}-fpm php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-intl php${PHP_VERSION}-readline php${PHP_VERSION}-dom php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-redis php${PHP_VERSION}-imagick php${PHP_VERSION}-soap php${PHP_VERSION}-xsl php${PHP_VERSION}-opcache
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        dnf module reset php -y
        dnf module enable php:remi-${PHP_VERSION} -y
        dnf install -y php php-cli php-gd php-mysql php-pdo php-mbstring php-tokenizer php-bcmath php-xml php-fpm php-curl php-zip php-intl php-readline php-dom php-sqlite3 php-redis php-imagick php-soap php-xsl php-opcache
    fi
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    systemctl enable php${PHP_VERSION}-fpm
    systemctl start php${PHP_VERSION}-fpm
}

Func5() {
    echo -e "${BLUE}Installing Nginx...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        apt install -y nginx
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        dnf install -y nginx
    fi
    systemctl enable nginx
    systemctl start nginx
    if [[ $SUPPORTED_OS == "debian" ]]; then
        ufw allow 'Nginx Full' 2>/dev/null || true
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
    fi
}

Func6() {
    echo -e "${BLUE}Installing databases...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        apt install -y mariadb-server postgresql postgresql-contrib redis-server sqlite3
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        dnf install -y mariadb-server postgresql postgresql-contrib redis sqlite
    fi
    systemctl start mariadb postgresql redis
    systemctl enable mariadb postgresql redis
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
}

Func7() {
    echo -e "${BLUE}Installing SSL certificates...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        apt install -y certbot python3-certbot-nginx
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        dnf install -y certbot python3-certbot-nginx
    fi
    if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
        certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email ${EMAIL} --redirect
    fi
}

Func8() {
    echo -e "${CYAN}Installing Docker stack...${NC}"
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
    curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    mkdir -p /opt/portainer
    docker volume create portainer_data
    docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
    mkdir -p /opt/yacht
    docker run -d -p 8001:8000 -v /var/run/docker.sock:/var/run/docker.sock -v /opt/yacht:/config --name yacht selfhostedpro/yacht
    echo -e "${GREEN}Docker: https://${SERVER_IP}:9443${NC}"
    echo -e "${GREEN}Yacht: http://${SERVER_IP}:8001${NC}"
}

Func9() {
    echo -e "${CYAN}Installing Proxmox VE...${NC}"
    read -s -p "Enter Proxmox root password: " PASSWORD
    echo
    if [[ $DISTRO != "debian" ]]; then
        echo -e "${RED}Proxmox VE only supports Debian${NC}"
        return 1
    fi
    echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bullseye pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
    wget http://download.proxmox.com/debian/proxmox-ve-release-6.x.gpg -O /etc/apt/trusted.gpg.d/proxmox-ve-release-6.x.gpg
    apt update -y
    apt full-upgrade -y
    apt install -y proxmox-ve postfix open-iscsi
    systemctl disable --now rpcbind rpcbind.socket
    echo -e "${GREEN}Proxmox: https://${SERVER_IP}:8006${NC}"
}

Func10() {
    echo -e "${CYAN}Installing Webmin/Virtualmin...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        echo "deb http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
        wget -qO - http://www.webmin.com/jcameron-key.asc | apt-key add -
        apt update -y
        apt install -y webmin
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        cat > /etc/yum.repos.d/webmin.repo <<EOF
[Webmin]
name=Webmin Distribution Neutral
baseurl=http://download.webmin.com/download/yum
enabled=1
gpgcheck=1
gpgkey=http://www.webmin.com/jcameron-key.asc
EOF
        dnf install -y webmin
    fi
    wget -O virtualmin-install.sh https://software.virtualmin.com/gpl/scripts/install.sh
    chmod +x virtualmin-install.sh
    ./virtualmin-install.sh --hostname $(hostname -f) --force
    echo -e "${GREEN}Webmin: https://${SERVER_IP}:10000${NC}"
}

Func11() {
    echo -e "${CYAN}Installing CyberPanel...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        apt install -y python3 python3-pip
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        dnf install -y python3 python3-pip
    fi
    wget -O cyberpanel.sh https://cyberpanel.net/install.sh
    chmod +x cyberpanel.sh
    ./cyberpanel.sh
    echo -e "${GREEN}CyberPanel: https://${SERVER_IP}:8090${NC}"
}

Func12() {
    echo -e "${CYAN}Installing WordPress...${NC}"
    read -p "Enter WordPress domain: " DOMAIN
    read -p "Enter admin email: " EMAIL
    read -s -p "Enter admin password: " PASSWORD
    echo
    mkdir -p ${INSTALL_DIR}/wordpress
    cd /tmp
    wget https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    cp -r wordpress/* ${INSTALL_DIR}/wordpress/
    WP_DB_PASS=$(openssl rand -base64 32)
    mysql -u root -p${MYSQL_ROOT_PASSWORD} <<EOF
CREATE DATABASE wordpress;
CREATE USER 'wordpress'@'localhost' IDENTIFIED BY '${WP_DB_PASS}';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost';
FLUSH PRIVILEGES;
EOF
    chown -R www-data:www-data ${INSTALL_DIR}/wordpress
    cat > /etc/nginx/sites-available/wordpress <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root ${INSTALL_DIR}/wordpress;
    index index.php index.html index.htm;
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
    systemctl reload nginx
    echo -e "${GREEN}WordPress: https://${DOMAIN}${NC}"
}

Func13() {
    echo -e "${CYAN}Installing Nextcloud...${NC}"
    read -p "Enter Nextcloud domain: " DOMAIN
    read -p "Enter admin email: " EMAIL
    read -s -p "Enter admin password: " PASSWORD
    echo
    mkdir -p ${INSTALL_DIR}/nextcloud
    cd /tmp
    wget https://download.nextcloud.com/server/releases/latest.tar.bz2
    tar -xjf latest.tar.bz2
    cp -r nextcloud/* ${INSTALL_DIR}/nextcloud/
    NC_DB_PASS=$(openssl rand -base64 32)
    mysql -u root -p${MYSQL_ROOT_PASSWORD} <<EOF
CREATE DATABASE nextcloud;
CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '${NC_DB_PASS}';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
EOF
    chown -R www-data:www-data ${INSTALL_DIR}/nextcloud
    cat > /etc/nginx/sites-available/nextcloud <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root ${INSTALL_DIR}/nextcloud;
    index index.php index.html index.htm;
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
    systemctl reload nginx
    echo -e "${GREEN}Nextcloud: https://${DOMAIN}${NC}"
}

Func14() {
    echo -e "${CYAN}Installing GitLab CE...${NC}"
    read -p "Enter GitLab domain: " DOMAIN
    read -p "Enter admin email: " EMAIL
    if [[ $SUPPORTED_OS == "debian" ]]; then
        curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
        apt install -y gitlab-ce
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | bash
        dnf install -y gitlab-ce
    fi
    cat > /etc/gitlab/gitlab.rb <<EOF
external_url 'https://${DOMAIN}'
gitlab_rails['gitlab_email_from'] = '${EMAIL}'
gitlab_rails['gitlab_email_display_name'] = 'GitLab'
gitlab_rails['smtp_enable'] = true
letsencrypt['enable'] = true
letsencrypt['contact_emails'] = ['${EMAIL}']
EOF
    gitlab-ctl reconfigure
    echo -e "${GREEN}GitLab: https://${DOMAIN}${NC}"
    echo -e "${YELLOW}Root password: $(cat /etc/gitlab/initial_root_password)${NC}"
}

Func15() {
    echo -e "${CYAN}Installing Jenkins...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | apt-key add -
        echo "deb https://pkg.jenkins.io/debian binary/" > /etc/apt/sources.list.d/jenkins.list
        apt update -y
        apt install -y jenkins
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat/jenkins.repo
        rpm --import https://pkg.jenkins.io/redhat/jenkins.io.key
        dnf install -y jenkins
    fi
    systemctl enable jenkins
    systemctl start jenkins
    echo -e "${GREEN}Jenkins: http://${SERVER_IP}:8080${NC}"
    echo -e "${YELLOW}Password: $(cat /var/lib/jenkins/secrets/initialAdminPassword)${NC}"
}

Func16() {
    echo -e "${CYAN}Installing Grafana & Prometheus...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
        echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
        apt update -y
        apt install -y grafana prometheus
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        cat > /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
        dnf install -y grafana prometheus2
    fi
    systemctl enable grafana-server prometheus
    systemctl start grafana-server prometheus
    echo -e "${GREEN}Grafana: http://${SERVER_IP}:3000${NC}"
    echo -e "${GREEN}Prometheus: http://${SERVER_IP}:9090${NC}"
}

Func17() {
    echo -e "${CYAN}Installing Pterodactyl Panel...${NC}"
    read -p "Enter panel domain: " DOMAIN
    read -p "Enter admin email: " EMAIL
    read -s -p "Enter admin password: " PASSWORD
    echo
    mkdir -p ${INSTALL_DIR}/pterodactyl
    cd ${INSTALL_DIR}/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    PT_DB_PASS=$(openssl rand -base64 32)
    mysql -u root -p${MYSQL_ROOT_PASSWORD} <<EOF
CREATE DATABASE panel;
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${PT_DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    php artisan migrate --seed --force
    chown -R www-data:www-data ${INSTALL_DIR}/pterodactyl/*
    cat > /etc/nginx/sites-available/pterodactyl <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root ${INSTALL_DIR}/pterodactyl/public;
    index index.php;
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/
    systemctl reload nginx
    echo -e "${GREEN}Pterodactyl: https://${DOMAIN}${NC}"
}

Func18() {
    echo -e "${CYAN}Installing Pterodactyl Wings...${NC}"
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable docker
    systemctl start docker
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable wings
    echo -e "${GREEN}Wings installed! Configure with panel API key.${NC}"
}

Func19() {
    echo -e "${BLUE}Installing security suite...${NC}"
    if [[ $SUPPORTED_OS == "debian" ]]; then
        apt install -y fail2ban ufw iptables-persistent clamav clamav-daemon rkhunter chkrootkit
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        dnf install -y fail2ban firewalld iptables-services clamav clamav-update rkhunter chkrootkit
    fi
    systemctl enable fail2ban
    systemctl start fail2ban
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
EOF
    systemctl restart fail2ban
    if [[ $SUPPORTED_OS == "debian" ]]; then
        ufw --force enable
    elif [[ $SUPPORTED_OS == "rhel" ]]; then
        systemctl enable firewalld
        systemctl start firewalld
    fi
}

Func20() {
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}                    QINSTALLER COMPLETE                        ${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${YELLOW}MySQL Root Password: ${MYSQL_ROOT_PASSWORD}${NC}"
    echo -e "${YELLOW}Server IP: ${SERVER_IP}${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${CYAN}Save these credentials in a secure location!${NC}"
    echo -e "${GREEN}================================================================${NC}"
}

Func21() {
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                        QINSTALLER v${QINSTALLER_VERSION}                        ║${NC}"
    echo -e "${PURPLE}║                       Server Manager            ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Detected OS: ${DISTRO} (${SUPPORTED_OS}) | Server IP: ${SERVER_IP}${NC}"
    echo
    echo -e "${YELLOW}════════════════ VIRTUALIZATION & CONTAINERS ══════════════════${NC}"
    echo -e "${YELLOW}1)  Install Proxmox VE${NC}"
    echo -e "${YELLOW}2)  Install Docker + Portainer + Yacht${NC}"
    echo -e "${YELLOW}3)  Install Pterodactyl Panel${NC}"
    echo -e "${YELLOW}4)  Install Pterodactyl Wings${NC}"
    echo
    echo -e "${YELLOW}════════════════ CONTROL PANELS ═══════════════════════════════${NC}"
    echo -e "${YELLOW}5)  Install Webmin/Virtualmin${NC}"
    echo -e "${YELLOW}6)  Install CyberPanel${NC}"
    echo
    echo -e "${YELLOW}════════════════ APPLICATIONS ═════════════════════════════════${NC}"
    echo -e "${YELLOW}7)  Install WordPress${NC}"
    echo -e "${YELLOW}8)  Install Nextcloud${NC}"
    echo -e "${YELLOW}9)  Install GitLab CE${NC}"
    echo -e "${YELLOW}10) Install Jenkins${NC}"
    echo -e "${YELLOW}11) Install Grafana + Prometheus${NC}"
    echo
    echo -e "${YELLOW}════════════════ STACKS ═══════════════════════════════════════${NC}"
    echo -e "${YELLOW}12) Install LEMP Stack${NC}"
    echo -e "${YELLOW}13) Install Everything${NC}"
    echo -e "${YELLOW}14) Install Hosting Stack${NC}"
    echo -e "${YELLOW}15) Install Game Server Stack${NC}"
    echo
    echo -e "${YELLOW}════════════════ SYSTEM ═══════════════════════════════════════${NC}"
    echo -e "${YELLOW}16) Install Base Dependencies${NC}"
    echo -e "${YELLOW}17) Install Security Suite${NC}"
    echo -e "${YELLOW}18) Exit${NC}"
    echo
    read -p "Select option [1-18]: " choice
    
    case $choice in
        1) Func3; Func9; Func20 ;;
        2) Func3; Func8; Func20 ;;
        3) Func3; Func4; Func5; Func6; Func7; Func17; Func20 ;;
        4) Func3; Func18; Func20 ;;
        5) Func3; Func10; Func20 ;;
        6) Func3; Func11; Func20 ;;
        7) Func3; Func4; Func5; Func6; Func7; Func12; Func20 ;;
        8) Func3; Func4; Func5; Func6; Func7; Func13; Func20 ;;
        9) Func3; Func14; Func20 ;;
        10) Func3; Func15; Func20 ;;
        11) Func3; Func16; Func20 ;;
        12) Func3; Func4; Func5; Func6; Func7; Func20 ;;
        13) Func3; Func4; Func5; Func6; Func7; Func8; Func10; Func12; Func13; Func14; Func15; Func16; Func17; Func19; Func20 ;;
        14) Func3; Func4; Func5; Func6; Func7; Func10; Func12; Func19; Func20 ;;
        15) Func3; Func4; Func5; Func6; Func7; Func8; Func17; Func18; Func19; Func20 ;;
        16) Func3; Func20 ;;
        17) Func3; Func19; Func20 ;;
        18) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; Func21 ;;
    esac
}

Func1
Func2
Func21
