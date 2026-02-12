#!/bin/bash

. ./scripts/INCLUDE.sh

# Initialize environment
init_environment() {
    log "INFO" "Start Builder Patch!"
    log "INFO" "Current Path: $PWD"
    
    cd "${GITHUB_WORKSPACE}/${WORKING_DIR}" || error "Failed to change directory"
}

# Apply specific patches
apply_distro_patches() {
    if [[ "${BASE}" == "openwrt" ]]; then
        log "INFO" "Applying OpenWrt specific patches"
    elif [[ "${BASE}" == "immortalwrt" ]]; then
        log "INFO" "Applying ImmortalWrt specific patches"
        # cpufreq
        sed -i "\|luci-app-cpufreq|d" include/target.mk
    else
        log "INFO" "Unknown distribution: ${BASE}"
    fi
}

# Patch package signature
patch_signature_check() {
    log "INFO" "Disabling package signature"
    
    local branch_major=$(echo "${BRANCH}" | cut -d'.' -f1)
    local repo_file="repositories"
    
    case "$branch_major" in
        "24"|"23")
            repo_file="repositories.conf"
            ;;
        "25"|*)
            repo_file="repositories"
            ;;
    esac
    
    log "INFO" "Using repository file: ${repo_file}"
    sed -i '\|option check_signature| s|^|#|' "${repo_file}"
}

# Force installation options in Makefile
patch_makefile() {
    log "INFO" "Applying force options to Makefile..."
    sed -i "s|install \$(BUILD_PACKAGES)|install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade --force-checksum|" Makefile
}

# Configure partition sizes
configure_partitions() {
    log "INFO" "Configuring partition sizes"
    # Set kernel and rootfs partition sizes
    sed -i "s|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|" .config
    sed -i "s|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1280|" .config
}

# Apply Amlogic-specific configurations
configure_amlogic() {
    if [[ "${TYPE}" == "OPHUB" || "${TYPE}" == "ULO" ]]; then
        sed -i "s|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g" .config
        sed -i "s|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g" .config
    else
        log "INFO" "System type: ${TYPE}"
    fi
}

# Main execution
main() {
    init_environment
    apply_distro_patches
    patch_signature_check
    patch_makefile
    configure_partitions
    configure_amlogic
    configure_x86
    log "INFO" "Builder patch completed successfully!"
}

# Execute main function
main
