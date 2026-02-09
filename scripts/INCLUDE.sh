#!/bin/bash

# Check Bash version (requires v4+)
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: Bash version 4 or higher is required." >&2
    exit 1
fi

# Strict mode (exit on error)
set -euo pipefail
IFS=$'\n\t'

# Setup output colors
setup_colors() {
    PURPLE="\033[95m"
    BLUE="\033[94m"
    GREEN="\033[92m"
    YELLOW="\033[93m"
    RED="\033[91m"
    RESET="\033[0m"

    STEPS="[${PURPLE} STEPS ${RESET}]"
    INFO="[${BLUE} INFO ${RESET}]"
    SUCCESS="[${GREEN} SUCCESS ${RESET}]"
    WARNING="[${YELLOW} WARNING ${RESET}]"
    ERROR="[${RED} ERROR ${RESET}]"
}

# Initialize colors
setup_colors

# Global configuration
declare -A CONFIG=(
    ["MAX_RETRIES"]=5
    ["RETRY_DELAY"]=2
    ["SPINNER_INTERVAL"]=0.1
    ["DEBUG"]="false"
    ["DEFAULT_VER"]="25.12.0" # Default version if not provided
)

# Cleanup processes on exit
cleanup() {
    printf "\e[?25h"  # Restore cursor
    jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT

# Simple logging function
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        "ERROR")   echo -e "${ERROR} $message" >&2 ;;
        "STEPS")   echo -e "${STEPS} $message" ;;
        "WARNING") echo -e "${WARNING} $message" ;;
        "SUCCESS") echo -e "${SUCCESS} $message" ;;
        "INFO")    echo -e "${INFO} $message" ;;
        *)         echo -e "${INFO} $message" ;;
    esac
}

# Show error and exit
error_msg() {
    echo -e "${ERROR} $1 (Line: ${2:-${BASH_LINENO[0]}})" >&2
    exit 1
}

# Loading animation
spinner() {
    local pid=$1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    printf "\e[?25l" # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        for frame in "${frames[@]}"; do
            printf "\r ${BLUE}%s${RESET}" "$frame"
            sleep "${CONFIG[SPINNER_INTERVAL]}"
        done
    done
    printf "\e[?25h" # Show cursor
    wait "$pid"
    return $?
}

# Check system dependencies
check_dependencies() {
    local -A dependencies=(
        ["aria2"]="aria2c --version"
        ["curl"]="curl --version"
        ["jq"]="jq --version"
        ["zstd"]="zstd --version" # Required for .apk format
    )

    log "STEPS" "Checking dependencies..."
    
    if ! command -v apt-get >/dev/null 2>&1; then
        error_msg "apt-get not found."
        return 1
    fi

    for pkg in "${!dependencies[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            log "WARNING" "Installing $pkg..."
            sudo apt-get install -y "$pkg" &>/dev/null || error_msg "Failed to install $pkg"
        fi
    done
    log "SUCCESS" "All dependencies are ready!"
}

# Determine file priority (.apk or .ipk) based on version
get_extension_priority() {
    local version="${1:-${CONFIG[DEFAULT_VER]}}"
    local major=$(echo "$version" | cut -d'.' -f1)
    
    # SNAPSHOT / Master uses APK
    if [[ "$version" =~ "SNAPSHOT" ]] || [[ "$version" == "master" ]]; then
        echo "apk ipk"
        return
    fi

    # Version 25.12) uses APK
    if [[ "$major" -ge 25 ]]; then
        echo "apk ipk"
        return
    fi

    # versions (23.05, 24.10) use IPK
    echo "ipk apk"
}

# Download function using aria2c
ariadl() {
    local URL=$1
    local DIR=${2:-"."}
    local FILE=$(basename "$URL")
    local RETRY=0

    mkdir -p "$DIR"

    while [ $RETRY -lt ${CONFIG[MAX_RETRIES]} ]; do
        # Download with multi-connection
        aria2c -q -x4 -s4 -d "$DIR" -o "$FILE" "$URL" && return 0
        
        RETRY=$((RETRY + 1))
        sleep "${CONFIG[RETRY_DELAY]}"
    done
    return 1
}

# Main package download logic
download_packages() {
    local -n list="$1"
    local ver="${VEROP:-${CONFIG[DEFAULT_VER]}}" # Get version from env
    local dir="packages"
    
    # Get extension priority (e.g., "ipk apk" for v24, "apk ipk" for v25)
    local exts=( $(get_extension_priority "$ver") )
    
    log "INFO" "OpenWrt Version: $ver. Priority: ${exts[*]}"
    mkdir -p "$dir"

    for entry in "${list[@]}"; do
        IFS="|" read -r name url <<< "$entry"
        unset IFS

        [ -z "$name" ] && continue

        local dl_url=""
        local found_ext=""

        # Loop through extension priority
        for ext in "${exts[@]}"; do
            
            # Case A: GitHub API URL
            if [[ "$url" == *"api.github.com"* ]]; then
                local json=$(curl -sL "$url" || true)
                dl_url=$(echo "$json" | jq -r '.assets[].browser_download_url' | grep -E "\.${ext}$" | grep -i "$name" | head -1)
            
            # Case B: Regular Web URL
            else
                local html=$(curl -sL --max-time 10 "$url" || true)
                # Regex to find .ipk/.apk file
                local file_match=$(echo "$html" | grep -oE "${name}.*\.${ext}" | head -1 | tr -d '"')
                
                if [[ -n "$file_match" ]]; then
                    # Fix relative URLs
                    [[ "$file_match" != http* ]] && dl_url="${url%/}/$file_match" || dl_url="$file_match"
                fi
            fi

            # Break loop if file found
            if [[ -n "$dl_url" ]]; then
                found_ext="$ext"
                break
            fi
        done

        # If file not found in any format
        if [[ -z "$dl_url" ]]; then
            log "ERROR" "Package not found: $name"
            continue
        fi

        log "INFO" "Downloading ($found_ext): $(basename "$dl_url")"
        if ! ariadl "$dl_url" "$dir"; then
            error_msg "Failed to download $name"
        fi
    done
}

# Main entry point
main() {
    check_dependencies || exit 1
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi