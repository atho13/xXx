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
    local output_dir="${GITHUB_WORKSPACE}/compiled_images"
    
    log "STEPS" "Memulai Repack untuk $target_board (Kernel: $target_kernel)"

    # 1. Download Builder menggunakan TAR.GZ (Lebih Aman & Stabil dibanding ZIP)
    cd "${GITHUB_WORKSPACE}"
    local repo_url="https://github.com"
    
    log "INFO" "Mengunduh builder dari ribel13..."
    if ! curl -sL "$repo_url" -o builder.tar.gz; then
        log "ERROR" "Gagal mengunduh! Cek koneksi internet runner."
        exit 1
    fi

    # 2. Ekstraksi Builder
    log "INFO" "Mengekstrak builder (tar.gz)..."
    if ! tar -xzf builder.tar.gz; then
        log "ERROR" "Ekstraksi gagal! File kemungkinan korup."
        rm -f builder.tar.gz
        exit 1
    fi
    rm -f builder.tar.gz

    # 3. Identifikasi Folder Hasil Ekstrak
    local builder_dir=$(find . -maxdepth 1 -type d -name "amlogic-s9xxx-openwrt*" | head -n 1)
    if [ -z "$builder_dir" ]; then
        log "ERROR" "Folder builder tidak ditemukan!"
        exit 1
    fi
    log "INFO" "Menggunakan direktori: $builder_dir"

    # 4. Menyiapkan Rootfs (Bahan Baku)
    log "INFO" "Mencari file Rootfs di $output_dir..."
    local rootfs_source=$(find "$output_dir" -type f -name "*-rootfs.tar.gz" | head -n 1)
    
    if [ -z "$rootfs_source" ]; then
        log "ERROR" "File Rootfs (.tar.gz) tidak ditemukan! Pastikan build sebelumnya sukses."
        exit 1
    fi

    # Buat folder input sesuai standar ribel13/ophub
    mkdir -p "${builder_dir}/openwrt-armvirt"
    cp -v "$rootfs_source" "${builder_dir}/openwrt-armvirt/openwrt-armvirt-64-default-rootfs.tar.gz"

    # 5. Eksekusi Script Repack (Remake)
    cd "$builder_dir"
    chmod +x remake
    
    log "INFO" "Menjalankan perintah remake..."
    # -b: board, -k: kernel, -s: partisi (512MB)
    sudo ./remake -b "$target_board" -k "$target_kernel" -s 512 || { log "ERROR" "Proses remake gagal!"; exit 1; }

    # 6. Pemindahan Hasil Akhir (.img)
    log "INFO" "Memindahkan hasil build ke folder artifacts..."
    if [ -d "out" ]; then
        find out/ -type f -name "*.img*" -exec mv {} "$output_dir/" \;
        log "SUCCESS" "Repack SELESAI! File tersedia di compiled_images/."
    else
        log "ERROR" "Folder 'out' tidak ditemukan. Image tidak tercipta."
        exit 1
    fi

    sync && sleep 2
}

# Eksekusi fungsi utama
# $1=ophub, $2=board, $3=kernel
repackwrt "$1" "$2" "$3"
