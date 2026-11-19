#!/bin/bash

# Install Supervisor
# Support Ubuntu/Debian/CentOS/RHEL/Rocky/AlmaLinux/TencentOS/OpenCloudOS/CTyunOS/Alpine/Arch Linux

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

install_supervisor() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"

    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y supervisor
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            prepare_rpm
            prepare_extra_repo
            "$PKG" install -y supervisor
            ;;
        alpine)
            apk add --no-cache supervisor
            mkdir -p /etc/supervisor.d
            ;;
        arch)
            pacman -Sy --noconfirm supervisor
            ;;
        *)
            echo -e "${RED}Unsupported system${NC}"
            exit 1
            ;;
    esac
}

start_service() {
    echo -e "${GREEN}Start Supervisor...${NC}"
    
    SUPERVISOR_SERVICE=supervisor
    if [ "$OS" != alpine ] && command -v systemctl >/dev/null 2>&1; then
        if systemctl cat supervisord.service >/dev/null 2>&1; then
            SUPERVISOR_SERVICE=supervisord
        elif ! systemctl cat supervisor.service >/dev/null 2>&1; then
            echo "Supervisor systemd service not found." >&2
            return 1
        fi
    fi
    case "$OS" in
        ubuntu|debian)
            systemctl enable "$SUPERVISOR_SERVICE"
            systemctl restart "$SUPERVISOR_SERVICE"
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            systemctl enable "$SUPERVISOR_SERVICE"
            systemctl restart "$SUPERVISOR_SERVICE"
            ;;
        alpine)
            rc-update add supervisor
            rc-service supervisor start
            ;;
        arch)
            systemctl enable "$SUPERVISOR_SERVICE"
            systemctl restart "$SUPERVISOR_SERVICE"
            ;;
        *)
            echo -e "${YELLOW}The service cannot be started automatically. Please start manually!${NC}"
            ;;
    esac

    if command -v systemctl &> /dev/null; then
        systemctl status "$SUPERVISOR_SERVICE" || true
    else
        rc-service supervisor status || true
    fi

     echo -e "${GREEN}Supervisor is installed and started${NC}"
}

main() {
    detect_os
    install_supervisor
    start_service
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    main "$@"
fi
