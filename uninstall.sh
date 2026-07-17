#!/bin/bash
# CSR8510 A10 btusb patch uninstaller
# Usage: sudo bash uninstall.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "CSR8510 A10 Bluetooth Patch - Uninstaller"
echo "========================================="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Run with sudo${NC}"
    exit 1
fi

KVER=$(uname -r)

echo "This will:"
echo "  1. Remove the patch script"
echo "  2. Remove the pacman hook"
echo "  3. Restore the original btusb module (from backup)"
echo "  4. Suggest a reboot"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Remove files
echo -n "Removing patch script... "
rm -f /usr/local/bin/patch-btusb-csr8510.sh
echo "done."

echo -n "Removing Python patch module... "
rm -f /usr/local/bin/patch_btusb.py
echo "done."

echo -n "Removing pacman hook... "
rm -f /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook
echo "done."

# Restore original module
echo -n "Restoring original module... "
if [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst.bak" ]; then
    cp "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst.bak" \
       "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst"
    echo "done."
else
    echo -e "${YELLOW}no backup found for kernel ${KVER}${NC}"
    echo "You may need to reinstall the kernel package to restore the original module:"
    echo "  sudo pacman -S linux-cachyos"
fi

echo ""
echo -e "${GREEN}Uninstalled.${NC}"
echo ""
echo "Reboot to reload the unpatched module:"
echo "  sudo reboot"
