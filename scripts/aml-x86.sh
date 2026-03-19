#!/bin/bash

# Fungsi Log
log() {
    echo -e "[ $(date +%H:%M:%S) ] $*"
}

# Ambil argumen profile
PROFILE=$1
[ -z "$PROFILE" ] && PROFILE="default"

# 1. CORE PACKAGES (Sistem Dasar)
# Pastikan ada spasi di akhir kutip
CORE_PACKAGES="base-files ca-bundle dnsmasq-full dropbear e2fsprogs firewall4 fstools \
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
fstrim "

# 2. X86_64 DRIVERS (LAN & WIFI)
DRIVERS_X86="kmod-e1000 kmod-e1000e kmod-igb kmod-ixgbe kmod-r8169 kmod-r8168 \
kmod-r8125 kmod-r8101 kmod-tg3 kmod-bnx2 kmod-forcedeth kmod-pcnet32 \
kmod-sky2 kmod-8139cp kmod-8139too kmod-usb-net-rtl8152 kmod-usb-net-asix-ax88179 \
kmod-iwlwifi kmod-ath9k kmod-ath10k "

# 3. OPTIMASI X86 (AES-NI & BBR)
# Catatan: kmod-crypto-aesni adalah nama paket yang benar untuk x86
X86_OPTIMIZATION="intel-microcode amd64-microcode kmod-crypto-aesni kmod-crypto-authenc \
kmod-tcp-bbr kmod-sched-cake kmod-sched-core "

# 4. EXTRA APPS
EXTRAS="luci-app-statistics collectd-mod-cpu collectd-mod-interface collectd-mod-memory "

# 5. LOGIKA PENGGABUNGAN (DIPERBAIKI AGAR TIDAK MENEMPEL)
PACKAGES="$CORE_PACKAGES"

if [ "$PROFILE" == "generic" ]; then
    log "INFO: Menambahkan Driver & Optimasi x86_64..."
    PACKAGES="$PACKAGES $DRIVERS_X86 $X86_OPTIMIZATION $EXTRAS"
else
    log "INFO: Menambahkan Paket Khusus Amlogic TV Box..."
    PACKAGES="$PACKAGES luci-app-amlogic kmod-amlogic-meson-gx-mmc "
fi

# 6. SCRIPT AUTOSTART (Aktivasi BBR & SSD Trim)
# File ini akan disisipkan ke dalam folder /etc/uci-defaults/ di firmware
mkdir -p files/etc/uci-defaults
cat <<EOF > files/etc/uci-defaults/99-custom-settings
#!/bin/sh
# Aktifkan Google BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# Jalankan fstrim sekali saat boot jika x86
[ -x /sbin/fstrim ] && /sbin/fstrim -av
exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-settings

# 7. EKSEKUSI BUILD
log "INFO: Memulai proses Build Firmware untuk profile: $PROFILE"

make image PROFILE="$PROFILE" \
           PACKAGES="$PACKAGES" \
           FILES="files" \
           CONFIG_TARGET_ROOTFS_TARGZ=y \
           CONFIG_TARGET_KERNEL_PARTSIZE=256 \
           CONFIG_TARGET_ROOTFS_PARTSIZE=1024

if [ $? -eq 0 ]; then
    log "SUCCESS: Build Firmware Selesai!"
else
    log "ERROR: Build Gagal. Cek log di atas."
    exit 1
fi
