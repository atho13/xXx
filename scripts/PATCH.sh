#!/bin/bash

# Load include script
[ -f "./scripts/INCLUDE.sh" ] && . ./scripts/INCLUDE.sh

# Initialize build environment
init_environment() {
    log "INFO" "Starting Builder Patch..."
    cd "${GITHUB_WORKSPACE}/${WORKING_DIR}" || exit 1
}

# Apply patches based on distro
apply_distro_patches() {
    case "${BASE}" in
        "immortalwrt")
            log "INFO" "Patching ImmortalWrt..."
            # Remove conflicting cpufreq
            sed -i "\|luci-app-cpufreq|d" include/target.mk
            ;;
        "openwrt")
            log "INFO" "Patching OpenWrt..."
            ;;
        *)
            log "INFO" "Unknown distro: ${BASE}"
            ;;
    esac
}

# Disable signature verification
patch_signature_check() {
    log "INFO" "Disabling signature check..."
    
    # Select config file based on version
    local major_ver=$(echo "${BRANCH}" | cut -d'.' -f1)
    local repo_file="repositories"
    
    # Use .conf for older versions (23/24)
    [[ "$major_ver" =~ ^(23|24)$ ]] && repo_file="repositories.conf"
    
    # Comment out signature check option
    sed -i '\|option check_signature| s|^|#|' "${repo_file}"
}

# Force overwrite packages in Makefile
patch_makefile() {
    log "INFO" "Patching Makefile force options..."
    sed -i "s|install \$(BUILD_PACKAGES)|install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade|" Makefile
}

# Resize partitions
configure_partitions() {
    log "INFO" "Resizing partitions..."
    sed -i "s|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|" .config
    sed -i "s|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1280|" .config
}

# Amlogic: Disable unused image formats
configure_amlogic() {
    if [[ "${TYPE}" == "OPHUB" || "${TYPE}" == "ULO" ]]; then
        log "INFO" "Optimizing for Amlogic..."
        sed -i "s|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g" .config
        sed -i "s|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g" .config
    fi
}

# x86: Disable ISO and VHDX images
configure_x86() {
    if [[ "${ARCH_2}" =~ (x86_64|i386) ]]; then
        log "INFO" "Optimizing for x86..."
        sed -i "s|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|" .config
        sed -i "s|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|" .config  
    fi
}

# Main Execution
main() {
    init_environment
    apply_distro_patches
    patch_signature_check
    patch_makefile
    configure_partitions
    configure_amlogic
    configure_x86
    log "INFO" "Builder patch finished!"
}

# Run main
main