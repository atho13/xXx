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
uci uclient-fetch urandom-seed urngd luci luci-compat luci-lib-base \
luci-mod-admin-full luci-mod-network luci-mod-status luci-mod-system \
luci-proto-3g luci-proto-ncm luci-proto-ppp luci-proto-qmi screen kmod-tun ttyd \
libqmi libmbim glib2 ipset ruby ruby-yaml php8 haproxy tcpdump htop jq tar \
bash openssh-sftp-server wget-ssl luci-app-amlogic luci-theme-material"

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
