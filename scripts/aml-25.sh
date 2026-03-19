#!/bin/bash
# Set default parameters
make_path="${PWD}"
openwrt_dir="imagebuilder"
imagebuilder_path="${make_path}/${openwrt_dir}"
custom_files_path="${make_path}/config/imagebuilder/files"
custom_config_file="${make_path}/config/imagebuilder/config"
output_path="${make_path}/output"
tmp_path="${imagebuilder_path}/tmp"
unpack_path="${tmp_path}/unpacked_rootfs"

# Set default parameters
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
#
#================================================================================================

# Output error message and abort script execution
error_msg() {
    echo -e "${ERROR} ${1}"
    exit 1
}

# Downloading OpenWrt ImageBuilder
download_imagebuilder() {
    cd ${make_path}
    echo -e "${STEPS} Downloading OpenWrt ImageBuilder..."

    # Downloading imagebuilder files
    if [[ "${op_sourse}" == "immortalwrt" ]]; then
        download_url="immortalwrt.kyarucloud.moe"
    else
        download_url="downloads.openwrt.org"
    fi
    download_file="https://${download_url}/releases/${op_branch}/targets/armsr/armv8/${op_sourse}-imagebuilder-${op_branch}-armsr-armv8.Linux-x86_64.tar.zst"
    curl -fsSOL ${download_file}
    [[ "${?}" -eq "0" ]] || error_msg "Failed to download: [ ${download_file} ]"

    # Unzip and change the directory name
    tar -I zstd -xvf *-imagebuilder-*.tar.zst -C . && sync && rm -f *-imagebuilder-*.tar.zst
    mv -f *-imagebuilder-* ${openwrt_dir}

    sync && sleep 3
    echo -e "${INFO} [ ${make_path} ] directory contents: \n$(ls -lh . 2>/dev/null)"
}

# Adjust related files in the ImageBuilder directory
adjust_settings() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Adjusting ImageBuilder .config settings..."

    # For .config file
    if [[ -s ".config" ]]; then
        # Root filesystem archives
        sed -i "s|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g" .config
        # Root filesystem images
        sed -i "s|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g" .config
        sed -i "s|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g" .config
    else
        echo -e "${INFO} [ ${imagebuilder_path} ] directory contents: \n$(ls -lh . 2>/dev/null)"
        error_msg "No .config file found in [ ${download_file} ]."
    fi

    # For other files
    # ......

    sync && sleep 3
    echo -e "${INFO} [ ${imagebuilder_path} ] directory contents: \n$(ls -lh . 2>/dev/null)"
}

# Add custom packages
# If there is a custom package or ipk you would prefer to use create a [ packages ] directory,
# If one does not exist and place your custom ipk within this directory.
custom_packages() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Adding custom packages..."

    # Create a [ packages ] directory
    [[ -d "packages" ]] || mkdir packages
    cd packages

    sync && sleep 3
    echo -e "${INFO} [ packages ] directory contents: \n$(ls -lh . 2>/dev/null)"
}

# Add custom packages, lib, theme, app and i18n, etc.
custom_config() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Loading custom package configuration..."

    config_list=""
    if [[ -s "${custom_config_file}" ]]; then
        config_list="$(sed -n 's/^CONFIG_PACKAGE_\(.*\)=y$/\1/p' "${custom_config_file}" | tr '\n' ' ')"
        echo -e "${INFO} Custom package list: \n$(echo "${config_list}" | tr ' ' '\n')"
    else
        echo -e "${INFO} No custom configuration file found, skipped."
    fi
}

# Add custom files
# The FILES variable allows custom configuration files to be included in images built with Image Builder.
# The [ files ] directory should be placed in the Image Builder root directory where you issue the make command.
custom_files() {
    # Pindah ke folder imagebuilder
    cd "${imagebuilder_path}" || { echo "Gagal masuk ke direktori build"; exit 1; }

    if [[ -d "${custom_files_path}" ]]; then
        echo -e "Menyalin file kustom dari: ${custom_files_path}"
        
        # 1. Pastikan folder target bersih
        mkdir -p files
        
        # 2. Salin semua file
        cp -rf "${custom_files_path}/." files/

        # 3. Atur izin akses (Rooting files)
        # Menggunakan sudo agar file di dalam firmware benar-benar milik root
        sudo chown -R 0:0 files/
        find files/ -type d -exec chmod 755 {} +
        find files/ -type f -exec chmod 644 {} +
        
        # Berikan izin eksekusi untuk skrip init (jika ada)
        [ -d "files/etc/init.d" ] && sudo chmod -R +x files/etc/init.d/*
        
        echo "File kustom berhasil diproses."
    fi
}

# Rebuild OpenWrt firmware
rebuild_firmware() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Building OpenWrt firmware with Image Builder..."

    # Selecting default packages, lib, theme, app and i18n, etc.
    my_packages="\
        dnsmasq-full attr base-files bash bc blkid block-mount blockd bsdtar btrfs-progs busybox bzip2 \
        cgi-io chattr comgt comgt-ncm coremark coreutils coreutils-base64 coreutils-nohup \
        coreutils-truncate curl dumpe2fs e2freefrag e2fsprogs fping exfat-mkfs f2fs-tools \
        f2fsck fdisk getopt git gzip iconv jq kmod-brcmfmac kmod-brcmutil libjson-script \
        liblucihttp liblucihttp-lua lsattr lsblk lscpu mkf2fs mount-utils openssl-util wget-ssl \
        perl-http-date perlbase-file perlbase-getopt perlbase-time perlbase-unicode perlbase-utf8 \
        ppp ppp-mod-pppoe pv rename resize2fs runc tar tini ttyd tune2fs luci-app-ttyd luci-theme-material \
        uclient-fetch uhttpd uhttpd-mod-ubus unzip uqmi usb-modeswitch uuidgen zstd wwan xfs-fsck \
        xfs-mkfs xz xz-utils ziptool zoneinfo-asia zoneinfo-core libc zram-swap zoneinfo-core \
        zoneinfo-asia bash screen uhttpd-mod-ubus openssh-sftp-server adb wget-ssl httping htop jq tar \
        unzip coreutils-sleep coreutils-stat kmod-nls-utf8 kmod-macvlan usb-modeswitch kmod-usb-storage \
        \
        luci luci-compat luci-lib-base kmod-usb-net-huawei-cdc-ncm kmod-usb-net kmod-usb-net-rndis \
        luci-lib-ip luci-lib-ipkg luci-lib-jsonc luci-lib-nixio luci-mod-admin-full luci-mod-network \
        kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179 kmod-mii \
        luci-mod-status luci-mod-system luci-proto-3g luci-proto-mbim mbim-utils picocom minicom \
        luci-proto-ncm luci-proto-ppp luci-proto-qmi screen kmod-tun ttyd kmod-usb-atm kmod-macvlan \
        kmod-usb-wdm kmod-usb-net-qmi-wwan luci-proto-qmi kmod-usb-net-cdc-ether dbus dbus-utils chat \
        kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils kmod-usb-serial-qualcomm \
        kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim luci-proto-modemmanager modemmanager modemmanager-rpcd libqmi libmbim glib2 \
        \
        ipset libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag kmod-nft-tproxy kmod-tun ip-full ca-bundle \
        php8 php8-cli php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-curl \
        php8-mod-iconv php8-mod-mbstring php8-cgi haproxy tcpdump UDPspeeder fping irqbalance kmod-dummy procps-ng-watch \
        procps-ng-pkill dos2unix git-http bc python3-pip python3-setuptools python3-requests \
        \
        ${config_list} \
        "

    # Rebuild firmware
    make image PROFILE="" PACKAGES="${my_packages}" FILES="files"

    sync && sleep 3
    echo -e "${INFO} [ ${openwrt_dir}/bin/targets/*/*/ ] directory contents: \n$(ls -lh bin/targets/*/*/ 2>/dev/null)"
    echo -e "${INFO} Firmware build completed successfully."
}

# Custom settings after rebuild
custom_settings() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Applying post-build customizations..."

    # Clean up temporary and output directories
    [[ -d "${tmp_path}" ]] && rm -rf "${tmp_path:?}"/* || mkdir -p "${tmp_path}"
    [[ -d "${output_path}" ]] && rm -rf "${output_path:?}"/* || mkdir -p "${output_path}"

    # Find the original *rootfs.tar.gz file
    original_archive="$(ls -1 bin/targets/*/*/*rootfs.tar.gz 2>/dev/null | head -n 1)"

    # Check if the original archive exists
    if [[ ! -f "${original_archive}" ]]; then
        error_msg "No rootfs.tar.gz archive found in build output."
    else
        echo -e "${INFO} Found rootfs archive: ${original_archive}"

        # Get the filename and path
        original_filename="$(basename "${original_archive}")"
        original_path="$(dirname "${original_archive}")"

        # Unpack the original archive
        echo -e "${INFO} Unpacking ${original_filename}..."
        mkdir -p "${unpack_path}"
        tar -xzpf "${original_archive}" -C "${unpack_path}"

        # Modify etc/openwrt_release
        release_file="${unpack_path}/etc/openwrt_release"
        if [[ -f "${release_file}" ]]; then
            echo -e "${INFO} Updating etc/openwrt_release..."
            {
                echo "DISTRIB_SOURCEREPO='github.com/${op_sourse}/${op_sourse}'"
                echo "DISTRIB_SOURCECODE='${op_sourse}'"
                echo "DISTRIB_SOURCEBRANCH='${op_branch}'"
            } >>"${release_file}"
        else
            error_msg "${release_file} not found."
        fi

        # Repack the modified root filesystem
        echo -e "${INFO} Repacking into ${original_filename}..."
        (cd "${unpack_path}" && tar -czpf "${tmp_path}/${original_filename}" ./)

        # Move the repacked archive to the output directory
        echo -e "${INFO} Moving modified rootfs to output directory..."
        mv -f "${tmp_path}/${original_filename}" "${output_path}/"
        # Copy the config file to the output directory
        cp -f .config "${output_path}/config" || true
    fi

    sync && sleep 3
    cd ${make_path}
    rm -rf "${imagebuilder_path}"
    echo -e "${INFO} [ ${output_path} ] directory contents: \n$(ls -lh ${output_path}/ 2>/dev/null)"
    echo -e "${INFO} Post-build customizations applied successfully."
}

# Show welcome message
echo -e "${STEPS} Welcome to the OpenWrt Image Builder."
[[ -x "${0}" ]] || error_msg "Please grant execution permission: [ chmod +x ${0} ]"
[[ -z "${1}" ]] && error_msg "Please specify the OpenWrt source and branch, e.g. [ ${0} openwrt:25.12.0 ]"
[[ "${1}" =~ ^[a-z]{3,}:[0-9]+ ]] || error_msg "Invalid parameter format. Expected <source:branch>, e.g. openwrt:25.12.0"
op_sourse="${1%:*}"
op_branch="${1#*:}"
echo -e "${INFO} Working directory: [ ${PWD} ]"
echo -e "${INFO} Source: [ ${op_sourse} ], Branch: [ ${op_branch} ]"
echo -e "${INFO} Server disk usage before build: \n$(df -hT ${make_path}) \n"
#
# Perform related operations
download_imagebuilder
adjust_settings
custom_packages
custom_config
custom_files
rebuild_firmware
custom_settings
#
# Show server end information
echo -e "${SUCCESS} OpenWrt Image Builder completed successfully."
echo -e "${INFO} Server disk usage after build: \n$(df -hT ${make_path}) \n"
