#!/bin/bash

. ./scripts/INCLUDE.sh

# Repository URLs based on version
if [[ "${VEROP}" == "25.12" ]]; then
    KIDDIN9_REPO="https://dl.openwrt.ai/releases/25.12/packages/${ARCH_3}/kiddin9"
else
    KIDDIN9_REPO="https://dl.openwrt.ai/releases/24.10/packages/${ARCH_3}/kiddin9"
fi

# Define all repositories
declare -A REPOS
REPOS+=(
    ["OPENWRT"]="https://downloads.openwrt.org/releases/packages-${VEROP}/${ARCH_3}"
    ["IMMORTALWRT"]="https://downloads.immortalwrt.org/releases/packages-${VEROP}/${ARCH_3}"
    ["KYARUCLOUD_IMMORTALWRT"]="https://immortalwrt.kyarucloud.moe/releases/packages-${VEROP}/${ARCH_3}"
    ["KIDDIN9"]="${KIDDIN9_REPO}"
    ["GSPOTX2F"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
    ["FANTASTIC"]="https://fantastic-packages.github.io/packages/releases/${VEROP}/packages/x86_64"
    ["DLLKIDS"]="https://op.dllkids.xyz/packages/${ARCH_3}"
    ["OPENWRTRU"]="https://openwrt.132lan.ru/packages/${VEROP}/packages/${ARCH_3}/modemfeed"
)

# Custom package list with format: "package_name|repository_url"
declare -a packages_custom
packages_custom+=(
    # Modem info packages
    "modeminfo_|${REPOS[KIDDIN9]}"
    "luci-app-modeminfo_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-tw_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-dell_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-sierra_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-xmm_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-fibocom_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-sierra_|${REPOS[KIDDIN9]}"
    
    # System utilities
    "atinout_|${REPOS[KIDDIN9]}"
    "luci-app-diskman_|${REPOS[KIDDIN9]}"
    "luci-app-poweroffdevice_|${REPOS[KIDDIN9]}" 
    
    # Monitoring & watchdog
    "luci-app-lite-watchdog_|${REPOS[KIDDIN9]}"
    "luci-app-atcommands_|${REPOS[KIDDIN9]}"
    
    # VPN services
    "tailscale_|${REPOS[OPENWRT]}/packages"
    
    # Display & interface
    "luci-app-oled_|${REPOS[KIDDIN9]}"
    "modemband_|${REPOS[KYARUCLOUD_IMMORTALWRT]}/packages"
    "luci-app-ramfree_|${REPOS[KYARUCLOUD_IMMORTALWRT]}/luci"
    "luci-app-modemband_|${REPOS[KYARUCLOUD_IMMORTALWRT]}/luci"
    "luci-app-sms-tool-js_|${REPOS[KYARUCLOUD_IMMORTALWRT]}/luci"
    "dns2tcp_|${REPOS[KYARUCLOUD_IMMORTALWRT]}/packages"
    
    # Network tools
    "luci-app-ttyd_|${REPOS[OPENWRT]}/luci"
    #"ookla-speedtest_|${REPOS[KIDDIN9]}"
    #"luci-app-eqosplus_|${REPOS[KIDDIN9]}"
    "luci-app-internet-detector_|${REPOS[KIDDIN9]}"
    "internet-detector_|${REPOS[KIDDIN9]}"
    "internet-detector-mod-modem-restart_|${REPOS[KIDDIN9]}"
    "luci-app-temp-status_|${REPOS[KIDDIN9]}"
    
    # GitHub releases
    "luci-app-tinyfm_|https://api.github.com/repos/bobbyunknown/luci-app-tinyfm/releases/latest"
    "luci-app-droidnet_|https://api.github.com/repos/animegasan/luci-app-droidmodem/releases/latest"
    "luci-theme-alpha_|https://api.github.com/repos/de-quenx/luci-theme-alpha/releases/latest"
    "luci-app-tailscale_|https://api.github.com/repos/asvow/luci-app-tailscale/releases/latest"
    "luci-app-ipinfo_|https://api.github.com/repos/bobbyunknown/luci-app-ipinfo/releases/latest"
    "luci-app-netmonitor_|https://api.github.com/repos/de-quenx/luci-app-netmonitor/releases/latest"
    "luci-theme-argon_|https://api.github.com/repos/de-quenx/luci-theme-argon/releases/latest"
    "luci-app-ttl_|https://api.github.com/repos/de-quenx/custom-x/releases/latest"
    "luci-app-temp-status_|https://api.github.com/repos/de-quenx/kwrt-packages/releases/latest"
)

# Add Amlogic packages for specific device types
if [[ "${TYPE}" == "OPHUB" || "${TYPE}" == "ULO" ]]; then
    log "INFO" "Add Packages Amlogic In ${TYPE}.."
    packages_custom+=(
        "luci-app-amlogic_|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
    )
#lfi

# Verify downloaded packages
verify_packages() {
    local pkg_dir="packages"
    local -a failed_packages=()
    local -a package_list=("${!1}")
    local pkg_ext=$(get_package_extension "${VEROP}")
    
    if [[ ! -d "$pkg_dir" ]]; then
        error_msg "Package directory not found: $pkg_dir"
        return 1
    fi
    
    # Count packages with correct extension
    local total_found=$(find "$pkg_dir" -name "*.${pkg_ext}" | wc -l)
    log "INFO" "Found $total_found package files with .$pkg_ext extension"
    
    # Check each package
    for package in "${package_list[@]}"; do
        local pkg_name="${package%%|*}"
        if ! find "$pkg_dir" -name "${pkg_name}*.${pkg_ext}" -print -quit | grep -q .; then
            failed_packages+=("$pkg_name")
        fi
    done
    
    local failed=${#failed_packages[@]}
    
    if ((failed > 0)); then
        log "WARNING" "$failed packages failed to download with .$pkg_ext format:"
        for pkg in "${failed_packages[@]}"; do
            log "WARNING" "- $pkg"
        done
        return 1
    fi
    
    log "SUCCESS" "All packages downloaded successfully with .$pkg_ext format"
    return 0
}

# Main execution
main() {
    local rc=0
    
    # Download custom packages
    log "INFO" "Downloading Custom packages..."
    download_packages packages_custom || rc=1
    
    # Verify all downloads
    log "INFO" "Verifying all packages..."
    verify_packages packages_custom || rc=1
    
    if [ $rc -eq 0 ]; then
        log "SUCCESS" "Package download and verification completed successfully"
    else
        error_msg "Package download or verification failed"
    fi
    
    return $rc
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
