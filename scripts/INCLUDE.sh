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

# Determine package priority (.apk vs .ipk)
get_extension_priority() {
    local version="${1:-${CONFIG[DEFAULT_VER]}}"
    local major=$(echo "$version" | cut -d'.' -f1)
    
    # 25.12+ and SNAPSHOT use .apk
    if [[ "$version" =~ "SNAPSHOT" ]] || [[ "$major" -ge 25 ]]; then
        echo "apk ipk"
        return
    fi

    # 23.05 and 24.10 use .ipk
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
    
    # Get priority: "apk ipk" (v25+) or "ipk apk" (v23/24)
    local exts=( $(get_extension_priority "$ver") )
    
    log "INFO" "OpenWrt Version: $ver. Priority: ${exts[*]}"
    mkdir -p "$dir"

    for entry in "${list[@]}"; do
        IFS="|" read -r name url <<< "$entry"
        unset IFS

        [ -z "$name" ] && continue

        local dl_url=""
        local found_ext=""

        # Loop through priorities (e.g., try apk first, then ipk)
        for ext in "${exts[@]}"; do
            
            # Case A: GitHub API URL
            if [[ "$url" == *"api.github.com"* ]]; then
                local json=$(curl -sL --user-agent "Mozilla/5.0" "$url" || true)
                dl_url=$(echo "$json" | jq -r '.assets[].browser_download_url' | grep -E "\.${ext}$" | grep -i "$name" | head -1)
            
            # Case B: Regular Web URL (Directory Listing)
            else
                # Use User-Agent to avoid blocking and follow redirects
                local html=$(curl -sL --user-agent "Mozilla/5.0" --max-time 15 "$url" || true)
                
                # Enhanced Regex: Looks for href="package_name...ext" or just the filename
                # Handles quotes, prefixes, and common web directory formats
                local file_match=$(echo "$html" | grep -oE "href=[\"'][^\"']*${name}[^\"']*\.${ext}[\"']" | head -1 | sed -E 's/href=[\"'\'']//g; s/[\"'\'']//g')
                
                # Fallback: simple grep if href not found
                if [[ -z "$file_match" ]]; then
                    file_match=$(echo "$html" | grep -oE "${name}[-_][a-zA-Z0-9\._-]+\.${ext}" | head -1)
                fi
                
                if [[ -n "$file_match" ]]; then
                    # Fix relative URLs
                    if [[ "$file_match" != http* ]]; then
                        # Remove trailing slash from base URL if present
                        local clean_base="${url%/}"
                        # Remove leading slash from file match if present
                        local clean_file="${file_match#/}"
                        dl_url="${clean_base}/${clean_file}"
                    else
                        dl_url="$file_match"
                    fi
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
            log "WARNING" "Checked in: $url"
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
