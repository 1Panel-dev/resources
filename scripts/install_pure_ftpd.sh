#!/bin/bash

# Install Pure-FTPd
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

install_pureftpd() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"

    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y pure-ftpd
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            prepare_rpm
            prepare_extra_repo
            "$PKG" install -y pure-ftpd
            ;;
        alpine)
            apk add --no-cache pure-ftpd
            ;;
        arch)
            pacman -Sy --noconfirm pure-ftpd
            ;;
        *)
            echo -e "${RED}Unsupported system${NC}"
            exit 1
            ;;
    esac

    if ! command -v pure-ftpd &> /dev/null; then
        echo -e "${RED}Install Pure-FTPd failed${NC}"
        exit 1
    fi
}

configure_pureftpd() {
    echo -e "${GREEN}Configure Pure-FTPd...${NC}"
    
    if [ ! -d "/etc/pure-ftpd/conf" ]; then
        PURE_FTPD_CONF="/etc/pure-ftpd/pure-ftpd.conf"
        if [ ! -f "$PURE_FTPD_CONF" ] && [ -f /etc/pure-ftpd.conf ]; then
            PURE_FTPD_CONF=/etc/pure-ftpd.conf
        fi
        cp "$PURE_FTPD_CONF" "$PURE_FTPD_CONF.bak"
        sed -i 's/^NoAnonymous[[:space:]]\+no$/NoAnonymous yes/' "$PURE_FTPD_CONF"
        sed -i 's/^PAMAuthentication[[:space:]]\+yes$/PAMAuthentication no/' "$PURE_FTPD_CONF"
        sed -i 's/^# PassivePortRange[[:space:]]\+30000 50000$/PassivePortRange 39000 40000/' "$PURE_FTPD_CONF"
        sed -i 's/^VerboseLog[[:space:]]\+no$/VerboseLog yes/' "$PURE_FTPD_CONF"
        sed -i 's/^# PureDB[[:space:]]\+\/etc\/pure-ftpd\/pureftpd\.pdb[[:space:]]*$/PureDB \/etc\/pure-ftpd\/pureftpd.pdb/' "$PURE_FTPD_CONF"
    else
        touch /etc/pure-ftpd/pureftpd.pdb
        chmod 644 /etc/pure-ftpd/pureftpd.pdb
        echo '/etc/pure-ftpd/pureftpd.pdb' > /etc/pure-ftpd/conf/PureDB
        echo yes > /etc/pure-ftpd/conf/VerboseLog 
        echo yes > /etc/pure-ftpd/conf/NoAnonymous
        echo '39000 40000' > /etc/pure-ftpd/conf/PassivePortRange
        echo 'no' > /etc/pure-ftpd/conf/PAMAuthentication
        echo 'no' > /etc/pure-ftpd/conf/UnixAuthentication
        echo 'clf:/var/log/pure-ftpd/transfer.log' > /etc/pure-ftpd/conf/AltLog
        ln -sf /etc/pure-ftpd/conf/PureDB /etc/pure-ftpd/auth/50puredb
    fi
}

start_service() {
    echo -e "${GREEN}Start Pure-FTPd...${NC}"
    
    case "$OS" in
        ubuntu|debian)
            systemctl enable pure-ftpd
            systemctl restart pure-ftpd
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            systemctl enable pure-ftpd
            systemctl restart pure-ftpd
            ;;
        alpine)
            rc-update add pure-ftpd
            rc-service pure-ftpd start
            ;;
        arch)
            systemctl enable pure-ftpd
            systemctl restart pure-ftpd
            ;;
        *)
            echo -e "${YELLOW}The service cannot be started automatically. Please start manually!${NC}"
            ;;
    esac

    if command -v systemctl &> /dev/null; then
        systemctl status pure-ftpd || true
    else
        rc-service pure-ftpd status || true
    fi

    echo -e "${GREEN}Pure-FTPd is installed and started${NC}"
}

main() {
    detect_os
    install_pureftpd
    configure_pureftpd
    start_service
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    main "$@"
fi
