#!/bin/bash

# Load include script
. ./scripts/INCLUDE.sh

# Function to modify SD card boot files
build_mod_sdcard() {
    local image_path="$1"
    local dtb="$2"
    local suffix="$3"

    log "STEPS" "Modifying boot files for Amlogic s905x..."
    
    # Validate parameters
    if [[ -z "$suffix" || -z "$dtb" || -z "$image_path" ]]; then
        error_msg "Missing parameters. Usage: build_mod_sdcard <path> <dtb> <suffix>"
        return 1
    fi

    # Set working directory
    local work_dir="$GITHUB_WORKSPACE/$WORKING_DIR/compiled_images"
    cd "$work_dir" || { error_msg "Directory not found: $work_dir"; return 1; }

    # Define cleanup trap
    cleanup() {
        log "INFO" "Cleaning up..."
        sudo umount boot 2>/dev/null || true
        sudo losetup -D 2>/dev/null || true
    }
    trap cleanup EXIT

    # Verify input file
    [[ ! -f "$image_path" ]] && { error_msg "Image not found: $image_path"; return 1; }

    # Download modification tools
    log "INFO" "Downloading mod tools..."
    ariadl "https://github.com/rizkikotet-dev/mod-boot-sdcard/archive/refs/heads/main.zip" "main.zip"

    # Extract tools
    unzip -q main.zip || { error_msg "Extraction failed"; return 1; }
    rm -f main.zip

    # Prepare build folder
    mkdir -p "${suffix}/boot"
    log "INFO" "Preparing files for ${suffix}..."
    
    # Copy image and bootloader
    cp "$image_path" "${suffix}/"
    if ! sudo cp mod-boot-sdcard-main/BootCardMaker/u-boot.bin \
        mod-boot-sdcard-main/files/mod-boot-sdcard.tar.gz "${suffix}/"; then
        error_msg "Copy failed"
        return 1
    fi

    cd "${suffix}" || return 1
    local file_name=$(basename "${image_path%.gz}")

    # Decompress image
    sudo gunzip "${file_name}.gz" || { error_msg "Decompression failed"; return 1; }

    # Setup Loop Device
    log "INFO" "Setting up loop device..."
    local device
    for i in {1..3}; do
        device=$(sudo losetup -fP --show "${file_name}" 2>/dev/null)
        [ -n "$device" ] && break
        sleep 1
    done
    [[ -z "$device" ]] && { error_msg "Loop setup failed"; return 1; }

    # Mount Partition
    log "INFO" "Mounting boot partition..."
    local mounted=false
    for i in {1..3}; do
        if sudo mount "${device}p1" boot; then
            mounted=true
            break
        fi
        sleep 1
    done
    [[ "$mounted" == "false" ]] && { error_msg "Mount failed"; return 1; }

    # Apply Modifications
    log "INFO" "Applying boot mods..."
    sudo tar -xzf mod-boot-sdcard.tar.gz -C boot || { error_msg "Mod extraction failed"; return 1; }

    # Update Config Files (uEnv, extlinux, boot.ini)
    log "INFO" "Updating configs..."
    local uenv=$(sudo cat boot/uEnv.txt | grep APPEND | awk -F "root=" '{print $2}')
    local extlinux=$(sudo cat boot/extlinux/extlinux.conf | grep append | awk -F "root=" '{print $2}')
    local current_dtb=$(sudo cat boot/boot.ini | grep dtb | awk -F "/" '{print $4}' | cut -d'"' -f1)

    # Replace root UUID and DTB name
    sudo sed -i "s|$extlinux|$uenv|g" boot/extlinux/extlinux.conf
    sudo sed -i "s|$current_dtb|$dtb|g" boot/boot.ini
    sudo sed -i "s|$current_dtb|$dtb|g" boot/extlinux/extlinux.conf
    sudo sed -i "s|$current_dtb|$dtb|g" boot/uEnv.txt

    sync && sudo umount boot

    # Write Bootloader (u-boot.bin)
    log "INFO" "Flashing bootloader..."
    if ! sudo dd if=u-boot.bin of="${device}" bs=1 count=444 conv=fsync 2>/dev/null || \
       ! sudo dd if=u-boot.bin of="${device}" bs=512 skip=1 seek=1 conv=fsync 2>/dev/null; then
        error_msg "Bootloader write failed"
        return 1
    fi

    # Cleanup and Compress
    sudo losetup -d "${device}"
    sudo gzip "${file_name}" || { error_msg "Compression failed"; return 1; }

    # Rename final image
    rm -f "../${file_name}.gz" # Remove original if exists
    
    # Extract EXACT kernel version from file name for final output
    local kernel=$(grep -oP 'k[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9-]+)?' <<<"${file_name}")
    local new_name="XIDZs-${OP_BASE}-${BRANCH}-${suffix}-${kernel}-${TUNNEL}-${DATE}-MODSDCARD.img.gz"

    mv "${file_name}.gz" "../${new_name}" || { error_msg "Rename failed"; return 1; }

    # Final cleanup
    cd ..
    rm -rf "${suffix}" mod-boot-sdcard-main
    log "SUCCESS" "Processed: ${new_name}"
    return 0
}

# Main processing loop
process_builds() {
    local img_dir="$1"
    local builds=("${@:2}") # Skip first arg (dir)
    local exit_code=0
    
    for build in "${builds[@]}"; do
        IFS=':' read -r pattern dtb suffix <<< "$build"
        
        # Find matching image (Generic Match)
        local image_file=$(find "$img_dir" -name "*${pattern}*.img.gz" | head -n 1)
        
        if [[ -n "$image_file" ]]; then
            log "INFO" "Found image for pattern ${pattern}: $(basename "$image_file")"
            build_mod_sdcard "$image_file" "$dtb" "$suffix" || exit_code=1
        else
            log "WARNING" "Skipping $suffix (No image found for pattern: $pattern)"
        fi
    done
    
    return $exit_code
}

# Main execution entry point
main() {
    local exit_code=0
    local img_dir="$GITHUB_WORKSPACE/$WORKING_DIR/compiled_images"

    # Define build configurations based on target
    # UPDATED: Removed specific patch versions (e.g., .196) for flexibility
    local builds=()
    if [[ "$MATRIXTARGET" == "Amlogic s905x HG680P MODSDCARD" ]]; then
        builds=(
            "_s905x_k5.15:meson-gxl-s905x-p212.dtb:s905x_HG680P-WIFION"
            "_s905x_k6.1:meson-gxl-s905x-p212.dtb:s905x_HG680P-WIFION"
            "_s905x_k6.6:meson-gxl-s905x-p212.dtb:s905x_HG680P-WIFION"
            "_s905x_k6.12:meson-gxl-s905x-p212.dtb:s905x_HG680P-WIFION"
        )
    elif [[ "$MATRIXTARGET" == "Amlogic s905x B860H MODSDCARD" ]]; then
        builds=(
            "_s905x-b860h_k5.15:meson-gxl-s905x-b860h.dtb:s905x_B860H-WIFION"
            "_s905x-b860h_k6.1:meson-gxl-s905x-b860h.dtb:s905x_B860H-WIFION"
            "_s905x-b860h_k6.6:meson-gxl-s905x-b860h.dtb:s905x_B860H-WIFION"
            "_s905x-b860h_k6.12:meson-gxl-s905x-b860h.dtb:s905x_B860H-WIFION"
        )
    fi
    
    # Check directory
    [[ ! -d "$img_dir" ]] && { error_msg "Missing image dir: $img_dir"; return 1; }
    
    # Run processing
    process_builds "$img_dir" "${builds[@]}" || exit_code=1
    
    return $exit_code
}

# Run script
main