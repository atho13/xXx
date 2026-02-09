#!/bin/bash

# Load include script
. ./scripts/INCLUDE.sh

# Validate input argument
if [ -z "$1" ]; then
    log "ERROR" "Parameter required"
    log "INFO" "Usage: $0 {openclash|nikki|insomclash|passwall|nikki-passwall|...}"
    exit 1
fi

PACKAGES="$1"
log "INFO" "Selected Tunnel: ${PACKAGES}"

# Determine package format (apk/ipk)
get_package_extension() {
    local major_ver=$(echo "${VEROP}" | cut -d'.' -f1)
    [[ "$major_ver" -ge 25 ]] && echo "apk" || echo "ipk"
}

# --- URL Generators ---

# Get OpenClash URLs (Core & App)
generate_openclash_urls() {
    local ext=$(get_package_extension "${VEROP}")
    local meta_file="mihomo-linux-${ARCH_1}"
    [[ "${ARCH_3}" == "x86_64" ]] && meta_file="mihomo-linux-${ARCH_1}-compatible"
    
    # Fetch latest download links
    openclash_core=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep "browser_download_url" | grep -oE "https.*${meta_file}-v[0-9]+\.[0-9]+\.[0-9]+\.gz" | head -n 1)
    openclash_app=$(curl -s "https://api.github.com/repos/de-quenx/OpenClash-x/releases" | grep "browser_download_url" | grep -oE "https.*luci-app-openclash.*.${ext}" | head -n 1)
}

# Get Passwall URLs
generate_passwall_urls() {
    local ext=$(get_package_extension "${VEROP}")
    passwall_app=$(curl -s "https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases" | grep "browser_download_url" | grep -oE "https.*luci-app-passwall[-_][0-9]+\.[0-9]+\.[0-9]+-r[0-9]+.*\.${ext}" | head -n 1)
    passwall_core=$(curl -s "https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases" | grep "browser_download_url" | grep -oE "https.*passwall_packages_${ext}_${ARCH_3}.*.zip" | head -n 1)
}

# Get Nikki URLs
generate_nikki_urls() {
    local file="nikki_${ARCH_3}-openwrt-${VEROP}"
    local repo="syntax-xidz/nikki-x/releases"
    # Use legacy release for 23.05
    [[ "${VEROP}" == "23.05" ]] && repo="Yogxx/OpenWrt-nikkiku/releases/tags/v1.25.0"
    
    nikki_app=$(curl -s "https://api.github.com/repos/${repo}" | grep "browser_download_url" | grep -oE "https.*${file}.*.tar.gz" | head -n 1)
}

# Get InsomClash URLs
generate_insomclash_urls() {
    insomclash_app=$(curl -s "https://api.github.com/repos/bobbyunknown/FusionTunX/releases" | grep "browser_download_url" | grep -oE "https.*luci-app-insomclash.*.ipk" | head -n 1)
    insomclash_core=$(curl -s "https://api.github.com/repos/bobbyunknown/FusionTunX/releases" | grep "browser_download_url" | grep -oE "https.*insomclash_[^\"]*${ARCH_3}[^\"]*\.ipk" | head -n 1)
}

# --- Setup Functions ---

setup_openclash() {
    generate_openclash_urls
    local ext=$(get_package_extension "${VEROP}")
    
    log "INFO" "Installing OpenClash (${ext})..."
    ariadl "${openclash_app}" "packages/openclash.${ext}"
    ariadl "${openclash_core}" "files/etc/openclash/core/clash_meta.gz"
    
    log "INFO" "Configuring OpenClash..."
    gzip -d "files/etc/openclash/core/clash_meta.gz"
    chmod +x "files/etc/openclash/core/clash_meta"
    chmod +x files/etc/openclash/{Country.mmdb,GeoIP.dat,GeoSite.dat}
    
    # Inject startup config
    sed -i "/# Tunnel/a\\
echo \"Configuring Tunnel...\"\\
ln -sf /etc/openclash/history/xidzs.db /etc/openclash/cache.db\\
ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash" "files/etc/uci-defaults/99-init-settings.sh"
}

setup_passwall() {
    generate_passwall_urls
    local ext=$(get_package_extension "${VEROP}")
    
    log "INFO" "Installing Passwall (${ext})..."
    ariadl "${passwall_app}" "packages/passwall.${ext}"
    ariadl "${passwall_core}" "packages/passwall.zip"
    
    log "INFO" "Extracting Passwall..."
    unzip -qq "packages/passwall.zip" -d "packages" && rm "packages/passwall.zip"
}

setup_nikki() {
    generate_nikki_urls
    log "INFO" "Installing Nikki..."
    ariadl "${nikki_app}" "packages/nikki.tar.gz"
    
    log "INFO" "Extracting Nikki..."
    tar -xzvf "packages/nikki.tar.gz" -C "packages" > /dev/null 2>&1 && rm "packages/nikki.tar.gz"
    chmod +x files/etc/nikki/run/{Country.mmdb,GeoIP.dat,GeoSite.dat}
}

setup_insomclash() {
    generate_insomclash_urls
    log "INFO" "Installing InsomClash..."
    ariadl "${insomclash_app}" "packages/luci-app-insomclash.ipk"
    ariadl "${insomclash_core}" "packages/insomclash.ipk"
}

# --- Cleanup Functions ---

clean_openclash() { rm -rf "files/etc/openclash"; }
clean_passwall() { rm -f "files/etc/config/passwall"; }
clean_nikki() { rm -rf "files/etc/nikki" "files/etc/config/nikki"; }
clean_insomclash() { rm -rf "files/etc/insomclash"; }

# --- Main Logic ---

log "INFO" "Processing: ${PACKAGES}"

case "${PACKAGES}" in
    openclash)
        setup_openclash; clean_passwall; clean_nikki; clean_insomclash ;;
    nikki)
        setup_nikki; clean_openclash; clean_passwall; clean_insomclash ;;
    insomclash)
        setup_insomclash; clean_openclash; clean_passwall; clean_nikki ;;
    passwall)
        setup_passwall; clean_openclash; clean_nikki; clean_insomclash ;;
    nikki-passwall)
        setup_nikki; setup_passwall; clean_openclash; clean_insomclash ;;
    nikki-insomclash)
        setup_nikki; setup_insomclash; clean_openclash; clean_passwall ;;
    openclash-nikki)
        setup_openclash; setup_nikki; clean_passwall; clean_insomclash ;;
    openclash-insomclash)
        setup_openclash; setup_insomclash; clean_passwall; clean_nikki ;;
    openclash-nikki-passwall)
        setup_openclash; setup_nikki; setup_passwall; clean_insomclash ;;
    no-tunnel)
        clean_openclash; clean_passwall; clean_nikki; clean_insomclash ;;
    *)
        log "ERROR" "Invalid option: ${PACKAGES}"
        exit 1 ;;
esac

# Final check
if [ "$?" -eq 0 ]; then
    log "SUCCESS" "Installation completed for: ${PACKAGES}"
else
    log "ERROR" "Installation failed."
    exit 1
fi