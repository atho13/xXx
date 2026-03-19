#!/bin/bash

# Fungsi Log Sederhana
log() {
    echo -e "[ $(date +%H:%M:%S) ] $*"
}

# Ambil argumen profile dari workflow (generic atau default)
PROFILE=$1
[ -z "$PROFILE" ] && PROFILE="default"

# 1. CORE PACKAGES (Sistem Dasar & Utilitas)
# Menambahkan fstrim untuk kesehatan SSD pada x86
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
coreutils-nohup luci-app-ttyd luci-theme-material wpad-openssl iw iwinfo wireless-regdb kmod-cfg80211 \
fstrim"

# 2. X86_64 DRIVERS (LAN, WIFI & USB)
DRIVERS_X86="kmod-e1000 kmod-e1000e kmod-igb kmod-ixgbe kmod-r8169 kmod-r8168 \
kmod-r8125 kmod-r8101 kmod-tg3 kmod-bnx2 kmod-forcedeth kmod-pcnet32 \
kmod-sky2 kmod-8139cp kmod-8139too kmod-usb-net-rtl8152 kmod-usb-net-asix-ax88179 \
kmod-iwlwifi kmod-ath9k kmod-ath10k"

# 3. OPTIMASI PROSESOR & NETWORK (Khusus x86_64)
# intel-microcode & amd64-microcode: Kestabilan instruksi CPU
# kmod-crypto-aes: Akselerasi AES-NI untuk VPN cepat
# kmod-tcp-bbr: Optimasi speed internet Google BBR
X86_OPTIMIZATION="intel-microcode amd64-microcode kmod-crypto-aes kmod-crypto-authenc \
kmod-crypto-hw-padlock kmod-tcp-bbr kmod-sched-cake kmod-sched-core"

# 4. EXTRA APPS (Statistik Dashboard)
EXTRAS="luci-app-statistics collectd-mod-cpu collectd-mod-interface collectd-mod-memory collectd-mod-load"

# 5. LOGIKA BERDASARKAN TARGET
if [ "$PROFILE" == "generic" ]; then
    log "INFO: Menambahkan Driver & Optimasi x86_64 (AES-NI/BBR/Microcode)..."
    PACKAGES+="$DRIVERS_X86 $X86_OPTIMIZATION $EXTRAS"
else
    # Untuk Amlogic, tambahkan paket integrasi TV Box
    log "INFO: Menambahkan Paket Khusus Amlogic TV Box..."
    PACKAGES+=" luci-app-amlogic kmod-amlogic-meson-gx-mmc"
fi

# 6. EKSEKUSI PROSES MAKE IMAGE
log "INFO: Memulai proses Build Firmware untuk profile: $PROFILE"

# Note: CONFIG_TARGET_ROOTFS_TARGZ=y krusial untuk repack Amlogic
make image PROFILE="$PROFILE" \
           PACKAGES="$PACKAGES" \
           CONFIG_TARGET_ROOTFS_TARGZ=y \
           CONFIG_TARGET_KERNEL_PARTSIZE=256 \
           CONFIG_TARGET_ROOTFS_PARTSIZE=1024

# Cek status akhir
if [ $? -eq 0 ]; then
    log "SUCCESS: Build Firmware Berhasil!"
else
    log "ERROR: Build Firmware Gagal. Periksa log di atas."
    exit 1
fi
