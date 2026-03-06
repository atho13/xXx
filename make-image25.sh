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

#CORE SYSTEM
my_package=" dnsmasq-full libc block-mount zram-swap zoneinfo-core zoneinfo-asia bash screen \
uhttpd uhttpd-mod-ubus luci luci-ssl openssh-sftp-server adb curl wget-ssl \
httping htop jq tar unzip coreutils-base64 coreutils-sleep coreutils-stat \
kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179 \
kmod-mii kmod-usb-net kmod-usb-wdm kmod-usb-net-rndis kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm kmod-usb-net-sierrawireless \
kmod-usb-net-qmi-wwan uqmi luci-proto-qmi kmod-usb-acm kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-mbim umbim \
kmod-usb-serial kmod-usb-serial-option kmod-usb-serial-wwan kmod-usb-serial-qualcomm kmod-usb-serial-sierrawireless \
modemmanager luci-proto-modemmanager libqmi libmbim glib2 dbus dbus-utils ppp chat kmod-usb-ehci kmod-usb3 \
qmi-utils mbim-utils usbutils luci-proto-ncm kmod-usb-ohci kmod-usb-uhci kmod-usb2 \
kmod-nls-utf8 kmod-macvlan usb-modeswitch xmm-modem luci-proto-xmm kmod-usb-storage luci-theme-material \
internet-detector internet-detector-mod-modem-restart luci-app-internet-detector luci-app-ttyd luci-app-tinyfm"

# MAIN BUILD
build_firmware() {
    local target_profile="$1"
    local build_files="my_package"

    log "INFO" "Starting build for profile '$target_profile' [my_packages]..."

    # PACKAGES + MISC + EXCLUDED + DISABLED_SERVICES    
    make image PROFILE="$target_profile" \
               #PROFILE="" PACKAGES="${my_packages}" FILES="files"
               PACKAGES="$PACK25 $MISC $EXCLUDED" \
               #PACKAGES="$MISC $EXCLUDED" \
               FILES="$build_files"
    
    local build_status=$?
    if [ "$build_status" -eq 0 ]; then
        log "SUCCESS" "Build completed successfully!"
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

# Jalankan log function dummy
if ! command -v log &> /dev/null; then
    log() { echo "[$1] $2"; }
fi

# Running Build
build_firmware "$1" "${2:-}"
