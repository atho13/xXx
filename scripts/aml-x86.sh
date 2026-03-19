#!/bin/bash

# 1. Definisi fungsi log di paling atas agar bisa dipanggil kapan saja
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

# 2. Source include file (Optional)
[ -f ./scripts/INCLUDE.sh ] && . ./scripts/INCLUDE.sh

# Exit on error
set -e

# 3. Deteksi Otomatis Arsitektur & Profil
TARGET_ARCH="${ARCH_2:-x86_64}" 

if [[ "$1" == "generic" ]] || [[ "$TARGET_ARCH" == "x86_64" ]]; then
    PROFILE="generic"
    BUILD_MODE="FULL_IMAGE"
    log "INFO" "Target Detected: x86_64 (Full Image Mode)"
elif [[ "$1" == "default" ]] || [[ "$TARGET_ARCH" == "armvirt" ]] || [[ "$TARGET_ARCH" == "arm64" ]]; then
    PROFILE="default"
    BUILD_MODE="ROOTFS_ONLY"
    log "INFO" "Target Detected: Amlogic/ArmVirt (Rootfs Only Mode)"
else
    PROFILE="${1:-generic}"
    BUILD_MODE="FULL_IMAGE"
    log "INFO" "Target Detected: Manual ($PROFILE)"
fi

# 4. DAFTAR PAKET (PACKAGES)
PACKAGES="base-files ca-bundle dnsmasq-full dropbear e2fsprogs firewall4 fstools \
kmod-button-hotplug kmod-nft-offload libc libgcc libustream-mbedtls logd \
mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils ppp ppp-mod-pppoe procd-ujail \
uci uclient-fetch urandom-seed urngd luci luci-compat luci-lib-base \
luci-lib-ip luci-lib-jsonc luci-lib-nixio luci-mod-admin-full \
luci-mod-network kmod-mii luci-mod-status luci-mod-system luci-proto-3g luci-proto-mbim \
mbim-utils picocom minicom luci-proto-ncm luci-proto-ppp luci-proto-qmi screen kmod-tun ttyd \
libqmi libmbim glib2 ipset libcap libcap-bin ruby ruby-yaml kmod-inet-diag kmod-nft-tproxy \
ip-full php8 haproxy tcpdump UDPspeeder irqbalance kmod-dummy bc uhttpd uhttpd-mod-ubus unzip \
uqmi usb-modeswitch uuidgen zstd wwan ziptool zoneinfo-asia zoneinfo-core zram-swap bash \
openssh-sftp-server adb wget-ssl httping htop jq tar coreutils-sleep coreutils-stat \
kmod-nls-utf8 kmod-usb-storage cgi-io chattr comgt comgt-ncm coremark coreutils coreutils-base64 \
coreutils-nohup luci-app-ttyd luci-theme-material wpad-openssl iw iwinfo wireless-regdb kmod-cfg80211"

# Tambahkan paket spesifik berdasarkan mode
if [ "$BUILD_MODE" == "ROOTFS_ONLY" ]; then
    PACKAGES+=" luci-app-amlogic" 
else
    PACKAGES+=" kmod-amazon-ena kmod-e1000e kmod-r8169" 
fi

# 5. FUNGSI UTAMA BUILD
build_firmware() {
    log "INFO" "Starting build for $PROFILE using $BUILD_MODE..."

    if [ "$BUILD_MODE" == "ROOTFS_ONLY" ]; then
        # Mode Amlogic: Buat Rootfs Tar.gz
        make image PROFILE="$PROFILE" \
                   PACKAGES="$PACKAGES"
    else
        # Mode x86: Buat Image Utuh
        make image PROFILE="$PROFILE" \
                   PACKAGES="$PACKAGES"
    fi
    
    local build_status=$?
    if [ "$build_status" -eq 0 ]; then
        log "SUCCESS" "Build completed! Copying files..."
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

# JALANKAN BUILD
build_firmware
