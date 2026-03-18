#!/bin/bash

# Source include file
[ -f ./scripts/INCLUDE.sh ] && . ./scripts/INCLUDE.sh

# Exit on error
set -e

# 1. Konfigurasi Target (Otomatis ke Amlogic ArmVirt)
PROFILE="default"
TUNNEL_OPT="${2:-no-tunnel}"
ARTIFACT_DIR="../compiled_images"

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

# DAFTAR PAKET (Disesuaikan untuk Amlogic 25.12.0)
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
php8-mod-mbstring luci-app-amlogic luci-theme-material"

# MAIN BUILD
build_rootfs() {
    log "INFO" "Memulai Build Rootfs Only untuk Amlogic (25.12.0)..."

    # KUNCI: Aktifkan Rootfs TARGZ, Matikan pembuatan image disk (.img, .iso, .grub)
    # Ini akan membuat proses build sangat cepat
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
        log "INFO" "Memindahkan hasil Rootfs ke folder artifacts..."
        
        # Buat folder tujuan di root workspace
        mkdir -p "$ARTIFACT_DIR"
        
        # Cari file .tar.gz (Rootfs) dan salin ke folder tujuan
        # Gunakan nama yang konsisten agar mudah dikenali
        find bin/targets/armvirt/64/ -type f -name "*.tar.gz" -exec cp {} "$ARTIFACT_DIR/FRDMX_Amlogic_Rootfs_$(date +%Y%m%d).tar.gz" \;
        
        # Salin juga file manifest untuk daftar paket
        find bin/targets/armvirt/64/ -type f -name "*.manifest" -exec cp {} "$ARTIFACT_DIR/FRDMX_Amlogic_Rootfs_$(date +%Y%m%d).manifest" \;
        
        log "SUCCESS" "Build Rootfs SELESAI! File tersedia di folder compiled_images."
    else
        log "ERROR" "Build gagal dengan exit code $build_status"
        exit "$build_status"
    fi
}

# Jalankan fungsi
build_rootfs
