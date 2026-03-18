#!/bin/bash

# Source include file
[ -f ./scripts/INCLUDE.sh ] && . ./scripts/INCLUDE.sh

# Exit on error
set -e

# VARIABEL AWAL
MISC=""
EXCLUDED=""

# CORE SYSTEM (Daftar paket yang sudah dibersihkan dari driver x86/PC)
PACKAGES="base-files ca-bundle dnsmasq-full dropbear e2fsprogs firewall4 fstools \
kmod-button-hotplug kmod-nft-offload libc libgcc libustream-mbedtls logd \
mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils ppp ppp-mod-pppoe procd-ujail \
uci uclient-fetch urandom-seed urngd luci luci-compat luci-lib-base kmod-usb-net-huawei-cdc-ncm \
kmod-usb-net kmod-usb-net-rndis luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
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
php8-cli php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-iconv \
php8-mod-mbstring"

# Fungsi Tunnel (Perbaikan sintaksis *)
add_tunnel_packages() {
    local tunnel="$1"
    case "$tunnel" in
        "openclash") PACKAGES+=" luci-app-openclash" ;;
        "nikki")     PACKAGES+=" luci-app-nikki" ;;
        "passwall")  PACKAGES+=" luci-app-passwall" ;;
        "no-tunnel"|"") log "INFO" "No tunnel selected." ;;
        *) log "INFO" "Custom tunnel: $tunnel" ;;
    esac
}

# MAIN BUILD
build_firmware() {
    local target_profile="$1"
    local tunnel_option="${2:-no-tunnel}"
    local build_files="files"

    log "INFO" "Starting build for profile '$target_profile' [Tunnel: $tunnel_option]..."

    # Jalankan fungsi pendukung
    add_tunnel_packages "$tunnel_option"
    
    # Buat folder files jika belum ada agar tidak error
    mkdir -p "$build_files"

    # Perintah Build khusus Amlogic Repack
    make image PROFILE="$target_profile" \
               PACKAGES="$PACKAGES $MISC $EXCLUDED" \
               FILES="$build_files" \
               CONFIG_TARGET_ROOTFS_TARGZ=y \
               CONFIG_TARGET_KERNEL_PARTSIZE=256 \
               CONFIG_TARGET_ROOTFS_PARTSIZE=2048
    
    local build_status=$?
    if [ "$build_status" -eq 0 ]; then
        log "SUCCESS" "Rootfs created successfully!"
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

# Fungsi Log jika belum ada
if ! command -v log &> /dev/null; then
    log() { echo -e "[\033[1;34m $1 \033[0m] $2"; }
fi

# Jalankan (Default profile untuk armvirt adalah 'default')
build_firmware "${1:-default}" "${2:-no-tunnel}"
