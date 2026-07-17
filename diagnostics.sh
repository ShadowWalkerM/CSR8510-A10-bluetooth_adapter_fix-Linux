#!/bin/bash
# CSR8510 A10 Bluetooth Dongle Patch - Diagnostics Script
# Run without sudo first to check if your device is affected
# Then run with sudo to install the fix

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  CSR8510 A10 Bluetooth Dongle Diagnostics & Fix for Linux   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Check if the device is present ──
echo -e "${YELLOW}[1/6] Checking for CSR8510 A10 device...${NC}"

DEVICE_FOUND=false
DEVICE_INFO=""

# Check for the specific USB IDs that this patch targets
# 10d7:b012 = CSR8510 A10 clone (Actions Semiconductor rebrand)
# 0a12:0001 = Original Cambridge Silicon Radio CSR8510 A10
for VID_PID in "10d7:b012" "0a12:0001"; do
    VID="${VID_PID%%:*}"
    PID="${VID_PID##*:}"
    if lsusb -d "$VID_PID" 2>/dev/null | grep -q .; then
        DEVICE_FOUND=true
        DEVICE_INFO=$(lsusb -d "$VID_PID" 2>/dev/null)
        DEVICE_VID="$VID"
        DEVICE_PID="$PID"
        echo -e "  ${GREEN}Found: $DEVICE_INFO${NC}"
        break
    fi
done

if ! $DEVICE_FOUND; then
    echo -e "  ${RED}No CSR8510 A10 device detected.${NC}"
    echo ""
    echo "  Your USB devices:"
    lsusb 2>/dev/null | grep -iE 'bluetooth|csr|cambridge' || echo "  (none found)"
    echo ""
    echo "  If your dongle has a different USB ID, this patch may not apply."
    echo "  Check your device ID with: lsusb"
    exit 1
fi

# ── Step 2: Check current kernel module state ──
echo -e "${YELLOW}[2/6] Checking kernel module state...${NC}"

KVER=$(uname -r)
echo "  Kernel: $KVER"

if lsmod | grep -q btusb; then
    echo -e "  ${GREEN}btusb module: loaded${NC}"
else
    echo -e "  ${RED}btusb module: NOT loaded${NC}"
fi

if [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst" ]; then
    echo -e "  ${GREEN}btusb module file: present${NC}"
else
    echo -e "  ${RED}btusb module file: NOT found${NC}"
fi

# ── Step 3: Check if already patched ──
echo -e "${YELLOW}[3/6] Checking if already patched...${NC}"

ALREADY_PATCHED=false
if [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst" ]; then
    if zstd -d "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst" -c 2>/dev/null | strings | grep -q 'Fake CSR clone'; then
        ALREADY_PATCHED=true
        echo -e "  ${GREEN}Module is already patched for 10d7:b012${NC}"
    fi
fi

if $ALREADY_PATCHED; then
    echo ""
    echo -e "  ${GREEN}Your dongle should already be working!${NC}"
    echo "  Verify with: bluetoothctl show"
    exit 0
else
    echo -e "  ${YELLOW}Module is NOT patched — dongle will not work${NC}"
fi

# ── Step 4: Check if dongle is currently working ──
echo -e "${YELLOW}[4/6] Checking Bluetooth controller status...${NC}"

if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
    echo -e "  ${GREEN}Bluetooth controller is working!${NC}"
    bluetoothctl show 2>/dev/null | head -5 | sed 's/^/  /'
    echo ""
    echo "  If Bluetooth works, you may not need this patch."
    exit 0
else
    echo -e "  ${RED}No default controller available — dongle is not working${NC}"
fi

# ── Step 5: Check for error messages ──
echo -e "${YELLOW}[5/6] Checking kernel logs for errors...${NC}"

if command -v sudo &>/dev/null; then
    ERRORS=$(sudo dmesg 2>/dev/null | grep -iE 'hci0.*timeout|hci0.*failed.*-110' | tail -3)
    if [ -n "$ERRORS" ]; then
        echo -e "  ${RED}Found HCI timeout errors (expected for unpatched module):${NC}"
        echo "$ERRORS" | sed 's/^/  /'
    else
        echo "  No HCI timeout errors found in recent logs."
    fi
else
    echo "  (Cannot check dmesg without sudo)"
fi

# ── Step 6: Check dependencies ──
echo -e "${YELLOW}[6/6] Checking dependencies...${NC}"

MISSING_DEPS=()

# Check for clang
if command -v clang &>/dev/null; then
    echo -e "  ${GREEN}clang: $(clang --version 2>&1 | head -1)${NC}"
else
    echo -e "  ${RED}clang: NOT installed${NC}"
    MISSING_DEPS+=("clang")
fi

# Check for zstd
if command -v zstd &>/dev/null; then
    echo -e "  ${GREEN}zstd: installed${NC}"
else
    echo -e "  ${RED}zstd: NOT installed${NC}"
    MISSING_DEPS+=("zstd")
fi

# Check for kernel headers
if [ -d "/lib/modules/${KVER}/build" ]; then
    echo -e "  ${GREEN}kernel headers: present (${KVER})${NC}"
else
    echo -e "  ${RED}kernel headers: NOT found${NC}"
    MISSING_DEPS+=("linux-cachyos-headers (or your distro's kernel headers)")
fi

# Check for curl
if command -v curl &>/dev/null; then
    echo -e "  ${GREEN}curl: installed${NC}"
else
    echo -e "  ${RED}curl: NOT installed${NC}"
    MISSING_DEPS+=("curl")
fi

# ── Summary ──
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${RED}Missing dependencies:${NC}"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Install them with:"
    echo "  sudo pacman -S clang zstd curl linux-cachyos-headers"
    echo ""
fi

echo -e "${GREEN}To fix your CSR8510 A10 dongle, run:${NC}"
echo ""
echo "  sudo bash install.sh"
echo ""
echo -e "${GREEN}Or if you downloaded just this script:${NC}"
echo ""
echo "  curl -sL https://raw.githubusercontent.com/nosferatu/csr8510-btusb-patch/main/install.sh | sudo bash"
echo ""
