#!/bin/bash
set -e

# Daftar Paket (Sudah termasuk driver WiFi & APK Manager 25.12)
PACKAGES="base-files ca-bundle dnsmasq-full -dnsmasq dropbear e2fsprogs firewall4 fstools \
kmod-nft-offload libc libgcc libustream-mbedtls logd mkf2fs mtd netifd nftables \
odhcp6c odhcpd-ipv6only partx-utils ppp ppp-mod-pppoe procd-ujail uci uclient-fetch \
kmod-fs-vfat kmod-igb kmod-r8169 luci luci-compat luci-lib-base luci-mod-admin-full \
luci-mod-network luci-mod-status luci-mod-system luci-app-ttyd ttyd bash wget-ssl \
htop jq tar zstd kmod-brcmfmac brcmfmac-firmware-43430-sdio brcmfmac-firmware-43455-sdio \
kmod-rtl8xxxu rtl8188eu-firmware iw wpad-basic-mbedtls luci-app-cpufreq"

echo "Building Rootfs..."
make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="../files" V=s
