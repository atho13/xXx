#!/bin/bash

# Source include file jika ada
[ -f ./scripts/INCLUDE.sh ] && . ./scripts/INCLUDE.sh

# Fungsi Log Sederhana (Mandiri)
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
    # Ambil argumen dari workflow
    local builder_type="$1"
    local target_board="$2"
    local target_kernel="$3"
    
    # Lokasi kerja di GitHub Runner
    local root_dir="${GITHUB_WORKSPACE}"
    local output_dir="${root_dir}/compiled_images"
    local builder_dir="${root_dir}/amlogic-s9xxx-openwrt"
    
    log "STEPS" "Memulai Repack: $target_board (Kernel: $target_kernel)"

    # 1. Clone Builder (URL Absolut untuk menghindari error repo not found)
    cd "${root_dir}"
    log "INFO" "Cloning builder dari ribel13 (branch main)..."
    
    # Hapus folder lama agar bersih
    sudo rm -rf "amlogic-s9xxx-openwrt"
    
    # Perintah Clone dengan URL Langsung
    if ! git clone --depth 1 "https://github.com" "amlogic-s9xxx-openwrt"; then
        log "ERROR" "Git clone gagal! Periksa koneksi internet atau status repositori."
        exit 1
    fi

    # 2. Verifikasi dan Siapkan Rootfs
    log "INFO" "Mencari file Rootfs di $output_dir..."
    local rootfs_source=$(find "$output_dir" -type f -name "*-rootfs.tar.gz" | head -n 1)
    
    if [ -z "$rootfs_source" ]; then
        log "ERROR" "File Rootfs (.tar.gz) tidak ditemukan di $output_dir!"
        exit 1
    fi
    log "INFO" "Rootfs ditemukan: $(basename "$rootfs_source")"

    # 3. Masukkan Rootfs ke Folder Kerja Builder
    mkdir -p "${builder_dir}/openwrt-armvirt"
    cp -v "$rootfs_source" "${builder_dir}/openwrt-armvirt/openwrt-armvirt-64-default-rootfs.tar.gz"

    # 4. Eksekusi Script Repack (Remake)
    cd "$builder_dir"
    chmod +x remake
    
    log "INFO" "Menjalankan perintah remake (Ophub)..."
    # -b: board, -k: kernel, -s: partisi (512MB)
    sudo ./remake -b "$target_board" -k "$target_kernel" -s 512 || { log "ERROR" "Proses remake gagal!"; exit 1; }

    # 5. Pindahkan Hasil Akhir (.img) ke Artifacts
    log "INFO" "Memindahkan hasil build (.img) ke folder compiled_images..."
    if [ -d "out" ]; then
        find out/ -type f -name "*.img*" -exec mv {} "$output_dir/" \;
        log "SUCCESS" "Repack SELESAI! File tersedia di folder compiled_images/."
    else
        log "ERROR" "Folder 'out' tidak ditemukan! Image gagal tercipta."
        exit 1
    fi

    sync && sleep 2
}

# Jalankan fungsi utama
# Penggunaan: ./scripts/REPACK25.sh "ophub" "s905x-b860h" "6.12.y"
repackwrt "$1" "$2" "$3"
