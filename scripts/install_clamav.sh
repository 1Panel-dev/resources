#!/bin/bash

# Install ClamAV
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

rpm_package() {
    local candidate
    for candidate in "$@"; do
        if "$PKG" -q list "$candidate" >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    echo "No package ($*) found for $OS $VERSION; check the distribution repositories." >&2
    return 1
}

install_clamav() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"

    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y clamav clamav-daemon clamav-freshclam
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            prepare_rpm
            prepare_extra_repo
            local daemon_package update_package
            daemon_package=$(rpm_package clamd clamav-server clamav)
            update_package=$(rpm_package clamav-update clamav-freshclam clamav)
            "$PKG" install -y clamav "$daemon_package" "$update_package"
            ;;
        alpine)
            apk add --no-cache clamav clamav-libunrar clamav-daemon clamav-freshclam
            ;;
        arch)
            pacman -Sy --noconfirm clamav
            ;;
        *)
            echo -e "${RED}Unsupported system${NC}"
            exit 1
            ;;
    esac
}

configure_clamd() {
    echo -e "${GREEN}Configure clamd...${NC}"
    
    CLAMD_CONF=""
    if [ -f "/etc/clamd.d/scan.conf" ]; then
        CLAMD_CONF="/etc/clamd.d/scan.conf"
    elif [ -f "/etc/clamd.conf" ]; then
        CLAMD_CONF="/etc/clamd.conf"
    elif [ -f "/etc/clamav/clamd.conf" ]; then
        CLAMD_CONF="/etc/clamav/clamd.conf"
    else
        echo "clamd configuration file not found, please manually configure"
        exit 1
    fi
    cp "$CLAMD_CONF" "$CLAMD_CONF.bak"

    sed -i -E 's|^#\s?LogFileMaxSize\s+.*|LogFileMaxSize 2M|' "$CLAMD_CONF"
    sed -i '/^Example[[:space:]]*$/d' "$CLAMD_CONF"
    # Keep the distribution's socket/PID paths and runtime directory ownership.
    sed -i -E 's|^#\s?DatabaseDirectory\s+.*|DatabaseDirectory /var/lib/clamav|' "$CLAMD_CONF"
    if [ "$CLAMD_CONF" = /etc/clamd.d/scan.conf ]; then
        sed -i -E 's|^#\s?LocalSocket\s+.*|LocalSocket /run/clamd.scan/clamd.sock|' "$CLAMD_CONF"
    fi
}

configure_freshclam() {
    echo -e "${GREEN}Configure freshclam...${NC}"
    
    FRESHCLAM_CONF=""
    if [ -f "/etc/freshclam.conf" ]; then
        FRESHCLAM_CONF="/etc/freshclam.conf"
    elif [ -f "/etc/clamav/freshclam.conf" ]; then
        FRESHCLAM_CONF="/etc/clamav/freshclam.conf"
    else
        echo "freshclam configuration file not found, please manually configure"
        exit 1
    fi
    cp "$FRESHCLAM_CONF" "$FRESHCLAM_CONF.bak"

    sed -i -E 's|^#\s?DatabaseDirectory\s+.*|DatabaseDirectory /var/lib/clamav|' "$FRESHCLAM_CONF"
    sed -i '/^Example[[:space:]]*$/d' "$FRESHCLAM_CONF"
    sed -i '/^DatabaseMirror/d' "$FRESHCLAM_CONF"
    echo "DatabaseMirror database.clamav.net" >> "$FRESHCLAM_CONF"
    sed -i -E 's|^#\s?Checks\s+.*|Checks 12|' "$FRESHCLAM_CONF"
}

find_systemd_unit() {
    local unit
    for unit in "$@"; do
        if systemctl cat "$unit" >/dev/null 2>&1; then
            printf '%s\n' "$unit"
            return 0
        fi
    done
    echo "ClamAV systemd unit not found: $*" >&2
    return 1
}

select_services() {
    [ "$OS" = alpine ] && return 0
    CLAMD_SERVICE=$(find_systemd_unit clamd@scan.service clamav-daemon.service clamd.service)
    FRESHCLAM_SERVICE=$(find_systemd_unit clamav-freshclam.timer freshclam.timer clamav-freshclam.service freshclam.service)
}

download_database() {
    if [ "$OS" = alpine ]; then
        rc-service freshclam stop
    else
        systemctl stop "$FRESHCLAM_SERVICE"
        # A timer may already have launched its corresponding updater service.
        if [[ "$FRESHCLAM_SERVICE" == *.timer ]]; then
            systemctl stop "${FRESHCLAM_SERVICE%.timer}.service"
        fi
    fi
    echo -e "${GREEN}The virus database starts to download...${NC}"
    
    MAX_RETRIES=5
    RETRY_DELAY=60
    ATTEMPT=1
    
    while [ $ATTEMPT -le $MAX_RETRIES ]; do
        echo -e "${YELLOW}Try $ATTEMPT/$MAX_RETRIES: run freshclam...${NC}"
        
        if freshclam --verbose; then
            echo -e "${GREEN}Download successfully${NC}"
            return 0
        fi
        
        if [ $ATTEMPT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}Download failed, wait $RETRY_DELAY seconds and try again...${NC}"
            sleep $RETRY_DELAY
        fi
        
        ATTEMPT=$((ATTEMPT+1))
    done
    
    echo -e "${RED}Error: Unable to download virus database after $MAX_RETRIES attempt${NC}" >&2
    exit 1
}

start_services() {
    echo -e "${GREEN}Start ClamAV...${NC}"
    
    case "$OS" in
        ubuntu|debian)
            systemctl enable --now "$CLAMD_SERVICE"
            systemctl enable --now "$FRESHCLAM_SERVICE"
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            systemctl enable --now "$CLAMD_SERVICE"
            systemctl enable --now "$FRESHCLAM_SERVICE"
            ;;
        alpine)
            rc-update add clamd boot
            rc-update add freshclam boot
            rc-service clamd start
            rc-service freshclam start
            ;;
        arch)
            systemctl enable --now "$CLAMD_SERVICE"
            systemctl enable --now "$FRESHCLAM_SERVICE"
            ;;
        *)
            echo -e "${YELLOW}The service cannot be started automatically. Please start manually!${NC}"
            ;;
    esac
    
   if ! command -v clamscan &> /dev/null; then
        echo -e "${RED}Install ClamAV failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}ClamAV is installed and started${NC}"
}

main() {
    detect_os
    install_clamav
    configure_clamd
    configure_freshclam
    select_services
    download_database
    start_services
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    main "$@"
fi
