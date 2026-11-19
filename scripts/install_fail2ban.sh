#!/bin/bash

# Install Fail2ban
# Support Ubuntu/Debian/CentOS/RHEL/Almalinux/Alpine/Arch Linux

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color


detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$(printf '%s' "$ID" | tr '[:upper:]' '[:lower:]')
        VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi
}

# Kept inline: the script library executes each installer independently.
prepare_rpm() {
    PKG=$(command -v dnf || command -v yum || true)
    if [ -z "$PKG" ]; then
        echo "Neither dnf nor yum was found." >&2
        return 1
    fi
}

prepare_extra_repo() {
    local major="${VERSION%%.*}"
    case "$OS" in
        tencentos)
            case "$major" in
                2|3) "$PKG" install -y epel-release ;;
                *) "$PKG" install -y epol-release ;;
            esac
            ;;
        opencloudos)
            case "$major" in
                7|8) "$PKG" install -y epel-release ;;
                *) "$PKG" install -y epol-release ;;
            esac
            ;;
        centos|rhel|rocky|almalinux)
            # EPEL dependencies on EL 8/9 are supplied by PowerTools/CRB.
            if [ "$OS" = almalinux ] || [ "$OS" = rocky ]; then
                "$PKG" install -y dnf-plugins-core
                if [ "$major" = 8 ]; then
                    "$PKG" config-manager --set-enabled powertools
                else
                    "$PKG" config-manager --set-enabled crb
                fi
            fi
            "$PKG" install -y epel-release
            ;;
        # Fedora and CTyunOS use their own configured repositories.
        # CTyunOS version numbers are not Enterprise Linux release numbers.
        fedora|ctyunos) ;;
    esac
}

install_fail2ban() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"

    case "$OS" in
        ubuntu|debian)
            apt-get update
            if ! command -v rsyslogd >/dev/null 2>&1; then
                echo -e "${YELLOW}rsyslog not installed. installing rsyslog...${NC}"
                apt-get install -y rsyslog
            else
                echo -e "${GREEN}rsyslog is already installed.${NC}"
            fi
            apt-get install -y fail2ban
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            prepare_rpm
            prepare_extra_repo
            "$PKG" install -y fail2ban
            ;;
        alpine)
            apk add --no-cache fail2ban
            ;;
        arch)
            pacman -Sy --noconfirm fail2ban
            ;;
        *)
            echo -e "${RED}Unsupported system${NC}"
            exit 1
            ;;
    esac
}

configure_fail2ban() {
    echo -e "${GREEN}Configure Fail2ban...${NC}"
    
    FAIL2BAN_CONF="/etc/fail2ban/jail.local"
    LOG_FILE=""
    BAN_ACTION=""

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        BAN_ACTION="firewallcmd-ipset"
    elif systemctl is-active --quiet ufw 2>/dev/null || service ufw status 2>/dev/null | grep -q "active"; then
        BAN_ACTION="ufw"
    else
        BAN_ACTION="iptables-allports"
    fi

    if [ -f /var/log/secure ]; then
        LOG_FILE="/var/log/secure"
    else
        LOG_FILE="/var/log/auth.log"
        [ -f "$LOG_FILE" ] || touch "$LOG_FILE"
    fi

    cat <<EOF > "$FAIL2BAN_CONF"
#DEFAULT-START
[DEFAULT]
bantime = 600
findtime = 300
maxretry = 5
banaction = $BAN_ACTION
action = %(action_mwl)s
#DEFAULT-END

[sshd]
ignoreip = 127.0.0.1/8
enabled = true
filter = sshd
port = 22
maxretry = 5
findtime = 300
bantime = 600
banaction = $BAN_ACTION
action = %(action_mwl)s
logpath = $LOG_FILE
EOF
}

start_service() {
    echo -e "${GREEN}Start Fail2ban...${NC}"
    
    case "$OS" in
        ubuntu|debian)
            systemctl enable fail2ban
            systemctl restart fail2ban
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            systemctl enable fail2ban
            systemctl restart fail2ban
            ;;
        alpine)
            rc-update add fail2ban
            rc-service fail2ban start
            ;;
        arch)
            systemctl enable fail2ban
            systemctl restart fail2ban
            ;;
        *)
            echo -e "${YELLOW}The service cannot be started automatically. Please start manually!${NC}"
            ;;
    esac

    if command -v systemctl &> /dev/null; then
        systemctl status fail2ban || true
    else
        rc-service fail2ban status || true
    fi

    echo -e "${GREEN}Fail2ban is installed and started${NC}"
}

main() {
    detect_os
    install_fail2ban
    configure_fail2ban
    start_service
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    main "$@"
fi
