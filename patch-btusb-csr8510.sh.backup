#!/bin/bash
# Patch and rebuild btusb module with CSR8510 A10 (10d7:b012) support
# Called by pacman hook after kernel upgrades, or run manually
set -euo pipefail

LOGFILE="/var/log/patch-btusb-csr8510.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "===== $(date): Starting btusb CSR8510 patch ====="

for KDIR in /lib/modules/*/build; do
    [ -d "$KDIR" ] || continue
    KVER=$(basename "$(dirname "$KDIR")")
    MOD_DIR="/lib/modules/${KVER}/kernel/drivers/bluetooth"
    MODULE="${MOD_DIR}/btusb.ko.zst"

    [ -f "$MODULE" ] || continue

    # Skip if already patched
    if zstd -d "$MODULE" -c 2>/dev/null | strings | grep -q 'Fake CSR clone'; then
        echo "  [$KVER] Already patched, skipping."
        continue
    fi

    echo "  [$KVER] Patching btusb module..."

    BUILDDIR=$(mktemp -d /tmp/btusb-patch.XXXXX)
    trap "rm -rf '$BUILDDIR'" EXIT

    KERNEL_TAG="v$(echo "$KVER" | grep -oP '^\d+\.\d+')"
    BASE_URL="https://raw.githubusercontent.com/torvalds/linux/${KERNEL_TAG}/drivers/bluetooth"

    cd "$BUILDDIR"

    # Download source files (try GitHub first, fall back to local kernel source)
    DOWNLOAD_OK=true
    for f in btusb.c btintel.h btbcm.h btrtl.h btmtk.h; do
        if ! curl -sfL "${BASE_URL}/${f}" -o "${BUILDDIR}/${f}" 2>/dev/null; then
            LOCAL_SRC="/usr/lib/modules/${KVER}/build/drivers/bluetooth"
            if [ -f "${LOCAL_SRC}/${f}" ]; then
                cp "${LOCAL_SRC}/${f}" "${BUILDDIR}/${f}"
            else
                echo "  [$KVER] ERROR: Cannot find source for $f. Skipping."
                DOWNLOAD_OK=false
                break
            fi
        fi
    done
    [ "$DOWNLOAD_OK" = true ] || continue

    # ── Patch 1: Change existing BTUSB_ACTIONS_SEMI entry to BTUSB_CSR ──
    # The kernel already has: { USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI }
    # We need to change it to: { USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }
    # AND add a comment so we can detect the patch later
    if grep -q 'USB_DEVICE(0x10d7, 0xb012).*BTUSB_ACTIONS_SEMI' btusb.c; then
        sed -i 's/{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI }/{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }, \/* Fake CSR clone - CSR8510 A10 *\//' btusb.c
    elif grep -q 'USB_DEVICE(0x10d7, 0xb012).*BTUSB_CSR' btusb.c; then
        # Already has CSR entry (maybe from a previous kernel version that included it)
        # Just add the marker comment if not present
        if ! grep -q 'Fake CSR clone' btusb.c; then
            sed -i 's/{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }/{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }, \/* Fake CSR clone - CSR8510 A10 *\//' btusb.c
        fi
    else
        # No entry at all — add one after the original CSR entry
        sed -i '/{ USB_DEVICE(0x0a12, 0x0001), .driver_info = BTUSB_CSR },/a\
\t/* Fake CSR clone - CSR8510 A10 */\n\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR },' btusb.c
    fi

    # ── Patch 2: Add device to interrupt transfer size check ──
    # Find the check for 0x0a12:0x0001 and add our device as an alternative
    LINE=$(grep -n 'le16_to_cpu(data->udev->descriptor.idVendor).*0x0a12' btusb.c | head -1 | cut -d: -f1)
    if [ -n "$LINE" ]; then
        # Check if already patched
        if ! sed -n "${LINE},$((LINE+5))p" btusb.c | grep -q '0x10d7'; then
            sed -i "${LINE}s/if (/if ((/" btusb.c
            NEXT=$((LINE + 1))
            sed -i "${NEXT}s/== 0x0001)/== 0x0001) ||/" btusb.c
            sed -i "${NEXT}a\\t    (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x10d7 \\&\\&\\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0xb012))" btusb.c
        fi
    fi

    # ── Patch 3: Add device to btusb_check_fake_csr setup check ──
    LINE=$(grep -n 'le16_to_cpu(udev->descriptor.idVendor).*0x0a12' btusb.c | tail -1 | cut -d: -f1)
    if [ -n "$LINE" ]; then
        # Check if already patched
        if ! sed -n "${LINE},$((LINE+5))p" btusb.c | grep -q '0x10d7'; then
            sed -i "${LINE}s/if (/if ((/" btusb.c
            NEXT=$((LINE + 1))
            sed -i "${NEXT}s/== 0x0001)/== 0x0001) ||/" btusb.c
            sed -i "${NEXT}a\\t\t    (le16_to_cpu(udev->descriptor.idVendor)  == 0x10d7 \\&\\&\\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0xb012))" btusb.c
        fi
    fi

    # ── Compile ──
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

    if ! make KVER="$KVER" CC=clang 2>&1; then
        echo "  [$KVER] ERROR: Compilation failed!"
        continue
    fi

    # Backup and install
    [ ! -f "${MODULE}.bak" ] && cp "$MODULE" "${MODULE}.bak"
    zstd -f "$BUILDDIR/btusb.ko" -o "$BUILDDIR/btusb.ko.zst"
    cp "$BUILDDIR/btusb.ko.zst" "$MODULE"

    echo "  [$KVER] Patched and installed successfully."
done

echo "===== $(date): Done ====="
