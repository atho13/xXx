#!/bin/bash

# Check bash version (requires 4+)
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: Bash 4+ required." >&2
    exit 1
fi

# Enable strict mode
set -euo pipefail
IFS=$'\n\t'

# Setup colors
setup_colors() {
    PURPLE="\033[95m"
    BLUE="\033[94m"
    GREEN="\033[92m"
    YELLOW="\033[93m"
    RED="\033[91m"
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    RESET="\033[0m"

    STEPS="[${PURPLE} STEPS ${RESET}]"
    INFO="[${BLUE} INFO ${RESET}]"
    SUCCESS="[${GREEN} SUCCESS ${RESET}]"
    WARNING="[${YELLOW} WARNING ${RESET}]"
    ERROR="[${RED} ERROR ${RESET}]"

    # Formatting escapes
    CL="\033[m"
    UL="\033[4m"
    BOLD="\033[1m"
    BFR="\r\033[K"
    HOLD=" "
    TAB="  "
}

# Init colors
setup_colors

# Config vars
declare -A CONFIG=(
    ["MAX_RETRIES"]=5
    ["RETRY_DELAY"]=2
    ["SPINNER_INTERVAL"]=0.1
    ["DEBUG"]="false"
)

# Cleanup trap
cleanup() {
    printf "\e[?25h"
    jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT

# Log message
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

# Error handler
error_msg() {
    local msg="$1"
    local line_number=${2:-${BASH_LINENO[0]}}
    echo -e "${ERROR} ${msg} (Line: ${line_number})" >&2
    echo "Stack trace:" >&2
    local frame=0
    while caller $frame; do
        ((frame++))
    done >&2
    exit 1
}

# Spinner for background tasks
spinner() {
    local pid=$1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local colors=("\033[31m" "\033[33m" "\033[32m" "\033[36m" "\033[34m" "\033[35m")

    printf "\e[?25l"

    while kill -0 "$pid" 2>/dev/null; do
        for ((i=0; i < ${#frames[@]}; i++)); do
            printf "\r ${colors[i % ${#colors[@]}]}%s${RESET}" "${frames[i]}"
            sleep "${CONFIG[SPINNER_INTERVAL]}"
        done
    done

    printf "\e[?25h"
    wait "$pid"
    return $?
}

# Install command with spinner
cmdinstall() {
    local cmd="$1"
    local desc="${2:-$cmd}"

    log "INFO" "Installing: $desc"

    ( eval "$cmd" ) &
    local pid=$!
    spinner "$pid"
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log "SUCCESS" "$desc installed"
        if [[ "${CONFIG[DEBUG]}" == "true" ]]; then set -x; fi
    else
        error_msg "Install failed: $desc"
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    local -A dependencies=(
        ["aria2"]="aria2c --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+'"
        ["curl"]="curl --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+'"
        ["tar"]="tar --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+'"
        ["gzip"]="gzip --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+'"
        ["unzip"]="unzip -v | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+'"
        ["git"]="git --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+'"
        ["wget"]="wget --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+'"
        ["jq"]="jq --version | grep -oE '[0-9]+(\.[0-9]+)+'"
    )

    log "STEPS" "Check deps..."

    # Check apt
    if ! command -v apt-get >/dev/null 2>&1; then
        error_msg "apt-get not found"
        return 1
    fi

    # Update repos
    if ! sudo apt-get update -qq &>/dev/null; then
        error_msg "Update failed"
        return 1
    fi

    # Check each dep
    for pkg in "${!dependencies[@]}"; do
        local version_cmd="${dependencies[$pkg]}"
        local installed_version=""

        if command -v "$pkg" >/dev/null 2>&1; then
            installed_version=$(eval "$version_cmd" 2>/dev/null || echo "")
            if [[ -n "$installed_version" ]]; then
                log "SUCCESS" "$pkg v$installed_version OK"
                continue
            fi
        fi

        log "WARNING" "Install $pkg"
        if ! sudo apt-get install -y "$pkg" &>/dev/null; then
            error_msg "Install failed: $pkg"
            return 1
        fi
        
        # Verify install
        installed_version=$(eval "$version_cmd" 2>/dev/null || echo "")
        if [[ -n "$installed_version" ]]; then
            log "SUCCESS" "$pkg v$installed_version"
        else
            log "WARNING" "$pkg version check failed"
        fi
    done

    log "SUCCESS" "Deps OK"
}

# Get pkg extension for OpenWrt
get_package_extension() {
    local version="$1"
    local major_version=$(echo "$version" | cut -d'.' -f1)
    
    if [[ "$major_version" -ge 25 ]]; then
        echo "apk"
    else
        echo "ipk"
    fi
}

# Aria2 download with retries (MOD: auto-clean .aria2 cache)
ariadl() {
    if [ "$#" -lt 1 ]; then
        error_msg "Usage: ariadl <URL> [OUTPUT]"
        return 1
    fi

    log "STEPS" "Aria2 download"

    local URL=$1
    local OUTPUT_FILE=""
    local OUTPUT_DIR=""
    local RETRY_COUNT=0
    local MAX_RETRIES=${CONFIG[MAX_RETRIES]}
    local RETRY_DELAY=${CONFIG[RETRY_DELAY]}

    # Set output
    if [ "$#" -eq 1 ]; then
        OUTPUT_FILE=$(basename "$URL")
        OUTPUT_DIR="."
    else
        OUTPUT_FILE=$(basename "$2")
        OUTPUT_DIR=$(dirname "$2")
    fi

    # Create dir
    if [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
    fi

    # Retry loop
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        log "INFO" "Download: $URL (try $((RETRY_COUNT + 1)))"

        # Clean files
        if [ -f "$OUTPUT_DIR/$OUTPUT_FILE" ]; then
            rm -f "$OUTPUT_DIR/$OUTPUT_FILE"
        fi
        # Clean aria2 cache to prevent session errors
        if [ -f "$OUTPUT_DIR/${OUTPUT_FILE}.aria2" ]; then
            rm -f "$OUTPUT_DIR/${OUTPUT_FILE}.aria2"
            log "INFO" "Cleaned .aria2 cache"
        fi

        # Download
        aria2c -q -d "$OUTPUT_DIR" -o "$OUTPUT_FILE" "$URL"

        if [ $? -eq 0 ]; then
            log "SUCCESS" "Downloaded $OUTPUT_FILE"
            return 0
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                log "WARNING" "Retry in $RETRY_DELAYs"
                sleep "$RETRY_DELAY"
            fi
        fi
    done

    error_msg "Download failed: $OUTPUT_FILE"
    return 1
}

# Download packages array
download_packages() {
    local -n package_list="$1"
    local download_dir="packages"
    local pkg_ext=$(get_package_extension "${VEROP:-0.0.0}")

    mkdir -p "$download_dir"

    # Internal download helper
    download_file() {
        local url="$1"
        local output="$2"
        local max_retries=5
        local retry=0

        while [ $retry -lt $max_retries ]; do
            if ariadl "$url" "$output"; then
                return 0
            fi
            retry=$((retry + 1))
            log "WARNING" "Retry $retry/$max_retries: $output"
            sleep 2
        done
        return 1
    }

    # Process entries (format: filename|base_url)
    for entry in "${package_list[@]}"; do
        IFS="|" read -r filename base_url <<< "$entry"
        unset IFS

        if [[ -z "$filename" || -z "$base_url" ]]; then
            log "ERROR" "Invalid entry: $entry"
            continue
        fi

        local download_url=""

        # GitHub API handling
        if [[ "$base_url" == *"api.github.com"* ]]; then
            local file_urls=$(curl -sL "$base_url" | jq -r '.assets[].browser_download_url' 2>/dev/null || echo "")
            if [[ -z "$file_urls" ]]; then
                log "ERROR" "GitHub API failed: $base_url"
                continue
            fi
            download_url=$(echo "$file_urls" | grep -E "\.${pkg_ext}$" | grep -i "$filename" | sort -V | tail -1)
        else
            # Web scrape handling
            local page_content=$(curl -sL --max-time 30 --retry 3 "$base_url" || echo "")
            if [[ -z "$page_content" ]]; then
                log "ERROR" "Page fetch failed: $base_url"
                continue
            fi

            local patterns=(
                "${filename}[^\"]*\\.${pkg_ext}"
                "${filename}_.*\\.${pkg_ext}"
                "${filename}.*\\.${pkg_ext}"
            )

            for pattern in "${patterns[@]}"; do
                download_url=$(echo "$page_content" | grep -oE "\"${pattern}\"" | tr -d '"' | sort -V | tail -n 1 || true)
                if [[ -n "$download_url" ]]; then
                    # Fix relative URL
                    if [[ ! "$download_url" =~ ^https?:// ]]; then
                        download_url="${base_url%/}/$download_url"
                    fi
                    break
                fi
            done
        fi

        # No URL? Skip
        if [[ -z "$download_url" ]]; then
            log "ERROR" "No URL for $filename (ext .$pkg_ext)"
            continue
        fi

        # Run download
        local output_file="$download_dir/$(basename "$download_url")"
        if ! download_file "$download_url" "$output_file"; then
            error_msg "Download failed: $filename"
        fi
    done

    return 0
}

# Main entry
main() {
    check_dependencies || exit 1
}

# Run main if direct call
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi