#!/bin/bash

# Load include script
[ -f "./scripts/INCLUDE.sh" ] && . ./scripts/INCLUDE.sh

# Extract major version
MAJOR_VER=$(echo "${VEROP}" | cut -d'.' -f1)

# Set base URL based on version (25+ uses APK structure)
if [[ "${VEROP}" == *"SNAPSHOT"* ]] || [[ "$MAJOR_VER" -ge 25 ]]; then
    BASE_KIDDIN9="https://dl.openwrt.ai/releases/${VEROP}/packages/${ARCH_3}/kiddin9"
else
    BASE_KIDDIN9="https://dl.openwrt.ai/releases/24.10/packages/${ARCH_3}/kiddin9"
fi

# Define repositories
declare -A REPOS
REPOS=(
    ["OPENWRT"]="https://downloads.openwrt.org/releases/packages-${VEROP}/${ARCH_3}"
    ["IMMORTALWRT"]="https://downloads.immortalwrt.org/releases/packages-${VEROP}/${ARCH_3}"
    ["KYARUCLOUD"]="https://immortalwrt.kyarucloud.moe/releases/packages-${VEROP}/${ARCH_3}"
    ["KIDDIN9"]="${BASE_KIDDIN9}"
    ["FANTASTIC"]="https://fantastic-packages.github.io/packages/releases/${VEROP}/packages/x86_64"
    ["DLLKIDS"]="https://op.dllkids.xyz/packages/${ARCH_3}"
    ["GSPOTX2F"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
)

# Custom Package List
declare -a packages_custom
packages_custom+=(
    # Modem Drivers & Info
    "modeminfo_|${REPOS[KIDDIN9]}"
    "luci-app-modeminfo_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-tw_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-dell_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-sierra_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-xmm_|${REPOS[KIDDIN9]}"
    "modeminfo-serial-fibocom_|${REPOS[KIDDIN9]}"
    
    # System Utilities
    "atinout_|${REPOS[KIDDIN9]}"
    "luci-app-diskman_|${REPOS[KIDDIN9]}"
    "luci-app-poweroffdevice_|${REPOS[KIDDIN9]}" 
    "luci-app-ttyd_|${REPOS[OPENWRT]}/luci"
    
    # Monitoring Tools
    "luci-app-lite-watchdog_|${REPOS[KIDDIN9]}"
    "luci-app-atcommands_|${REPOS[KIDDIN9]}"
    "luci-app-eqosplus_|${REPOS[KIDDIN9]}"
    "ookla-speedtest_|${REPOS[KIDDIN9]}"
    
    # VPN & Network
    "tailscale_|${REPOS[OPENWRT]}/packages"
    "dns2tcp_|${REPOS[KYARUCLOUD]}/packages"
    
    # Interface & Display
    "luci-app-oled_|${REPOS[KIDDIN9]}"
    "modemband_|${REPOS[KYARUCLOUD]}/packages"
    "luci-app-ramfree_|${REPOS[KYARUCLOUD]}/luci"
    "luci-app-modemband_|${REPOS[KYARUCLOUD]}/luci"
    "luci-app-sms-tool-js_|${REPOS[KYARUCLOUD]}/luci"
    
    # Internet Detector
    "luci-app-internet-detector_|${REPOS[KIDDIN9]}"
    "internet-detector_|${REPOS[KIDDIN9]}"
    "internet-detector-mod-modem-restart_|${REPOS[KIDDIN9]}"

    # GitHub Latest Releases (Direct API)
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

# Add Amlogic-specific packages if needed
if [[ "${TYPE}" == "OPHUB" || "${TYPE}" == "ULO" ]]; then
    log "INFO" "Adding Amlogic packages for ${TYPE}..."
    packages_custom+=(
        "luci-app-amlogic_|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
    )
fi

# Verification Logic
verify_packages() {
    local -a list=("${!1}")
    local dir="packages"
    local -a failed=()
    local exts=("apk" "ipk") 
    
    [ ! -d "$dir" ] && { error_msg "Package directory missing"; return 1; }

    log "STEPS" "Verifying packages..."

    for entry in "${list[@]}"; do
        local name="${entry%%|*}"
        name="${name%_}" 
        local found=false

        # Check if file exists with either extension
        for ext in "${exts[@]}"; do
            if find "$dir" -name "${name}*.${ext}" -print -quit | grep -q .; then
                found=true
                break
            fi
        done

        if [ "$found" = false ]; then
            failed+=("$name")
        fi
    done
    
    if [ ${#failed[@]} -gt 0 ]; then
        log "WARNING" "Failed to download ${#failed[@]} packages:"
        printf ' - %s\n' "${failed[@]}"
        return 1
    fi
    
    log "SUCCESS" "All packages verified successfully."
    return 0
}

# Main Execution
main() {
    local status=0
    
    # Download packages
    log "INFO" "Downloading custom packages..."
    download_packages packages_custom || status=1
    
    # Verify downloads
    verify_packages packages_custom || status=1
    
    return $status
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi