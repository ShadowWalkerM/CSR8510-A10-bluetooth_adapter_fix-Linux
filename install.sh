#!/bin/bash
# CSR8510 A10 (10d7:b012) btusb patch installer
# Fixes cheap CSR8510 A10 Bluetooth dongles that work on Windows but not Linux
#
# Usage: sudo bash install.sh
#        curl -sL <url>/install.sh | sudo bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  CSR8510 A10 Bluetooth Dongle Patch Installer               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Check root ──
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    echo "Usage: sudo bash $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Check if device is present ──
echo -e "${YELLOW}[1/5] Checking for CSR8510 A10 device...${NC}"

DEVICE_FOUND=false
for VID_PID in "10d7:b012" "0a12:0001"; do
    if lsusb -d "$VID_PID" 2>/dev/null | grep -q .; then
        DEVICE_FOUND=true
        echo -e "  ${GREEN}Found: $(lsusb -d "$VID_PID" 2>/dev/null)${NC}"
        break
    fi
done

if ! $DEVICE_FOUND; then
    echo -e "  ${YELLOW}Warning: No CSR8510 A10 device detected via USB.${NC}"
    echo "  The patch will still be installed and will take effect when you plug in the dongle."
    echo ""
    read -p "  Continue anyway? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ── Install dependencies ──
echo -e "${YELLOW}[2/5] Checking dependencies...${NC}"

MISSING=()
for pkg in clang zstd curl; do
    if ! pacman -Q "$pkg" &>/dev/null; then
        MISSING+=("$pkg")
    fi
done

# Check kernel headers
KVER=$(uname -r)
if [ ! -d "/lib/modules/${KVER}/build" ]; then
    # Try to find the headers package
    if pacman -Q linux-cachyos-headers &>/dev/null; then
        echo -e "  ${YELLOW}linux-cachyos-headers installed but doesn't match running kernel${NC}"
        echo "  Running: $KVER"
        echo "  Installed headers may be for a different kernel version."
        echo "  The patch will work for the kernel that matches the headers."
    else
        MISSING+=("linux-cachyos-headers")
    fi
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}Installing missing packages: ${MISSING[*]}${NC}"
    pacman -S --noconfirm "${MISSING[@]}" 2>&1 | tail -5
else
    echo -e "  ${GREEN}All dependencies satisfied.${NC}"
fi

# ── Install files ──
echo -e "${YELLOW}[3/5] Installing patch script and pacman hook...${NC}"

# Determine source directory
if [ -f "${SCRIPT_DIR}/patch-btusb-csr8510.sh" ]; then
    PATCH_SRC="${SCRIPT_DIR}/patch-btusb-csr8510.sh"
    HOOK_SRC="${SCRIPT_DIR}/99-patch-btusb-csr8510.hook"
else
    echo -e "  ${RED}Error: Cannot find patch-btusb-csr8510.sh${NC}"
    echo "  Make sure you extracted the full package."
    exit 1
fi

install -Dm755 "$PATCH_SRC" /usr/local/bin/patch-btusb-csr8510.sh
echo -e "  ${GREEN}Installed: /usr/local/bin/patch-btusb-csr8510.sh${NC}"

PY_SRC="${SCRIPT_DIR}/patch_btusb.py"
if [ -f "$PY_SRC" ]; then
    install -Dm755 "$PY_SRC" /usr/local/bin/patch_btusb.py
    echo -e "  ${GREEN}Installed: /usr/local/bin/patch_btusb.py${NC}"
fi

install -Dm644 "$HOOK_SRC" /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook
echo -e "  ${GREEN}Installed: /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook${NC}"

# ── Run the patch ──
echo -e "${YELLOW}[4/5] Patching btusb module for current kernel...${NC}"
echo "  This will download btusb.c, apply patches, and recompile."
echo ""

if /usr/local/bin/patch-btusb-csr8510.sh 2>&1 | tee /var/log/patch-btusb-csr8510.log; then
    echo ""
    echo -e "  ${GREEN}Patch applied successfully!${NC}"
else
    echo ""
    echo -e "  ${RED}Patch failed! Check the log: /var/log/patch-btusb-csr8510.log${NC}"
    echo ""
    echo "Common issues:"
    echo "  - Kernel headers don't match running kernel"
    echo "  - No internet access (needed to download btusb.c)"
    echo "  - clang not installed or wrong version"
    exit 1
fi

# ── Verify ──
echo -e "${YELLOW}[5/5] Verifying...${NC}"

# Check if module is patched
if [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst" ]; then
    if zstd -d "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst" -c 2>/dev/null | strings | grep -q 'Fake CSR clone'; then
        echo -e "  ${GREEN}Module is patched for 10d7:b012${NC}"
    else
        echo -e "  ${YELLOW}Module file exists but may not be patched${NC}"
    fi
fi

# Check if dongle is working
echo ""
echo "  Checking Bluetooth controller..."
sleep 2

if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
    echo -e "  ${GREEN}Bluetooth controller is working!${NC}"
    bluetoothctl show 2>/dev/null | head -3 | sed 's/^/  /'
else
    echo -e "  ${YELLOW}Bluetooth controller not detected yet.${NC}"
    echo "  Try unplugging and replugging the dongle."
    echo "  Then run: bluetoothctl show"
fi

# ── Done ──
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "What was installed:"
echo "  - Patch script: /usr/local/bin/patch-btusb-csr8510.sh"
echo "  - Pacman hook:  /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook"
echo "  - Log file:     /var/log/patch-btusb-csr8510.log"
echo ""
echo "The patch will automatically re-apply after kernel updates."
echo ""
echo "To uninstall:"
echo "  sudo rm /usr/local/bin/patch-btusb-csr8510.sh"
echo "  sudo rm /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook"
echo "  sudo cp /lib/modules/\$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst.bak \\"
echo "          /lib/modules/\$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst"
