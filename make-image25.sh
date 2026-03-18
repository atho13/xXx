#!/bin/bash

# Source include file
. ./scripts/INCLUDE.sh

# Exit on error
set -e

# 1. Tentukan PROFILE di awal agar Validasi tidak Error
PROFILE="${1:-generic}"
TUNNEL_OPT="${2:-}"
BUILD_FILES="files" # Gunakan nama folder fisik, bukan "PACKAGES"

# Display info Image Builder
make info

# VARIABEL AWAL
MISC=""
EXCLUDED=""

# CORE SYSTEM (Daftar paket Anda)
PACKAGES="apk-mbedtls base-files ca-bundle dnsmasq-full dropbear e2fsprogs firewall4 fstools \
grub2-bios-setup kmod-button-hotplug kmod-nft-offload libc libgcc libustream-mbedtls logd \
mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils ppp ppp-mod-pppoe procd-ujail \
uci uclient-fetch urandom-seed urngd kmod-amazon-ena kmod-amd-xgbe kmod-bnx2 kmod-dwmac-intel \
kmod-e1000e kmod-e1000 kmod-forcedeth kmod-fs-vfat kmod-igb kmod-igc kmod-ixgbe kmod-r8169 \
kmod-tg3 kmod-drm-i915 luci luci-compat luci-lib-base kmod-usb-net-huawei-cdc-ncm kmod-usb-net \
kmod-usb-net-rndis luci-lib-ip luci-lib-ipkg luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
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
luci-app-ttyd luci-theme-material wpad-openssl iw iwinfo wireless-regdb kmod-cfg80211 kmod-80211"

log() {
    local level="$1"
    local msg="$2"
    case "$level" in
       "INFO")    echo -e "[ \033[1;34mINFO\033[0m ] $msg" ;;
       "SUCCESS") echo -e "[ \033[1;32mSUCCESS\033[0m ] $msg" ;;
       "ERROR")   echo -e "[ \033[1;31mERROR\033[0m ] $msg" ;;
       *)         echo -e "[ $level ] $msg" ;;   
    esac
}

# MAIN BUILD
build_firmware() {
    log "INFO" "Starting build for profile '$PROFILE'..."

    # Load Profile & Tunnel Specifics
    #configure_profile_packages "$PROFILE"
    #add_tunnel_packages "$TUNNEL_OPT"
    #configure_release_packages
    
    # Eksekusi Build
    make image PROFILE="$PROFILE" \
               PACKAGES="$PACKAGES $MISC $EXCLUDED"
    
    local build_status=$?
    if [ "$build_status" -eq 0 ]; then
        log "SUCCESS" "Build completed successfully!"
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

# 2. Jalankan Build (Validasi sudah terlewati karena PROFILE diisi di atas)
build_firmware
