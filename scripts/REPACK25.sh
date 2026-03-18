#!/bin/bash

# Load include script
[ -f ./scripts/INCLUDE.sh ] && . ./scripts/INCLUDE.sh

# Fungsi Log Sederhana jika INCLUDE.sh tidak terpanggil
log() {
    local level="$1"
    local msg="$2"
    case "$level" in
       "INFO")    echo -e "[ \033[1;34mINFO\033[0m ] $msg" ;;
       "SUCCESS") echo -e "[ \033[1;32mSUCCESS\033[0m ] $msg" ;;
       "ERROR")   echo -e "[ \033[1;31mERROR\033[0m ] $msg" ;;
       "STEPS")   echo -e "[ \033[1;35mSTEPS\033[0m ] $msg" ;;
       *)         echo -e "[ $level ] $msg" ;;   
    esac
}

error_msg() { log "ERROR" "$1"; }

repackwrt() {
    # Initialize variables
    local builder_type=""
    local target_board=""
    local target_kernel=""
    
    # Parse command line arguments (Manual Parsing)
    builder_type="--$1"
    target_board="$2"
    target_kernel="$3"
    local tunnel_type="${4:-no-tunnel}"

    # Validate inputs
    [[ -z "$1" ]] && { error_msg "Builder type required (ophub/ulo)"; exit 1; }
    [[ -z "$target_board" ]] && { error_msg "Target board required (e.g. s905x3)"; exit 1; }
    [[ -z "$target_kernel" ]] && { error_msg "Target kernel required (e.g. 6.1.x)"; exit 1; }

    # Set branch
    local BRANCH="${GITHUB_REF_NAME:-main}"
    log "INFO" "Using Branch: $BRANCH | Board: $target_board | Kernel: $target_kernel"

    # Define repo URLs and directories
    local work_dir="${GITHUB_WORKSPACE}/${WORKING_DIR:-imagebuilder}"
    local output_dir="${work_dir}/compiled_images"
    local builder_dir repo_url ZIP_FILE="${BRANCH}.zip"

    # Configure builder settings
    if [[ "$builder_type" == "--ophub" ]]; then
        builder_dir="${work_dir}/amlogic-s9xxx-openwrt-${BRANCH}"
        repo_url="https://github.com{BRANCH}.zip"
        log "STEPS" "Repacking with Ophub..."
    else
        builder_dir="${work_dir}/ULO-Builder-${BRANCH}"
        repo_url="https://github.com{BRANCH}.zip"
        log "STEPS" "Repacking with UloBuilder..."
    fi

    # Prepare working directory
    cd "${work_dir}" || { error_msg "Missing work dir: ${work_dir}"; exit 1; }

    # Download builder
    log "INFO" "Downloading builder..."
    if ! wget -qO "${ZIP_FILE}" "${repo_url}"; then
        log "WARNING" "Branch download failed. Fallback to main."
        ZIP_FILE="main.zip"
        if [[ "$builder_type" == "--ophub" ]]; then
            repo_url="https://github.com"
            builder_dir="ribel13/amlogic-s9xxx-openwrt-main"
        else
            repo_url="https://github.com"
            builder_dir="ribel13/ULO-Builder-main"
        fi
        wget -qO "${ZIP_FILE}" "${repo_url}" || { error_msg "Download failed"; exit 1; }
    fi

    # Extract builder
    unzip -q "${ZIP_FILE}" || { error_msg "Extraction failed"; rm -f "${ZIP_FILE}"; exit 1; }
    rm -f "${ZIP_FILE}"

    # Find rootfs file (Pencarian fleksibel)
    log "INFO" "Searching for rootfs in: ${output_dir}"
    local rootfs_file=$(find "${output_dir}" -type f -name "*-rootfs.tar.gz" | head -n 1)
    [[ -z "$rootfs_file" ]] && { error_msg "Rootfs file not found!"; exit 1; }

    # Setup directories and copy rootfs
    if [[ "$builder_type" == "--ophub" ]]; then
        mkdir -p "${builder_dir}/openwrt-armvirt"
        local target_path="${builder_dir}/openwrt-armvirt/openwrt-armvirt-64-default-rootfs.tar.gz"
        cp -f "${rootfs_file}" "${target_path}"
    else
        mkdir -p "${builder_dir}/rootfs"
        local target_path="${builder_dir}/rootfs/openwrt-armvirt-64-default-rootfs.tar.gz"
        cp -f "${rootfs_file}" "${target_path}"
    fi

    # Enter builder directory
    cd "${builder_dir}" || { error_msg "Missing builder dir"; exit 1; }

    # Run Repack Process
    if [[ "$builder_type" == "--ophub" ]]; then
        log "INFO" "Executing Ophub Remake (Optimized)..."
        # -s 512 untuk partisi, -c zstd untuk kompresi kilat (jika skrip mendukung)
        sudo ./remake -b "${target_board}" -k "${target_kernel}" -s 512 || { error_msg "Ophub failed"; exit 1; }
        device_output_dir="./out"
    else
        log "INFO" "Executing Ulo Builder..."
        sudo ./ulo -y -m "${target_board}" -r "openwrt-armvirt-64-default-rootfs.tar.gz" -k "${target_kernel}" -s 1024 || { error_msg "Ulo failed"; exit 1; }
        device_output_dir="./out/${target_board}"
    fi

    # Verify and Copy Output
    log "INFO" "Saving firmware artifacts..."
    mkdir -p "${output_dir}"
    # Pindahkan semua file .img hasil repack ke folder output utama
    find "${device_output_dir}" -type f -name "*.img*" -exec mv {} "${output_dir}/" \;

    # Cleanup (Optional - bisa dikomentari jika butuh debug)
    # sudo rm -rf "${builder_dir}"

    sync && sleep 2
    log "SUCCESS" "Repack Complete! Files ready in compiled_images/"
    ls -lh "${output_dir}"/*.img*
}

# Jalankan fungsi dengan parameter dari workflow
# Argumen: 1=type, 2=board, 3=kernel, 4=tunnel
repackwrt "$1" "$2" "$3" "$4"
