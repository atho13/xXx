#!/bin/bash

# =================================================================
# OpenWrt 25.12.1 Build Script for Amlogic (STB)
# Optimized for: APK Manager, Kernel 6.12, Zstandard Support
# =================================================================

# Set default parameters
make_path="${PWD}"
openwrt_dir="imagebuilder"
imagebuilder_path="${make_path}/${openwrt_dir}"
custom_files_path="${make_path}/files"
output_path="${make_path}/output"

# Status Colors
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"

error_msg() { echo -e "${ERROR} ${1}"; exit 1; }

# 1. Downloading OpenWrt ImageBuilder (Zstandard Support)
download_imagebuilder() {
    cd "${make_path}"
    echo -e "${STEPS} Downloading OpenWrt 25.12.1 ImageBuilder..."
    
    # URL Resmi OpenWrt 25.12.1 ArmVirt (Bahan Rootfs Amlogic)
    download_url="https://downloads.openwrt.org"
    
    wget -qO ib_file.tar.zst "${download_url}" || error_msg "Gagal download ImageBuilder!"
    
    # Ekstrak menggunakan zstd
    zstd -d ib_file.tar.zst -c | tar -x -C . --strip-components=0
    mv -f openwrt-imagebuilder-* "${openwrt_dir}"
    rm -f ib_file.tar.zst
    echo -e "${SUCCESS} ImageBuilder siap di folder [ ${openwrt_dir} ]"
}

# 2. Add Custom Files & Fix Permissions (IMPORTANT)
custom_files() {
    cd "${imagebuilder_path}"
    if [[ -d "${custom_files_path}" ]]; then
        echo -e "${STEPS} Memproses File Kustom & Memperbaiki Izin (Permissions)..."
        mkdir -p files
        cp -rf "${custom_files_path}/." files/

        # PAKSA IZIN AKSES (ROOT 0:0 dan 0755/0644)
        # 1. Semua folder jadi 755
        find files/ -type d -exec chmod 755 {} +
        # 2. Semua file sistem inti jadi 755 (Executable)
        for dir in "bin" "sbin" "usr/bin" "usr/sbin" "etc/init.d" "etc/uci-defaults"; do
            [ -d "files/$dir" ] && find "files/$dir" -type f -exec chmod 755 {} +
        done
        # 3. Semua file config jadi 644 (Read Only)
        [ -d "files/etc/config" ] && find "files/etc/config" -type f -exec chmod 644 {} +
        
        # NOTE: Kepemilikan root disimulasikan oleh fakeroot saat 'make'
        echo -e "${SUCCESS} Izin file berhasil disetel."
    fi
}

# 3. Rebuild OpenWrt Firmware (Daftar Paket Lengkap)
rebuild_firmware() {
    cd "${imagebuilder_path}"
    echo -e "${STEPS} Membangun Rootfs dengan APK Manager & Driver WiFi..."

    # Paket Driver WiFi, USB LAN, Modem, dan Tool Sistem
    my_packages="\
        base-files ca-bundle dnsmasq-full -dnsmasq dropbear firewall4 nftables \
        kmod-nft-offload kmod-amazon-ena kmod-amd-xgbe kmod-bnx2 kmod-dwmac-intel \
        kmod-e1000e kmod-e1000 kmod-igb kmod-igc kmod-ixgbe kmod-r8169 kmod-tg3 \
        kmod-brcmfmac brcmfmac-firmware-43430-sdio brcmfmac-firmware-43455-sdio \
        kmod-rtl8xxxu rtl8188eu-firmware kmod-rtw88 kmod-usb-net-rtl8150 \
        kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179 kmod-mii \
        kmod-usb-storage kmod-usb-net-rndis luci luci-compat luci-lib-base \
        luci-mod-admin-full luci-mod-network luci-mod-status luci-mod-system \
        luci-app-ttyd ttyd bash wget-ssl htop jq tar zstd luci-app-cpufreq \
        irqbalance btrfs-progs e2fsprogs f2fs-tools xfsprogs unzip coreutils-sleep \
        python3-pip python3-setuptools coremark apk \
        -wpad-basic wpad-basic-mbedtls iw iwinfo hostapd-common"

    # EKSEKUSI DENGAN FAKEROOT (Untuk Izin Root 0:0)
    fakeroot make image PROFILE="generic" PACKAGES="${my_packages}" FILES="files" V=s

    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} Build Selesai!"
        mkdir -p "${output_path}"
        cp bin/targets/armvirt/64/*.tar.* "${output_path}/"
        echo -e "${INFO} Hasil Rootfs ada di folder: ${output_path}"
    else
        error_msg "Build Gagal!"
    fi
}

# Jalankan Fungsi Utama
download_imagebuilder
custom_files
rebuild_firmware
