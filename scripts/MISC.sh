#!/bin/bash

# Load include script
. ./scripts/INCLUDE.sh

# Initialize environment
init_environment() {
    log "INFO" "Downloading Misc files and setting up config..."
    log "INFO" "Current Path: $PWD"
}

# Configure base settings
setup_base_config() {
    # Inject build date into init settings
    sed -i "s/Ouc3kNF6/${DATE}/g" "files/etc/uci-defaults/99-init-settings.sh"
    
    case "${BASE}" in
        "openwrt")
            log "INFO" "Configuring OpenWrt..."
            ;;
        "immortalwrt")
            log "INFO" "Configuring ImmortalWrt..."
            ;;
        *)
            log "INFO" "Unknown Base: ${BASE}"
            ;;
    esac
}

# Clean up Amlogic specific files
handle_amlogic_files() {
    case "${TYPE}" in
        "OPHUB" | "ULO")
            log "INFO" "Removing unnecessary Amlogic init scripts..."
            rm -f files/etc/uci-defaults/{70-rootpt-resize,80-rootfs-resize}
            rm -f "files/etc/sysupgrade.conf"
            ;;
        *)
            log "INFO" "System Type: ${TYPE}"
            ;;
    esac
}

# Configure settings per branch
setup_branch_config() {
    local major=$(echo "${BRANCH}" | cut -d'.' -f1)
    log "INFO" "Configuring for Branch: ${major}.x"
}

# Manage permissions for Amlogic vs Others
configure_amlogic_permissions() {
    case "${TYPE}" in
        "OPHUB" | "ULO")
            log "INFO" "Setting executable permissions for Amlogic network scripts..."
            
            # List of netifd scripts
            local netifd_files=(
                "files/lib/netifd/proto/3g.sh"
                "files/lib/netifd/proto/atc.sh"
                "files/lib/netifd/proto/dhcp.sh"
                "files/lib/netifd/proto/dhcpv6.sh"
                "files/lib/netifd/proto/ncm.sh"
                "files/lib/netifd/proto/wwan.sh"
                "files/lib/netifd/wireless/mac80211.sh"
                "files/lib/netifd/dhcp-get-server.sh"
                "files/lib/netifd/dhcp.script"
                "files/lib/netifd/dhcpv6.script"
                "files/lib/netifd/hostapd.sh"
                "files/lib/netifd/netifd-proto.sh"
                "files/lib/netifd/netifd-wireless.sh"
                "files/lib/netifd/utils.sh"
                "files/lib/wifi/mac80211.sh"
            )
            
            for file in "${netifd_files[@]}"; do
                [ -f "$file" ] && chmod +x "$file"
            done
            ;;
        *)
            log "INFO" "Cleaning 'lib' directory for non-Amlogic (keeping 'proto')..."
            find "files/lib" -mindepth 1 -not -path "files/lib/netifd/proto/*" -exec rm -rf {} +
            ;;
    esac
}

# Download external custom scripts
download_custom_scripts() {
    log "INFO" "Downloading extra tools..."
    
    # Format: "URL|DESTINATION_PATH"
    local downloads=(
        "https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh|files/root"
        "https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/xdev|files/usr/bin"
        "https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/syntax|files/usr/bin"
        "https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/xidz|files/usr/bin"
        "https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/x-gpio|files/usr/bin"
        "https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/x-gpioled|files/usr/bin"
        "https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/xidzs|files/etc/init.d"
        "https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/issue|files/etc/init.d"
    )
    
    for item in "${downloads[@]}"; do
        IFS='|' read -r url path <<< "$item"
        mkdir -p "$path"
        wget --no-check-certificate -nv -P "$path" "$url" || error "Download failed: $url"
    done
}

# Set file permissions for system files
configure_file_permissions() {
    log "INFO" "Setting file permissions..."
    
    # Executable scripts (chmod +x)
    local executables=(
        "files/etc/init.d/issue"
        "files/etc/init.d/xidzs"
        "files/sbin/free.sh"
        "files/sbin/jam"
        "files/sbin/ping.sh"
        "files/root/install2.sh"
        "files/usr/bin/xdev"
        "files/usr/bin/syntax"
        "files/usr/bin/xidz"
        "files/usr/bin/x-gpio"
        "files/usr/bin/x-gpioled"
    )
    
    for file in "${executables[@]}"; do
        [ -f "$file" ] && chmod +x "$file"
    done

    # Config files (chmod 644)
    local configs=(
        "files/etc/crontabs/root"
        "files/etc/rc.local"
        "files/etc/sysctl.conf"
    )
    
    for file in "${configs[@]}"; do
        [ -f "$file" ] && chmod 644 "$file"
    done
}

# Main Execution
main() {
    init_environment
    setup_base_config
    handle_amlogic_files
    setup_branch_config
    configure_amlogic_permissions
    download_custom_scripts
    configure_file_permissions
    log "SUCCESS" "Misc setup completed!"
}

# Run main
main