#!/bin/bash
# CSR8510 A10 btusb patch uninstaller
# Distro-agnostic — auto-detects module format
# Usage: sudo bash uninstall.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Error: Run with sudo"; exit 1; fi

KVER=$(uname -r)

# Find the actual module file (regardless of compression)
MODULE=""
for ext in "" ".zst" ".xz" ".gz"; do
    [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" ] && MODULE="/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" && break
done

[ -z "$MODULE" ] && { echo "Cannot find btusb module for kernel $KVER"; exit 1; }
BAK="${MODULE}.bak"

echo "CSR8510 A10 Uninstaller"
echo "======================="
echo ""

[ ! -f "$BAK" ] && {
    echo "No backup found at: $BAK"
    echo "The original module is already in use, or this kernel was never patched."
    echo "To fully restore, reinstall your kernel package:"
    echo "  Debian/Ubuntu: sudo apt install --reinstall linux-image-$(uname -r)"
    echo "  Fedora:        sudo dnf reinstall kernel-core"
    echo "  Arch:          sudo pacman -S linux"
    echo "  openSUSE:      sudo zypper install --force kernel-default"
    exit 1
}

read -p "Restore original module and remove scripts? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted."; exit 0; }

# Restore original
cp "$BAK" "$MODULE"
depmod -a "$KVER"

# Reload
modprobe -r btusb 2>/dev/null || true
modprobe btusb 2>/dev/null || true

# Remove scripts
rm -f /usr/local/bin/patch-btusb-csr8510.sh
rm -f /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook

echo ""
echo "Original module restored. Dongle will stop working."
echo "Re-run: sudo bash install.sh  to re-enable the fix."
echo ""
echo "If you see 'No default controller available', unplug and replug the dongle."
