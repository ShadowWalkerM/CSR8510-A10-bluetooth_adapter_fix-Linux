#!/bin/bash
# CSR8510 A10 Bluetooth Dongle Diagnostics
# Distro-agnostic — run without sudo to check your device

set -euo pipefail

echo "=========================================="
echo "CSR8510 A10 Bluetooth Dongle Diagnostics"
echo "=========================================="
echo ""

# Device presence
echo "[1] Checking for CSR8510 A10 device..."
if lsusb -d 10d7:b012 2>/dev/null | grep -q .; then
    echo "  Found: $(lsusb -d 10d7:b012)"
elif lsusb -d 0a12:0001 2>/dev/null | grep -q .; then
    echo "  Found: $(lsusb -d 0a12:0001)"
else
    echo "  No CSR8510 A10 detected."
    echo "  Check: lsusb | grep -i bluetooth"
    exit 1
fi

# Controller status
echo ""
echo "[2] Bluetooth controller status..."
if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
    echo "  Controller working!"
    bluetoothctl show 2>/dev/null | grep -E "Controller|Powered|Name" | sed 's/^/    /'
else
    echo "  No controller available (patch likely needed)"
fi

# Module state — auto-detect module file
echo ""
echo "[3] Kernel module state..."
KVER=$(uname -r)
MODULE=""
for ext in "" ".zst" ".xz" ".gz"; do
    [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" ] && MODULE="/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" && break
done

if [ -z "$MODULE" ]; then
    echo "  Cannot find btusb module file"
else
    BAK="${MODULE}.bak"
    echo "  Module: $MODULE"
    if [ -f "$BAK" ]; then
        ORIG=$(stat -c%s "$BAK" 2>/dev/null || echo 0)
        CUR=$(stat -c%s "$MODULE" 2>/dev/null || echo 0)
        echo "  Original: ${ORIG} bytes"
        echo "  Current:  ${CUR} bytes"
        if [ "$CUR" -gt "$((ORIG * 3))" ]; then
            echo "  Module IS patched"
        else
            echo "  Module NOT patched"
        fi
    else
        echo "  No backup found, size: $(stat -c%s "$MODULE" 2>/dev/null || echo '?') bytes"
        echo "  (Module may not be patched)"
    fi
fi

# Kernel logs
echo ""
echo "[4] Kernel log check..."
if command -v sudo &>/dev/null; then
    if sudo dmesg 2>/dev/null | grep -qi "CSR.*Setting up"; then
        echo "  CSR initialization ran (good sign)"
    fi
    if sudo dmesg 2>/dev/null | grep -qi "hci0.*timeout"; then
        echo "  HCI timeouts detected (device needs patch)"
    else
        echo "  No HCI timeout errors"
    fi
fi

# Dependencies
echo ""
echo "[5] Dependencies:"
for cmd in curl python3; do
    command -v $cmd &>/dev/null && echo "  $cmd: OK" || echo "  $cmd: MISSING"
done
# Check kernel build tools from .config if available
KCONF="/lib/modules/${KVER}/build/.config"
if [ -f "$KCONF" ]; then
    CC_VER=$(grep 'CONFIG_CC_VERSION_TEXT' "$KCONF" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    echo "  Kernel compiler: $CC_VER"
    # Check if that compiler is available
    echo "$CC_VER" | grep -qi 'clang' && (command -v clang &>/dev/null && echo "  clang: OK" || echo "  clang: MISSING")
    echo "$CC_VER" | grep -qi 'gcc' && (command -v gcc &>/dev/null && echo "  gcc: OK" || echo "  gcc: MISSING")
else
    echo "  Kernel config not found (kernel headers may be missing)"
fi
[ -d "/lib/modules/${KVER}/build" ] && echo "  kernel headers: OK" || echo "  kernel headers: MISSING"

echo ""
echo "=========================================="
echo "To fix: sudo bash install.sh"
echo "=========================================="
