#!/bin/bash
# Patch and rebuild btusb module with CSR8510 A10 (10d7:b012) support
# Called by pacman hook after kernel upgrades, or run manually
set -euo pipefail

LOGFILE="/var/log/patch-btusb-csr8510.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec > >(tee -a "$LOGFILE") 2>&1

echo "===== $(date): Starting btusb CSR8510 patch ====="

for KDIR in /lib/modules/*/build; do
    [ -d "$KDIR" ] || continue
    KVER=$(basename "$(dirname "$KDIR")")
    MODULE="/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.zst"

    [ -f "$MODULE" ] || continue

    # Check if already patched: original module is ~38KB, patched is ~320KB+
    ORIG_SIZE=$(stat -c%s "${MODULE}.bak" 2>/dev/null || echo 0)
    CUR_SIZE=$(stat -c%s "$MODULE" 2>/dev/null || echo 0)
    if [ -f "${MODULE}.bak" ] && [ "$CUR_SIZE" -gt "$((ORIG_SIZE * 3))" ]; then
        echo "  [$KVER] Already patched (size: ${CUR_SIZE}B vs original ${ORIG_SIZE}B), skipping."
        continue
    fi

    echo "  [$KVER] Patching btusb module..."
    BD=$(mktemp -d /tmp/btusb-patch.XXXXX)
    trap "rm -rf '$BD'" EXIT
    KMAJMIN=$(echo "$KVER" | grep -oP '^\d+\.\d+')
    BASE_URL="https://raw.githubusercontent.com/torvalds/linux/v${KMAJMIN}/drivers/bluetooth"

    cd "$BD"
    for f in btusb.c btintel.h btbcm.h btrtl.h btmtk.h; do
        curl -sfL "${BASE_URL}/${f}" -o "$BD/$f" 2>/dev/null ||
        cp "/usr/lib/modules/${KVER}/build/drivers/bluetooth/$f" "$BD/$f" 2>/dev/null ||
        { echo "  [$KVER] ERROR: Cannot find $f"; continue 2; }
    done

    # Patch with Python (precise, handles tabs correctly)
    python3 "$SCRIPT_DIR/patch_btusb.py" "$BD/btusb.c"

    cat > Makefile << 'MAKEFILE'
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
obj-m += btusb.o
ccflags-y += -DCONFIG_BT_HCIBTUSB_BCM=1 -DCONFIG_BT_HCIBTUSB_RTL=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_MTK=1 -DCONFIG_BT_HCIBTUSB_AUTOSUSPEND=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_POLL_SYNC=1
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
MAKEFILE

    if ! make KVER="$KVER" CC=clang LD=ld.lld 2>&1; then
        echo "  [$KVER] ERROR: Compilation failed!"
        continue
    fi

    # Backup original if not already backed up
    [ ! -f "${MODULE}.bak" ] && cp "$MODULE" "${MODULE}.bak"
    zstd -f "$BD/btusb.ko" -o "$BD/btusb.ko.zst"
    cp "$BD/btusb.ko.zst" "$MODULE"
    depmod -a "$KVER"
    echo "  [$KVER] Patched and installed."
done

# Reload for current kernel
echo "Reloading btusb for current kernel..."
modprobe -r btusb 2>/dev/null || true
modprobe btusb 2>/dev/null || true
sleep 2
echo "Verify: bluetoothctl show"
echo "===== $(date): Done ====="
