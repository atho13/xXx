#!/bin/bash

log() {
    echo -e "[ $(date +%H:%M:%S) ] $*"
}

# Ambil input target dari workflow (Amlogic atau X86-64)
TARGET_TYPE=$1 

# 1. DAFTAR PAKET LENGKAP
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

# 2. LOGIKA PAKET BERDASARKAN TARGET
if [ "$TARGET_TYPE" == "generic" ]; then
    log "INFO: Menambahkan Driver & Optimasi x86_64..."
    DRIVERS_X86="kmod-e1000 kmod-e1000e kmod-igb kmod-ixgbe kmod-r8169 kmod-r8168 kmod-r8125"
    PACKAGES="$PACKAGES $DRIVERS_X86"
fi

# 3. KONFIGURASI OTOMATIS (IP STATIS & BBR)
mkdir -p files/etc/uci-defaults
cat <<EOF > files/etc/uci-defaults/99-custom-settings
#!/bin/sh
# 1. Aktifkan Google BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 2. Pengaturan Network (IP Statis 192.168.1.1)
# Menghapus jembatan (bridge) jika ada dan mengatur eth0 sebagai LAN utama
uci set network.lan.device='eth0'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.1.1'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.1.1'
uci set network.lan.dns='8.8.8.8 1.1.1.1'

# Simpan dan terapkan
uci commit network
/etc/init.d/network restart

# 3. Jalankan fstrim jika x86
[ -x /sbin/fstrim ] && /sbin/fstrim -av
exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-settings

# 4. EKSEKUSI BUILD (PROFILE generic)
log "INFO: Memulai proses Build Firmware..."

make image PROFILE="generic" \
           PACKAGES="$PACKAGES" \
           FILES="files" \
           CONFIG_TARGET_ROOTFS_TARGZ=y \
           CONFIG_TARGET_KERNEL_PARTSIZE=256 \
           CONFIG_TARGET_ROOTFS_PARTSIZE=1024

if [ $? -eq 0 ]; then
    log "SUCCESS: Build Selesai!"
else
    log "ERROR: Build Gagal!"
    exit 1
fi
