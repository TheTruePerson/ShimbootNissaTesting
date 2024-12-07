#!/bin/bash

# Enhanced patch script for Shimboot, with additional support for audio firmware

. ./common.sh
. ./image_utils.sh

print_help() {
  echo "Usage: ./patch_rootfs.sh shim_path reco_path rootfs_dir"
}

assert_root
assert_deps "git gunzip depmod lsof"
assert_args "$3"

copy_modules_and_firmware() {
  local shim_rootfs=$(realpath -m $1)
  local reco_rootfs=$(realpath -m $2)
  local target_rootfs=$(realpath -m $3)

  echo "Copying kernel modules and firmware from shim and recovery images..."

  # Replace kernel modules
  rm -rf "${target_rootfs}/lib/modules"
  cp -r "${shim_rootfs}/lib/modules" "${target_rootfs}/lib/modules"

  # Merge firmware from shim and recovery images
  mkdir -p "${target_rootfs}/lib/firmware"
  cp -r --remove-destination "${shim_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"
  cp -r --remove-destination "${reco_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"

  # Add modprobe configurations
  mkdir -p "${target_rootfs}/lib/modprobe.d/" "${target_rootfs}/etc/modprobe.d/"
  cp -r --remove-destination "${reco_rootfs}/lib/modprobe.d/"* "${target_rootfs}/lib/modprobe.d/" 2>/dev/null || true
  cp -r --remove-destination "${reco_rootfs}/etc/modprobe.d/"* "${target_rootfs}/etc/modprobe.d/" 2>/dev/null || true

  # Decompress kernel modules if required
  echo "Decompressing kernel modules if needed..."
  find "${target_rootfs}/lib/modules" -name '*.gz' -exec gunzip {} \;
  for kernel_dir in "${target_rootfs}/lib/modules/"*; do
    local version=$(basename "$kernel_dir")
    depmod -b "${target_rootfs}" "$version"
  done
}

fetch_audio_firmware() {
  local target_rootfs=$(realpath -m $1)
  local firmware_repo="https://chromium.googlesource.com/chromiumos/third_party/linux-firmware"
  local temp_firmware_dir="/tmp/audio-firmware"

  echo "Fetching additional audio firmware..."
  rm -rf "$temp_firmware_dir"
  git clone --depth=1 "$firmware_repo" "$temp_firmware_dir"

  cp -r --remove-destination "${temp_firmware_dir}/"* "${target_rootfs}/lib/firmware/"
  rm -rf "$temp_firmware_dir"
}

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

echo "Copying kernel modules and firmware..."
copy_modules_and_firmware "$shim_rootfs" "$reco_rootfs" "$target_rootfs"

echo "Fetching and applying additional audio firmware..."
fetch_audio_firmware "$target_rootfs"

echo "Cleaning up..."
umount "$shim_rootfs"
umount "$reco_rootfs"
losetup -d "$shim_loop"
losetup -d "$reco_loop"

echo "Patch complete. Rootfs updated with audio support."
