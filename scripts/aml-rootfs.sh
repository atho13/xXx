#!/bin/bash

# Exit on error
set -e

# VARIABEL
PROFILE="default"
TUNNEL_OPT="${1:-no-tunnel}"
ARTIFACT_DIR="../compiled_images"

# Daftar Paket (Khusus Amlogic - Ringan)
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

echo "[ INFO ] Memulai Build Rootfs Only (25.12.1)..."

# KUNCI UTAMA: Aktifkan Rootfs TARGZ, Matikan image lain
make image PROFILE="$PROFILE" \
           PACKAGES="$PACKAGES" \
           CONFIG_TARGET_ROOTFS_TARGZ=y \
           CONFIG_TARGET_ROOTFS_EXT4FS=n \
           CONFIG_TARGET_ROOTFS_SQUASHFS=n \
           CONFIG_GRUB_IMAGES=n \
           CONFIG_ISO_IMAGES=n \
           CONFIG_VHDX_IMAGES=n

# PROSES PEMINDAHAN HASIL
mkdir -p "$ARTIFACT_DIR"

# 1. Pindahkan Rootfs .tar.gz
find bin/targets/armvirt/64/ -type f -name "*.tar.gz" -exec cp {} "$ARTIFACT_DIR/openwrt-amlogic-rootfs.tar.gz" \;

# 2. Pindahkan Manifest (Daftar Paket)
find bin/targets/armvirt/64/ -type f -name "*.manifest" -exec cp {} "$ARTIFACT_DIR/openwrt-amlogic.manifest" \;

# 3. Salin .config untuk cadangan
[ -f .config ] && cp .config "$ARTIFACT_DIR/build.config"

echo "[ SUCCESS ] Rootfs, Manifest, dan Config tersedia di folder compiled_images/"
