#!/bin/bash
# Re-patch btusb module after kernel updates
# Distro-agnostic: detects kernel config and adapts
set -euo pipefail

LOGFILE="/var/log/patch-btusb-csr8510.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "===== $(date): Starting btusb CSR8510 patch ====="

for KDIR in /lib/modules/*/build; do
    [ -d "$KDIR" ] || continue
    KVER=$(basename "$(dirname "$KDIR")")
    KCONF="$KDIR/.config"

    # Find the actual module file
    MODULE=""
    for ext in "" ".zst" ".xz" ".gz"; do
        [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" ] && MODULE="/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" && break
    done
    [ -z "$MODULE" ] && continue

    # Already patched? Original ~38KB, patched ~320KB+
    ORIG_SIZE=$(stat -c%s "${MODULE}.bak" 2>/dev/null || echo 0)
    CUR_SIZE=$(stat -c%s "$MODULE" 2>/dev/null || echo 0)
    if [ -f "${MODULE}.bak" ] && [ "$CUR_SIZE" -gt "$((ORIG_SIZE * 3))" ]; then
        echo "  [$KVER] Already patched, skipping."
        continue
    fi

    echo "  [$KVER] Patching..."

    # Detect build tools from kernel config
    [ ! -f "$KCONF" ] && { echo "  No .config, skipping"; continue; }
    LD_IS_LLD=$(grep -q 'CONFIG_LD_IS_LLD=y' "$KCONF" 2>/dev/null && echo "yes" || echo "no")
    CC_VER=$(grep 'CONFIG_CC_VERSION_TEXT' "$KCONF" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    COMPILER=""; LINKER=""
    echo "$CC_VER" | grep -qi 'clang' && COMPILER="clang" || COMPILER="gcc"
    LINKER="$([ "$LD_IS_LLD" = "yes" ] && echo "ld.lld" || echo "ld.bfd")"

    MOD_EXT="${MODULE##*btusb.ko}"
    COMPRESSOR=""; [ "$MOD_EXT" = ".zst" ] && COMPRESSOR="zstd"
    [ "$MOD_EXT" = ".xz" ] && COMPRESSOR="xz"
    [ "$MOD_EXT" = ".gz" ] && COMPRESSOR="gzip"

    BD=$(mktemp -d /tmp/btusb-patch.XXXXX)
    trap "rm -rf '$BD'" EXIT
    KMAJMIN=$(echo "$KVER" | grep -oP '^\d+\.\d+')

    cd "$BD"
    for f in btusb.c btintel.h btbcm.h btrtl.h btmtk.h; do
        curl -sfL "https://raw.githubusercontent.com/torvalds/linux/v${KMAJMIN}/drivers/bluetooth/$f" -o "$BD/$f" 2>/dev/null ||
        cp "$KDIR/drivers/bluetooth/$f" "$BD/$f" 2>/dev/null ||
        { echo "  ERROR: Cannot find $f"; continue 2; }
    done

    python3 - "$BD/btusb.c" << 'PYEOF'
import sys
p=sys.argv[1]
with open(p) as f: c=f.read()
m=False
o='\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI },'
n='\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }, /* Fake CSR clone - CSR8510 A10 */'
if o in c: c=c.replace(o,n,1); m=True
o2='\tif (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n\t    le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001)\n\t\t/* Fake CSR devices'
n2='\tif ((le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001) ||\n\t    (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x10d7 &&\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0xb012))\n\t\t/* Fake CSR devices'
if o2 in c: c=c.replace(o2,n2,1); m=True
o3='\t\tif (le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n\t\t    le16_to_cpu(udev->descriptor.idProduct) == 0x0001)\n\t\t\thdev->setup = btusb_setup_csr;'
n3='\t\tif ((le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0x0001) ||\n\t\t    (le16_to_cpu(udev->descriptor.idVendor)  == 0x10d7 &&\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0xb012))\n\t\t\thdev->setup = btusb_setup_csr;'
if o3 in c: c=c.replace(o3,n3,1); m=True
if m:
    with open(p,'w') as f: f.write(c)
    print("  Patches applied")
else: print("  No changes")
PYEOF

    cat > Makefile << 'MFL'
obj-m += btusb.o
ccflags-y += -DCONFIG_BT_HCIBTUSB_BCM=1 -DCONFIG_BT_HCIBTUSB_RTL=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_MTK=1 -DCONFIG_BT_HCIBTUSB_AUTOSUSPEND=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_POLL_SYNC=1
all: ; $(MAKE) -C /lib/modules/$(KVER)/build M=$(PWD) modules
MFL

    MAKE_ARGS="KVER=$KVER CC=$COMPILER"
    [ -n "$LINKER" ] && MAKE_ARGS="$MAKE_ARGS LD=$LINKER"
    make $MAKE_ARGS 2>&1 || { echo "  COMPILE FAILED"; continue; }

    [ ! -f "${MODULE}.bak" ] && cp "$MODULE" "${MODULE}.bak"
    if [ -n "$COMPRESSOR" ]; then
        $COMPRESSOR -f "$BD/btusb.ko" -o "$BD/btusb.ko${MOD_EXT}"
        cp "$BD/btusb.ko${MOD_EXT}" "$MODULE"
    else
        cp "$BD/btusb.ko" "$MODULE"
    fi
    depmod -a "$KVER"
    echo "  [$KVER] Done"
done

modprobe -r btusb 2>/dev/null || true
modprobe btusb 2>/dev/null || true
echo "===== $(date): Done ====="
