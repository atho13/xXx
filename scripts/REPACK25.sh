#!/bin/bash

# Load include script
. ./scripts/INCLUDE.sh

repackwrt() {
    # Initialize variables
    local builder_type=""
    local target_board=""
    local target_kernel=""
    #local tunnel_type=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ophub|--ulo)
                builder_type="$1"
                shift
                ;;
            -t|--target)
                target_board="$2"
                shift 2
                ;;
            -k|--kernel)
                target_kernel="$2"
                shift 2
                ;;
        esac
    done

    # Validate inputs
    [[ -z "$builder_type" ]] && { error_msg "Builder type required (--ophub or --ulo)"; exit 1; }
    [[ -z "$target_board" ]] && { error_msg "Target board required (-t)"; exit 1; }
    [[ -z "$target_kernel" ]] && { error_msg "Target kernel required (-k)"; exit 1; }
    #[[ -z "$tunnel_type" ]] && { error_msg "Tunnel type required (-tn)"; exit 1; }

    # Set branch (fallback to main if not on a branch)
    local BRANCH="${GITHUB_REF_NAME:-main}"
    [[ "${GITHUB_REF_TYPE:-branch}" != "branch" ]] && BRANCH="main"
    log "INFO" "Using Branch: $BRANCH"

    # Define repo URLs and directories
    #local OPHUB_REPO="https://github.com/syntax-xidz/amlogic-s9xxx-openwrt/archive/refs/heads/${BRANCH}.zip"
    #local ULO_REPO="https://github.com/syntax-xidz/ULO-Builder/archive/refs/heads/${BRANCH}.zip"
    local OPHUB_REPO="https://github.com/ophub/amlogic-s9xxx-openwrt/archive/refs/heads/${BRANCH}.zip"
    #local ULO_REPO="https://github.com/ribel13/ULO-Builder/archive/refs/heads/${BRANCH}.zip"
    local work_dir="$GITHUB_WORKSPACE/$WORKING_DIR"
    local output_dir="${work_dir}/compiled_images"
    local builder_dir repo_url ZIP_FILE="${BRANCH}.zip"

    # Configure builder settings
    if [[ "$builder_type" == "--ophub" ]]; then
        builder_dir="${work_dir}/amlogic-s9xxx-openwrt-${BRANCH}"
        repo_url="${OPHUB_REPO}"
        log "STEPS" "Repacking with Ophub..."
    #else
        #builder_dir="${work_dir}/ULO-Builder-${BRANCH}"
        #repo_url="${ULO_REPO}"
        #log "STEPS" "Repacking with UloBuilder..."
    fi

    # Prepare working directory
    cd "${work_dir}" || { error_msg "Missing work dir: ${work_dir}"; exit 1; }

    # Download builder (with fallback to main)
    log "INFO" "Downloading builder..."
    if ! ariadl "${repo_url}" "${ZIP_FILE}"; then
        log "WARNING" "Branch download failed. Fallback to main."
        ZIP_FILE="main.zip"
        if [[ "$builder_type" == "--ophub" ]]; then
            #repo_url="https://github.com/syntax-xidz/amlogic-s9xxx-openwrt/archive/refs/heads/main.zip"
            repo_url="https://github.com/ophub/amlogic-s9xxx-openwrt/archive/refs/heads/main.zip"
            builder_dir="${work_dir}/amlogic-s9xxx-openwrt-main"
        #else
            #repo_url="https://github.com/syntax-xidz/ULO-Builder/archive/refs/heads/main.zip"
            #repo_url="https://github.com/ribel13/ULO-Builder/archive/refs/heads/main.zip"
            #builder_dir="${work_dir}/ULO-Builder-main"
        fi
        ariadl "${repo_url}" "${ZIP_FILE}" || { error_msg "Download failed"; exit 1; }
    fi

    # Extract builder
    unzip -q "${ZIP_FILE}" || { error_msg "Extraction failed"; rm -f "${ZIP_FILE}"; exit 1; }
    rm -f "${ZIP_FILE}"

    # Setup directories
    [[ "$builder_type" == "--ophub" ]] && mkdir -p "${builder_dir}/openwrt-armsr" || mkdir -p "${builder_dir}/rootfs"

    # Find rootfs file
    #local rootfs_files=("${output_dir}/"*"_${tunnel_type}-rootfs.tar.gz")
    local rootfs_files=("${output_dir}-rootfs.tar.gz")
    [[ ${#rootfs_files[@]} -ne 1 ]] && { error_msg "Rootfs file not found or multiple found"; exit 1; }
    local rootfs_file="${rootfs_files[0]}"

    # Copy rootfs to builder
    log "INFO" "Copying rootfs..."
    local target_path
    if [[ "$builder_type" == "--ophub" ]]; then
        target_path="${builder_dir}/openwrt-armsr/${BASE}-armsr-armv8-generic-rootfs.tar.gz"
    else
        target_path="${builder_dir}/rootfs/${BASE}-armsr-armv8-generic-rootfs.tar.gz"
    fi
    cp -f "${rootfs_file}" "${target_path}" || { error_msg "Copy failed"; exit 1; }

    # Enter builder directory
    cd "${builder_dir}" || { error_msg "Missing builder dir"; exit 1; }

    # Run Repack Process
    local device_output_dir
    if [[ "$builder_type" == "--ophub" ]]; then
        log "INFO" "Executing Ophub Script..."
        sudo ./remake -b "${target_board}" -k "${target_kernel}" -s 512 || { error_msg "Ophub failed"; exit 1; }
        device_output_dir="./openwrt/out"
    #else
        #log "INFO" "Applying ULO patches..."
        #if [[ -f "./.github/workflows/ULO_Workflow.patch" ]]; then
            #mv ./.github/workflows/ULO_Workflow.patch ./ULO_Workflow.patch
            #patch -p1 < ./ULO_Workflow.patch >/dev/null 2>&1 && log "SUCCESS" "Patch applied" || log "WARNING" "Patch failed"
        #fi

        #log "INFO" "Executing Ulo Script..."
        #local rootfs_name=$(basename "${target_path}")
        #sudo ./ulo -y -m "${target_board}" -r "${rootfs_name}" -k "${target_kernel}" -s 1024 || { error_msg "Ulo failed"; exit 1; }
        #device_output_dir="./out/${target_board}"
    fi

    # Verify and Copy Output
    [[ ! -d "${device_output_dir}" ]] && { error_msg "Output dir missing"; exit 1; }
    
    log "INFO" "Saving firmware..."
    cp -rf "${device_output_dir}"/* "${output_dir}/" || { error_msg "Save failed"; exit 1; }

    # Final Check
    ls "${output_dir}"/* >/dev/null 2>&1 || { error_msg "No firmware generated"; exit 1; }

    # Cleanup
    [[ -d "${builder_dir}" && "${builder_dir}" != "/" ]] && sudo rm -rf "${builder_dir}"

    sync && sleep 3
    ls -lh "${output_dir}"/*
    log "SUCCESS" "Repack Complete!"
}

# Run function
repackwrt --"$1" -t "$2" -k "$3" -tn "$4"
