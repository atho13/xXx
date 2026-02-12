#!/bin/bash

. ./scripts/INCLUDE.sh

# Initialize environment
init_environment() {
    log "INFO" "Start Downloading Misc files and setup configuration!"
    log "INFO" "Current Path: $PWD"
}

# Setup base configurations
setup_base_config() {
    # Update date in init settings
    sed -i "s/Ouc3kNF6/${DATE}/g" "files/etc/uci-defaults/99-init-settings.sh"
    
    case "${BASE}" in
        "openwrt")
            log "INFO" "Configuring OpenWrt specific settings"
            ;;
        "immortalwrt")
            log "INFO" "Configuring ImmortalWrt specific settings"
            ;;
        *)
            log "INFO" "Unknown base system: ${BASE}"
            ;;
    esac
}

# Handle Amlogic files
handle_amlogic_files() {
    case "${TYPE}" in
        "OPHUB" | "ULO")
            log "INFO" "Removing Amlogic-specific files"
            rm -f "files/etc/uci-defaults/70-rootpt-resize"
            rm -f "files/etc/uci-defaults/80-rootfs-resize"
            rm -f "files/etc/sysupgrade.conf"
            ;;
        *)
            log "INFO" "system type: ${TYPE}"
            ;;
    esac
}

# Setup branch configurations
setup_branch_config() {
    local branch_major=$(echo "${BRANCH}" | cut -d'.' -f1)
    case "$branch_major" in
        "25")
            log "INFO" "Configuring for branch 25.x"
            ;;
        "24")
            log "INFO" "Configuring for branch 24.x"
            ;;
        "23")
            log "INFO" "Configuring for branch 23.x"
            ;;
        *)
            log "INFO" "Unknown branch version: ${BRANCH}"
            ;;
    esac
}

# Set Amlogic permissions
configure_amlogic_permissions() {
    case "${TYPE}" in
        "OPHUB" | "ULO")
            log "INFO" "Sett up Amlogic file permissions"
            
            # Netifd and wifi files sett permission
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
            
            # Set permission
            log "INFO" "Sett permissions for netifd and wifi files"
            for file in "${netifd_files[@]}"; do
                if [ -f "$file" ]; then
                    chmod +x "$file"
                fi
            done
            log "INFO" "Permissions set for netifd files"
            ;;
        *)
            log "INFO" "Removing lib directory for non-Amlogic build, preserving netifd/proto"
            
            find "files/lib" -mindepth 1 -not -path "files/lib/netifd/proto/*" -exec rm -rf {} +
            log "INFO" "Non-Amlogic specific files removed from lib, netifd/proto preserved."
            ;;
    esac
}

# Download custom scripts
download_custom_scripts() {
    log "INFO" "Downloading custom scripts"
    
    local scripts=(
        #"https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh|files/root"
        #"https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/xdev|files/usr/bin"
        #"https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/syntax|files/usr/bin"
        #"https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/xidz|files/usr/bin"
        #"https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/x-gpio|files/usr/bin"
        #"https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/x-gpioled|files/usr/bin"
        #"https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/xidzs|files/etc/init.d"
        #"https://raw.githubusercontent.com/syntax-xidz/contenx/main/xcli/issue|files/etc/init.d"
        #"https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/install2.sh|files/root"
        #"https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/xdev|files/usr/bin"
        "https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/chnrot|files/usr/bin"
        #"https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/xidz|files/usr/bin"
        #"https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/x-gpio|files/usr/bin"
        #"https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/x-gpioled|files/usr/bin"
        #"https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/xidzs|files/etc/init.d"
        "https://github.com/ribel13/XIDZs-Punya/blob/main/scripts/issue|files/etc/init.d"
    )
    
    for script in "${scripts[@]}"; do
        IFS='|' read -r url path <<< "$script"
        mkdir -p "$path"
        wget --no-check-certificate -nv -P "$path" "$url" || error "Failed to download: $url"
    done
}

# Configure file permissions
configure_file_permissions() {
    log "INFO" "Sett file permissions"
    
    # file etc sett permission
    local initd_files=(
        "files/etc/init.d/issue"
        #"files/etc/init.d/xidzs"
    )
    
    log "INFO" "Sett permissions for init.d files"
    for file in "${initd_files[@]}"; do
        if [ -f "$file" ]; then
            chmod +x "$file"
        fi
    done
    log "INFO" "Init.d permissions set successfully"
    
    # Sbin files sett permission  
    local sbin_files=(
        "files/sbin/free.sh"
        "files/sbin/jam"
        "files/sbin/ping.sh"
    )
    
    log "INFO" "Sett permissions for sbin files"
    for file in "${sbin_files[@]}"; do
        if [ -f "$file" ]; then
            chmod +x "$file"
        fi
    done
    log "INFO" "Sbin permissions set successfully"
    
    # Custom scripts and sett permission
    local custom_scripts=(
        #"files/root/install2.sh"
        #"files/usr/bin/xdev"
        "files/usr/bin/chnrot"
        #"files/usr/bin/xidz"
        #"files/usr/bin/x-gpio"
        #"files/usr/bin/x-gpioled"
    )
    
    log "INFO" "Sett permissions for custom scripts"
    for file in "${custom_scripts[@]}"; do
        if [ -f "$file" ]; then
            chmod +x "$file"
        fi
    done
    log "INFO" "Custom scripts permissions set successfully"
    
    # Set permissions for config files
    local config_files=(
        "files/etc/crontabs/root"
        "files/etc/rc.local"
        "files/etc/sysctl.conf"
    )
    
    log "INFO" "Sett permissions for config files"
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            chmod 644 "$file"
        fi
    done
    log "INFO" "Config files permissions set successfully"
}

# Main execution
main() {
    init_environment
    setup_base_config
    handle_amlogic_files
    setup_branch_config
    configure_amlogic_permissions
    download_custom_scripts
    configure_file_permissions
    log "SUCCESS" "All custom configuration setup completed!"
}

# Execute main function
main
