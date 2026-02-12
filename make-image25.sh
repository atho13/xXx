#!/bin/bash

# Source include file
. ./scripts/INCLUDE.sh

# Exit on error
set -e

# Display Profile
make info

# VARIABEL
PROFILE=""
PACKAGES=""
MISC=""
EXCLUDED=""

# CORE SYSTEM
PACKAGES+=" base-files bash bc blkid block-mount btrfs-progs busybox bzip2 ip-full libc \
        cgi-io comgt comgt-ncm coreutils coreutils-stat coreutils-base64 coreutils-nohup \
        curl dosfstools e2fsprogs exfat-mkfs f2fs-tools f2fsck fdisk gawk \
        jq jshn nano htop liblucihttp-lua ca-bundle losetup lsblk lscpu mkf2fs mount-utils \
        openssl-util parted iconv gzip perlbase-file perlbase-unicode perlbase-utf8 \
        perlbase-essential perlbase-time perlbase-xsloader rpcd rpcd-mod-file ziptool uuidgen \
        rpcd-mod-iwinfo rpcd-mod-luci rpcd-mod-rrdns uhttpd uhttpd-mod-ubus openssh-sftp-server \
        ppp ppp-mod-pppoe pv ntfs-3g tar ttyd kmod-usb2 kmod-usb-net-rndis wwan httping \
        uclient-fetch unzip uqmi usb-modeswitch xz xz-utils zoneinfo-asia zoneinfo-core \
        luci luci-compat luci-lib-base kmod-usb-net-huawei-cdc-ncm kmod-usb-net \
        luci-lib-ip luci-lib-ipkg luci-lib-jsonc luci-lib-nixio luci-mod-admin-full luci-mod-network \
        luci-mod-status luci-mod-system luci-proto-3g luci-proto-mbim mbim-utils \
        luci-proto-ncm luci-proto-ppp luci-proto-qmi screen kmod-tun \
        kmod-usb-wdm kmod-usb-net-qmi-wwan luci-proto-qmi kmod-usb-net-cdc-ether \
        kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils kmod-usb-serial-qualcomm \
        kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim modemmanager"

# THEMES
PACKAGES+=" luci-theme-material"

# MISC
MISC+=" internet-detector internet-detector-mod-modem-restart luci-app-internet-detector luci-app-ttyd luci-app-tinyfm"

# MAIN BUILD
build_firmware() {
    local target_profile="$1"
    local build_files="files"

    log "INFO" "Starting build for profile '$target_profile' [Tunnel: $tunnel_option]..."

    # Load Profile Specifics
    configure_profile_packages "$target_profile"
    
    # Load Base/Release Config
    configure_release_packages

    # PACKAGES + MISC + EXCLUDED    
    make image PROFILE="$target_profile" PACKAGES="$PACKAGES $MISC $EXCLUDED" FILES="$build_files"
    
    local build_status=$?
    if [ "$build_status" -eq 0 ]; then
        log "SUCCESS" "Build completed successfully!"
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

# Validasi Argumen
if [ -z "${1:-}" ]; then
    echo "ERROR: Profile not specified."
    exit 1
fi

# Jalankan log function dummy
if ! command -v log &> /dev/null; then
    log() { echo "[$1] $2"; }
fi

# Running Build
build_firmware "$1" "${2:-}"
