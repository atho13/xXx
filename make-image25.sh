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
PACKAGES="
apk-mbedtls base-files ca-bundle dnsmasq-full dropbear e2fsprogs firewall4 fstools grub2-bios-setup kmod-button-hotplug kmod-nft-offload \
libc libgcc libustream-mbedtls logd mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils ppp ppp-mod-pppoe procd-ujail uci \
uclient-fetch urandom-seed urngd kmod-amazon-ena kmod-amd-xgbe kmod-bnx2 kmod-dwmac-intel kmod-e1000e kmod-e1000 kmod-forcedeth \
kmod-fs-vfat kmod-igb kmod-igc kmod-ixgbe kmod-r8169 kmod-tg3 kmod-drm-i915 luci luci-compat luci-lib-base kmod-usb-net-huawei-cdc-ncm \
kmod-usb-net kmod-usb-net-rndis luci-lib-ip luci-lib-ipkg luci-lib-jsonc luci-lib-nixio luci-mod-admin-full luci-mod-network \
kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179 kmod-mii luci-mod-status luci-mod-system \
luci-proto-3g luci-proto-mbim mbim-utils picocom minicom luci-proto-ncm luci-proto-ppp luci-proto-qmi screen kmod-tun ttyd kmod-usb-atm \
kmod-macvlan kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim luci-proto-modemmanager modemmanager modemmanager-rpcd libqmi libmbim glib2 ipset \
libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag kmod-nft-tproxy kmod-tun ip-full php8 haproxy tcpdump UDPspeeder irqbalance \
kmod-dummy bc haproxy uclient-fetch uhttpd uhttpd-mod-ubus unzip uqmi usb-modeswitch uuidgen zstd wwan ziptool zoneinfo-asia zoneinfo-core \
libc zram-swap zoneinfo-core zoneinfo-asia bash screen uhttpd-mod-ubus openssh-sftp-server adb wget-ssl httping htop jq tar unzip \
coreutils-sleep coreutils-stat kmod-nls-utf8 kmod-macvlan usb-modeswitch kmod-usb-storage cgi-io chattr comgt comgt-ncm coremark coreutils \
coreutils-base64 coreutils-nohup kmod-usb-net-rtl8152 kmod-usb-net-sierrawireless kmod-usb-serial-qualcomm kmod-usb-serial-sierrawireless \
luci-app-ttyd luci-theme-material wpad-openssl iw iwinfo wireless-regdb kmod-cfg80211 kmod-80211"

# MAIN BUILD
build_firmware() {
    PROFILE="${1:-generic}"
    TUNNEL_OPT="${2:-}"
    BUILD_FILES="PACKAGES"

    log "INFO" "Starting build for profile '$target_profile' [PACKAGES]..."

    # Load Profile Specifics
    configure_profile_packages "$$PROFILE"
    
    # Load Tunnel Packages
    add_tunnel_packages "$TUNNEL_OPT"
    
    # Load Base/Release Config
    configure_release_packages
    
    # PACKAGES + MISC + EXCLUDED + DISABLED_SERVICES    
    make image PROFILE="$PROFILE" \
               PACKAGES="$PACKAGES $MISC $EXCLUDED" \
               FILES="$BUILD_FILES"
    
    local build_status=$?
    if [ "$build_status" -eq 0 ]; then
        log "SUCCESS" "Build completed successfully!"
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

# Validasi Argumen
if [ -z "$PROFILE" ]; then
    echo "ERROR: Profile not specified."
    exit 1
fi

# Jalankan log function dummy
#if ! command -v log &> /dev/null; then
#fi

# Running Build
build_firmware
