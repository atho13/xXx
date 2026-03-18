#!/bin/bash

# Source include file
[ -f ./scripts/INCLUDE.sh ] && . ./scripts/INCLUDE.sh

# Exit on error
set -e

# 1. Logika Cerdas: Otomatis pilih profil 'default' untuk Amlogic
if [[ "$1" == "no-tunnel" ]] || [[ -z "$1" ]] || [[ "$1" == "default" ]]; then
   PROFILE="default"
   TUNNEL_OPT="${1:-no-tunnel}"
else
   PROFILE="$1"
   TUNNEL_OPT="${2:-no-tunnel}"
fi

# Fungsi Log Sederhana
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

# CORE SYSTEM (Daftar paket Amlogic yang sudah dibersihkan)
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
luci-app-ttyd luci-theme-material wpad-openssl iw iwinfo wireless-regdb kmod-cfg80211"

# MAIN BUILD
build_firmware() {
    log "INFO" "Building ONLY Rootfs for profile: $PROFILE"

    # KUNCI UTAMA: Hanya aktifkan Rootfs TARGZ, matikan image lain agar cepat
    make image PROFILE="$PROFILE" \
               PACKAGES="$PACKAGES" \
               CONFIG_TARGET_ROOTFS_TARGZ=y \
               CONFIG_TARGET_ROOTFS_EXT4FS=n \
               CONFIG_TARGET_ROOTFS_SQUASHFS=n \
               CONFIG_GRUB_IMAGES=n \
               CONFIG_ISO_IMAGES=n \
               CONFIG_VHDX_IMAGES=n
    
    local build_status=$?
    if [ "$build_status" -eq 0 ]; then
        log "INFO" "Verifying Rootfs file..."
        # Cari file .tar.gz di folder bin
        local rootfs_file=$(find bin/targets/ -type f -name "*.tar.gz" | head -n 1)
        
        if [ -n "$rootfs_file" ]; then
            mkdir -p ../compiled_images
            # Beri nama standar agar REPACK25.sh mudah menemukannya
            cp "$rootfs_file" "../compiled_images/openwrt-armvirt-64-default-rootfs.tar.gz"
            log "SUCCESS" "Rootfs created: openwrt-armvirt-64-default-rootfs.tar.gz"
        else
            log "ERROR" "Rootfs .tar.gz NOT FOUND!"
            exit 1
        fi
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

build_firmware
