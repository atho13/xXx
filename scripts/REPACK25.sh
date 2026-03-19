#!/bin/bash

BUILDER_TYPE=$1
BOARD=$2
KERNEL=$3

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
OUTPUT_DIR="${ROOT_DIR}/compiled_images"
#REPO_URL="https://x-access-token:${GH_TOKEN}@://github.com"
REPO_URL="https://github.com/ribel13/amlogic-s9xxx-openwrt/archive/refs/heads/${BRANCH}.zip"

# 1. Clone Builder Privat
cd "${ROOT_DIR}"
sudo rm -rf builder-tmp
git clone --depth 1 "$REPO_URL" builder-tmp

# 2. Cari Rootfs
ROOTFS=$(find "$OUTPUT_DIR" -name "*.tar.gz" | head -n 1)

# 3. Eksekusi Repack (Menghasilkan .img)
cd builder-tmp
chmod +x remake 2>/dev/null || chmod +x rebuild 2>/dev/null
sudo ./remake -b "$BOARD" -k "$KERNEL" -s 1024 || sudo ./rebuild -i "$ROOTFS" -b "$BOARD" -k "$KERNEL" -s 1024

# 4. Pindahkan ke compiled_images agar diupload ke Release
find . -type f -name "*.img*" -exec mv {} "$OUTPUT_DIR/" \;
