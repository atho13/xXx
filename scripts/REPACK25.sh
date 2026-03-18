#!/bin/bash

# Load include script
[ -f ./scripts/INCLUDE.sh ] && . ./scripts/INCLUDE.sh

# Fungsi Log Sederhana
log() {
    local level="$1"
    local msg="$2"
    case "$level" in
       "INFO")    echo -e "[ \033[1;34mINFO\033[0m ] $msg" ;;
       "SUCCESS") echo -e "[ \033[1;32mSUCCESS\033[0m ] $msg" ;;
       "ERROR")   echo -e "[ \033[1;31mERROR\033[0m ] $msg" ;;
       "STEPS")   echo -e "[ \033[1;35mSTEPS\033[0m ] $msg" ;;
    esac
}

repackwrt() {
    local builder_type="$1"
    local target_board="$2"
    local target_kernel="$3"
    
    # Lokasi kerja (Sesuaikan dengan env GITHUB)
    local work_dir="${GITHUB_WORKSPACE}/${WORKING_DIR:-imagebuilder}"
    local output_dir="${work_dir}/compiled_images"
    
    log "STEPS" "Starting Repack Process for $target_board ($target_kernel)"

    # 1. Download Builder menggunakan TAR.GZ (Lebih Stabil)
    cd "${work_dir}"
    local repo_url="https://github.com"
    
    log "INFO" "Downloading builder from ribel13..."
    if ! curl -sL "$repo_url" -o builder.tar.gz; then
        log "ERROR" "Download gagal! Cek koneksi internet."
        exit 1
    fi

    # 2. Extract Builder
    log "INFO" "Extracting builder..."
    if ! tar -xzf builder.tar.gz; then
        log "ERROR" "Ekstraksi gagal! File tar.gz korup."
        rm -f builder.tar.gz
        exit 1
    fi
    rm -f builder.tar.gz

    # 3. Deteksi Nama Folder Hasil Extract
    local builder_dir=$(find . -maxdepth 1 -type d -name "amlogic-s9xxx-openwrt*" | head -n 1)
    if [ -z "$builder_dir" ]; then
        log "ERROR" "Folder builder tidak ditemukan setelah ekstraksi."
        exit 1
    fi
    log "INFO" "Using builder directory: $builder_dir"

    # 4. Siapkan Rootfs (Bahan Baku)
    log "INFO" "Searching for Rootfs in $output_dir..."
    local rootfs_source=$(find "$output_dir" -type f -name "*-rootfs.tar.gz" | head -n 1)
    
    if [ -z "$rootfs_source" ]; then
        log "ERROR" "File Rootfs (.tar.gz) tidak ditemukan di $output_dir!"
        exit 1
    fi

    # Buat folder input untuk Ophub (ribel13 biasanya pakai openwrt-armvirt)
    mkdir -p "${builder_dir}/openwrt-armvirt"
    cp -v "$rootfs_source" "${builder_dir}/openwrt-armvirt/openwrt-armvirt-64-default-rootfs.tar.gz"

    # 5. Eksekusi Remake (Ophub Script)
    cd "$builder_dir"
    chmod +x remake
    
    log "INFO" "Executing Remake script..."
    # -b: board, -k: kernel, -s: partisi (512MB), -c: kompresi (zstd untuk speed)
    sudo ./remake -b "$target_board" -k "$target_kernel" -s 512 || { log "ERROR" "Remake gagal!"; exit 1; }

    # 6. Pindahkan Hasil Akhir (.img)
    log "INFO" "Moving final images to compiled_images..."
    if [ -d "out" ]; then
        find out/ -type f -name "*.img*" -exec mv {} "$output_dir/" \;
        log "SUCCESS" "Repack SELESAI! Cek folder compiled_images."
    else
        log "ERROR" "Folder 'out' tidak ditemukan. Build gagal tanpa pesan error."
        exit 1
    fi

    # Sinkronisasi disk
    sync && sleep 2
}

# Jalankan fungsi
# Argumen: $1=ophub, $2=board, $3=kernel
repackwrt "$1" "$2" "$3"
