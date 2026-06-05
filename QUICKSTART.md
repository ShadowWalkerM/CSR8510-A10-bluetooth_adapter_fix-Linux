# CSR8510 A10 Bluetooth Dongle Patch for Linux
# Fixes cheap CSR8510 A10 (USB ID 10d7:b012) clone dongles that work on Windows but not Linux.

## Quick Install (fresh CachyOS install)
#
# 1. Download from Google Drive:
#    rclone copy gdrive100:csr8510-btusb-patch.tar.gz ~/csr8510-btusb-patch.tar.gz
#
# 2. Extract and install:
#    tar xzf ~/csr8510-btusb-patch.tar.gz && sudo bash ~/csr8510-btusb-patch/install.sh
#
# Or as a one-liner:
#    rclone copy gdrive100:csr8510-btusb-patch.tar.gz ~ && tar xzf ~/csr8510-btusb-patch.tar.gz -C ~ && sudo bash ~/csr8510-btusb-patch/install.sh

## Files
- install.sh                  → One-command installer (requires sudo)
- patch-btusb-csr8510.sh      → Patch/rebuild script (called by hook or manually)
- 99-patch-btusb-csr8510.hook → Pacman hook (auto-patches on kernel updates)
- README.md                   → This file
