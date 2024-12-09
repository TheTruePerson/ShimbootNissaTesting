#!/bin/bash

# Advanced patch script for Shimboot rootfs
# Designed to integrate essential audio firmware for compatibility with target hardware.

. ./common.sh
. ./image_utils.sh

print_help() {
  echo "Usage: ./patch_rootfs.sh shim_path reco_path rootfs_dir"
}

assert_root
assert_deps "git gunzip depmod xz"
assert_args "$3"

# Identify relevant audio hardware from recovery image
identify_audio_hardware() {
  echo "Scanning recovery image for audio hardware details..."
  local reco_rootfs=$1
  local device_info=$(cat "${reco_rootfs}/proc/asound/cards" 2>/dev/null || lspci | grep -i audio)

  if [ -z "$device_info" ]; then
    echo "Warning: No audio hardware detected in recovery image."
  else
    echo "Audio hardware identified: $device_info"
  fi
  echo "$device_info"
}

# Copy and validate firmware files
copy_and_prepare_firmware() {
  local source_firmware_paths=("$1" "$2")
  local target_rootfs=$3
  local target_firmware_dir="${target_rootfs}/lib/firmware"

  echo "Copying audio firmware to target rootfs..."
  mkdir -p "$target_firmware_dir"

  for path in "${source_firmware_paths[@]}"; do
    if [ -d "$path" ]; then
      echo "Processing firmware in $path..."
      find "$path" -type f \( -name "*audio*" -o -name "*dsp*" -o -name "*codec*" \) -exec cp --remove-destination {} "$target_firmware_dir/" \;
    fi
  done

  echo "Compressing firmware files..."
  find "$target_firmware_dir" -type f -exec xz -T0 {} \;

  echo "Firmware preparation complete."
}

# Copy kernel modules
copy_kernel_modules() {
  local source_rootfs=$1
  local target_rootfs=$2

  echo "Copying kernel modules..."
  rm -rf "${target_rootfs}/lib/modules"
  cp -r "${source_rootfs}/lib/modules" "${target_rootfs}/lib/modules"

  echo "Decompressing kernel modules if necessary..."
  find "${target_rootfs}/lib/modules" -name '*.gz' -exec gunzip {} \;
  for kernel_dir in "${target_rootfs}/lib/modules/"*; do
    local version=$(basename "$kernel_dir")
    depmod -b "${target_rootfs}" "$version"
  done
}

# Fetch and integrate additional firmware
fetch_additional_firmware() {
  local target_firmware_dir="${1}/lib/firmware"
  local firmware_repo="https://chromium.googlesource.com/chromiumos/third_party/linux-firmware"
  local temp_dir="/tmp/audio-firmware"

  echo "Fetching additional firmware from Chromium repository..."
  rm -rf "$temp_dir"
  git clone --depth=1 "$firmware_repo" "$temp_dir"

  cp -r --remove-destination "${temp_dir}/"* "$target_firmware_dir/"
  rm -rf "$temp_dir"
}

# Main Script Workflow
shim_path=$(realpath -m $1)
reco_path=$(realpath -m $2)
target_rootfs=$(realpath -m $3)
shim_rootfs="/tmp/shim_rootfs"
reco_rootfs="/tmp/reco_rootfs"

echo "Mounting shim rootfs..."
shim_loop=$(create_loop "$shim_path")
safe_mount "${shim_loop}p3" "$shim_rootfs" ro

echo "Mounting recovery rootfs..."
reco_loop=$(create_loop "$reco_path")
safe_mount "${reco_loop}p3" "$reco_rootfs" ro

echo "Identifying audio hardware..."
identify_audio_hardware "$reco_rootfs"

echo "Copying kernel modules..."
copy_kernel_modules "$shim_rootfs" "$target_rootfs"

echo "Copying and preparing firmware..."
copy_and_prepare_firmware "$shim_rootfs/lib/firmware" "$reco_rootfs/lib/firmware" "$target_rootfs"

echo "Fetching and integrating additional firmware..."
fetch_additional_firmware "$target_rootfs"

echo "Cleaning up..."
umount "$shim_rootfs"
umount "$reco_rootfs"
losetup -d "$shim_loop"
losetup -d "$reco_loop"

echo "Patch process complete. Audio firmware integrated for Shimboot."
