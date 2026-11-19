#!/bin/bash

# Install FFmpeg
# Support Ubuntu/Debian/CentOS/RHEL/Rocky/AlmaLinux/TencentOS/OpenCloudOS/CTyunOS/Alpine/Arch Linux

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

OS=""
VERSION=""

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$(printf '%s' "$ID" | tr '[:upper:]' '[:lower:]')
        VERSION=$VERSION_ID
        if [ -n "$ID_LIKE" ]; then
            OS_LIKE=$ID_LIKE
        fi
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
        OS_LIKE="rhel"
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

install_rpm_ffmpeg() {
    local release="" repo_family=el
    # Prefer the distribution's package (EPOL / CTyunOS included).
    if "$PKG" -q list ffmpeg >/dev/null 2>&1; then
        "$PKG" install -y ffmpeg
        return
    fi
    case "$OS" in
        centos|rhel|rocky|almalinux) release="${VERSION%%.*}" ;;
        tencentos)
            case "${VERSION%%.*}" in 2) release=7 ;; 3) release=8 ;; esac
            ;;
        opencloudos)
            case "${VERSION%%.*}" in 7|8) release="${VERSION%%.*}" ;; esac
            ;;
        fedora) repo_family=fedora; release="${VERSION%%.*}" ;;
    esac
    if [[ ! "$release" =~ ^[0-9]+$ ]]; then
        echo "FFmpeg is unavailable in the configured $OS $VERSION repositories. Enable a distribution-compatible multimedia repository." >&2
        return 1
    fi
    "$PKG" install -y "https://download1.rpmfusion.org/free/$repo_family/rpmfusion-free-release-$release.noarch.rpm"
    "$PKG" install -y ffmpeg
}

install_ffmpeg() {
    echo -e "${GREEN}Detected system: $OS $VERSION, start to install FFmpeg...${NC}"
    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y ffmpeg
            ;;
        centos|rhel|fedora|rocky|almalinux|tencentos|opencloudos|ctyunos)
            prepare_rpm
            prepare_extra_repo
            install_rpm_ffmpeg
            ;;
        alpine)
            apk update
            apk add ffmpeg
            ;;
        arch)
            pacman -Sy --noconfirm ffmpeg
            ;;
        *)
            echo -e "${RED}Unsupported system: $OS $VERSION${NC}"
            exit 1
            ;;
    esac
}

check_ffmpeg_install() {
    if command -v ffmpeg >/dev/null 2>&1; then
        echo -e "${GREEN}FFmpeg is installed. Version: $(ffmpeg -version | head -n 1)${NC}"
    else
        echo -e "${RED}FFmpeg installation failed or not found.${NC}"
        exit 1
    fi
}

main() {
    detect_os
    install_ffmpeg
    check_ffmpeg_install
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    main "$@"
fi
