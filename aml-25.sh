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
PACKAGES="
base-files ca-bundle dnsmasq-full dropbear e2fsprogs firewall4 fstools \
grub2-bios-setup kmod-button-hotplug kmod-nft-offload libc libgcc libustream-mbedtls logd \
mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils ppp ppp-mod-pppoe procd-ujail \
uci uclient-fetch urandom-seed urngd kmod-amazon-ena kmod-amd-xgbe kmod-bnx2 kmod-dwmac-intel \
kmod-e1000e kmod-e1000 kmod-forcedeth kmod-fs-vfat kmod-igb kmod-igc kmod-ixgbe kmod-r8169 \
kmod-tg3 luci luci-compat luci-lib-base kmod-usb-net-huawei-cdc-ncm kmod-usb-net \
kmod-usb-net-rndis luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
luci-mod-network kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179 \
kmod-mii luci-mod-status luci-mod-system luci-proto-3g luci-proto-mbim mbim-utils picocom minicom \
luci-proto-ncm luci-proto-ppp luci-proto-qmi screen kmod-tun ttyd kmod-usb-atm kmod-macvlan \
kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim luci-proto-modemmanager modemmanager modemmanager-rpcd \
libqmi libmbim glib2 ipset libcap libcap-bin ruby ruby-yaml kmod-inet-diag kmod-nft-tproxy \
ip-full php8 haproxy tcpdump UDPspeeder irqbalance kmod-dummy bc uhttpd uhttpd-mod-ubus unzip \
uqmi usb-modeswitch uuidgen zstd wwan ziptool zoneinfo-asia zoneinfo-core zram-swap bash \
openssh-sftp-server adb wget-ssl httping htop jq tar coreutils-sleep coreutils-stat \
kmod-nls-utf8 kmod-usb-storage cgi-io chattr comgt comgt-ncm coremark coreutils coreutils-base64 \
coreutils-nohup kmod-usb-net-sierrawireless kmod-usb-serial-qualcomm kmod-usb-serial-sierrawireless \
luci-app-ttyd luci-theme-material wpad-openssl iw iwinfo wireless-regdb netdata vnstat2 vnstati2 \
php8 php8-cli php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-iconv \
php8-mod-mbstring"

# PROFILE SPECIFIC
configure_profile_packages() {
    local profile_name="$1"

    if [[ "$profile_name" == *"rpi-2"* ]] || [[ "$profile_name" == *"rpi-3"* ]] || [[ "$profile_name" == *"rpi-4"* ]] || [[ "$profile_name" == *"rpi-5"* ]]; then
        PACKAGES+=" kmod-i2c-bcm2835 i2c-tools kmod-i2c-core kmod-i2c-gpio"
    elif [[ "${ARCH_2:-}" == "x86_64" ]] || [[ "${ARCH_2:-}" == "i386" ]]; then
        PACKAGES+=" kmod-iwlwifi iw-full pciutils wireless-tools"
    fi

    if [[ "${TYPE:-}" == "OPHUB" ]] || [[ "${TYPE:-}" == "ULO" ]]; then
        PACKAGES+=" btrfs-progs kmod-fs-btrfs"
        EXCLUDED+=" -procd-ujail"
    fi
}

# RELEASE SPECIFIC
configure_release_packages() {
    if [[ "${BASE:-}" == "openwrt" ]]; then
        # MISC+=" wpad-openssl iw iwinfo wireless-regdb kmod-cfg80211 kmod-mac80211 luci-app-temp-status"
        MISC+=" -dnsmasq"
        #EXCLUDED+=" -dnsmasq"
    elif [[ "${BASE:-}" == "immortalwrt" ]]; then
        #MISC+=" wpad-openssl iw iwinfo wireless-regdb kmod-cfg80211 kmod-mac80211"
        MISC+=" -dnsmasq -cpusage -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        #EXCLUDED+=" -dnsmasq -cpusage -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        
        #if [[ "${ARCH_2:-}" == "x86_64" ]] || [[ "${ARCH_2:-}" == "i386" ]]; then
            #EXCLUDED+=" -kmod-usb-net-rtl8152-vendor"
        #fi
    fi
}

# MAIN BUILD
build_firmware() {
    local target_profile="$1"
    local tunnel_option="${2:-}"
    #local build_files="files"

    log "INFO" "Starting build for profile '$target_profile' [Tunnel: $tunnel_option]..."

    # Load Profile Specifics
    configure_profile_packages "$target_profile"
    
    # Load Tunnel Packages
    add_tunnel_packages "$tunnel_option"
    
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
    echo "Usage: $0 <profile> [tunnel_option]"
    echo "Tunnel Options: openclash, nikki, insomclash, nikki-passwall, openclash-nikki, openclash-insomclash, openclash-nikki-passwall, no-tunnel"
    exit 1
fi

# Jalankan log function dummy
if ! command -v log &> /dev/null; then
    log() { echo "[$1] $2"; }
fi

# Running Build
build_firmware "$1" "${2:-}"
