#!/bin/bash
# CSR8510 A10 (10d7:b012) btusb patch installer
# Fixes cheap CSR8510 A10 Bluetooth dongles on Linux
# Distro-agnostic: works on Arch, Debian, Ubuntu, Fedora, openSUSE, etc.
#
# Usage: sudo bash install.sh
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  CSR8510 A10 Bluetooth Dongle Patch Installer               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Run with sudo${NC}"; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Distro detection ──
echo -e "${YELLOW}[1/7] Detecting distribution...${NC}"
if command -v apt &>/dev/null; then
    DISTRO="debian"; PM="apt"
    HEADER_PKG="linux-headers-$(uname -r)"
    PM_INSTALL="apt install -y"
elif command -v dnf &>/dev/null; then
    DISTRO="fedora"; PM="dnf"
    HEADER_PKG="kernel-devel"
    PM_INSTALL="dnf install -y"
elif command -v zypper &>/dev/null; then
    DISTRO="suse"; PM="zypper"
    HEADER_PKG="kernel-devel"
    PM_INSTALL="zypper install -y"
elif command -v pacman &>/dev/null; then
    DISTRO="arch"; PM="pacman"
    HEADER_PKG="linux-cachyos-headers linux-headers"
    PM_INSTALL="pacman -S --noconfirm"
elif command -v apk &>/dev/null; then
    DISTRO="alpine"; PM="apk"
    HEADER_PKG="linux-headers"
    PM_INSTALL="apk add"
else
    DISTRO="unknown"; PM=""
    HEADER_PKG="kernel headers"
    PM_INSTALL="" # manual install
fi
echo "  Distro: $DISTRO  Package manager: $PM"

# ── Detect kernel compiler & linker ──
echo -e "${YELLOW}[2/7] Detecting kernel build tools...${NC}"
KVER=$(uname -r)
KMAJMIN=$(echo "$KVER" | grep -oP '^\d+\.\d+')
KCONFIG="/lib/modules/${KVER}/build/.config"

[ -d "/lib/modules/${KVER}/build" ] || { echo -e "${RED}No kernel headers for $KVER${NC}"; echo "Install: $HEADER_PKG"; exit 1; }

# Read kernel build config
CC_VER=$(grep 'CONFIG_CC_VERSION_TEXT' "$KCONFIG" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
LD_IS_LLD=$(grep -q 'CONFIG_LD_IS_LLD=y' "$KCONFIG" 2>/dev/null && echo "yes" || echo "no")
MOD_COMPRESS=$(grep 'CONFIG_MODULE_COMPRESS_' "$KCONFIG" 2>/dev/null | grep '=y' | head -1 | sed 's/CONFIG_MODULE_COMPRESS_//; s/=y//' || echo "")

echo "  Kernel: $KVER (v$KMAJMIN)"
echo "  Built with: $CC_VER"

# Determine compiler
COMPILER=""
if echo "$CC_VER" | grep -qi 'clang'; then
    COMPILER="clang"
    LINKER="$([ "$LD_IS_LLD" = "yes" ] && echo "ld.lld" || echo "ld.bfd")"
    echo "  Compiler: clang  Linker: $LINKER"
elif echo "$CC_VER" | grep -qi 'gcc'; then
    COMPILER="gcc"
    LINKER="ld.bfd"
    echo "  Compiler: gcc  Linker: ld.bfd"
else
    # Fallback: try what's available
    COMPILER="$(command -v clang || command -v gcc || echo "cc")"
    LINKER="$(command -v ld.lld || command -v ld.bfd || echo "ld")"
    echo "  Compiler: $COMPILER (detected)  Linker: $LINKER"
fi

# Determine module extension & compressor
case "$MOD_COMPRESS" in
    ZSTD) MOD_EXT=".zst"; COMPRESSOR="zstd";;
    XZ)   MOD_EXT=".xz";  COMPRESSOR="xz";;
    GZIP) MOD_EXT=".gz";  COMPRESSOR="gzip";;
    *)    # Check actual file
          if ls /lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.* 2>/dev/null | grep -q .; then
              MOD_EXT=".$(ls /lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko.* 2>/dev/null | head -1 | rev | cut -d. -f1 | rev)"
          else
              MOD_EXT=""
          fi
          [ -z "$MOD_EXT" ] && MOD_EXT=".zst" COMPRESSOR="zstd" # best guess
          case "$MOD_EXT" in
              .zst) COMPRESSOR="zstd";;
              .xz)  COMPRESSOR="xz";;
              .gz)  COMPRESSOR="gzip";;
              *)    MOD_EXT=""; COMPRESSOR="";;
          esac;;
esac
[ -n "$MOD_EXT" ] && echo "  Module compression: ${MOD_EXT} (${COMPRESSOR})" || echo "  Module: uncompressed"

# ── Install dependencies ──
echo -e "${YELLOW}[3/7] Installing dependencies...${NC}"
NEED_INSTALL=""
for tool in "$COMPILER" "$LINKER" "$COMPRESSOR" curl python3; do
    command -v "$tool" &>/dev/null || NEED_INSTALL="$NEED_INSTALL $tool"
done
# Also check kernel headers via config existence
[ -f "$KCONFIG" ] || NEED_INSTALL="$NEED_INSTALL kernel-headers"

if [ -n "$NEED_INSTALL" ] && [ -n "$PM" ]; then
    # Map tool names to package names per distro
    PKGS=""
    for t in $NEED_INSTALL; do
        case "$t" in
            clang)     PKGS="$PKGS clang";;
            gcc)       PKGS="$PKGS gcc";;
            ld.lld)    PKGS="$PKGS lld";;
            ld.bfd)    PKGS="$PKGS binutils";;
            ld)        PKGS="$PKGS binutils";;
            ld.lld)    PKGS="$PKGS lld";;
            zstd)      PKGS="$PKGS zstd";;
            xz)        PKGS="$PKGS xz-utils";;
            gzip)      PKGS="$PKGS gzip";;
            curl)      PKGS="$PKGS curl";;
            python3)   PKGS="$PKGS python3";;
            kernel-headers)
                case "$DISTRO" in
                    debian)  PKGS="$PKGS $(echo "$HEADER_PKG")";;
                    fedora)  PKGS="$PKGS kernel-devel";;
                    suse)    PKGS="$PKGS kernel-devel";;
                    arch)    for p in $HEADER_PKG; do PKGS="$PKGS $p"; done;;
                    alpine)  PKGS="$PKGS linux-headers";;
                esac;;
        esac
    done
    if [ -n "$PKGS" ]; then
        echo "  Installing: $PKGS"
        $PM_INSTALL $PKGS
    fi
elif [ -n "$NEED_INSTALL" ]; then
    echo -e "${YELLOW}  Missing tools: $NEED_INSTALL${NC}"
    echo "  Install manually, then re-run this script."
    exit 1
fi
echo -e "  ${GREEN}All dependencies present${NC}"

# ── Download source ──
echo -e "${YELLOW}[4/7] Downloading kernel source...${NC}"
BD=$(mktemp -d /tmp/btusb-build.XXXXX)
cd "$BD"
BASE="https://raw.githubusercontent.com/torvalds/linux/v${KMAJMIN}/drivers/bluetooth"
for f in btusb.c btintel.h btbcm.h btrtl.h btmtk.h; do
    echo -n "  $f ... "
    if curl -sfL "${BASE}/${f}" -o "$BD/$f" 2>/dev/null; then
        echo "OK"
    elif cp "/lib/modules/${KVER}/build/drivers/bluetooth/$f" "$BD/$f" 2>/dev/null; then
        echo "OK (local)"
    else
        echo -e "${RED}FAILED${NC}"
        echo "  Try: install git and clone the kernel source tree"
        exit 1
    fi
done

# ── Apply 3 patches ──
echo -e "${YELLOW}[5/7] Applying patches...${NC}"
python3 - "$BD/btusb.c" << 'PYEOF'
import sys
p = sys.argv[1]
with open(p) as f: c = f.read()
m = False

o = '\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI },'
n = '\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }, /* Fake CSR clone - CSR8510 A10 */'
if o in c: c = c.replace(o, n, 1); m = True; print("  [1/3] Device table: ACTIONS_SEMI -> CSR OK")
else: print("  [1/3] Device table: already correct")

o2 = '\tif (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n\t    le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001)\n\t\t/* Fake CSR devices'
n2 = '\tif ((le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001) ||\n\t    (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x10d7 &&\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0xb012))\n\t\t/* Fake CSR devices'
if o2 in c: c = c.replace(o2, n2, 1); m = True; print("  [2/3] Interrupt size: patched OK")
else: print("  [2/3] Interrupt size: already done")

o3 = '\t\tif (le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n\t\t    le16_to_cpu(udev->descriptor.idProduct) == 0x0001)\n\t\t\thdev->setup = btusb_setup_csr;'
n3 = '\t\tif ((le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0x0001) ||\n\t\t    (le16_to_cpu(udev->descriptor.idVendor)  == 0x10d7 &&\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0xb012))\n\t\t\thdev->setup = btusb_setup_csr;'
if o3 in c: c = c.replace(o3, n3, 1); m = True; print("  [3/3] Setup routing: patched OK")
else: print("  [3/3] Setup routing: already done")

if m:
    with open(p, 'w') as f: f.write(c)
    print("  All patches applied.")
else: print("  No changes needed.")
PYEOF

# ── Compile ──
echo -e "${YELLOW}[6/7] Compiling patched module...${NC}"
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

MAKE_ARGS="KVER=$KVER CC=$COMPILER"
[ -n "$LINKER" ] && MAKE_ARGS="$MAKE_ARGS LD=$LINKER"

if ! make $MAKE_ARGS 2>&1; then
    echo -e "${RED}Compilation failed${NC}"
    echo "  Trying alternative compiler..."
    if [ "$COMPILER" = "clang" ]; then
        MAKE_ARGS="KVER=$KVER CC=gcc"
        make $MAKE_ARGS 2>&1 || { echo -e "${RED}Still failed${NC}"; exit 1; }
    elif [ "$COMPILER" = "gcc" ]; then
        MAKE_ARGS="KVER=$KVER CC=clang LD=ld.lld"
        make $MAKE_ARGS 2>&1 || { echo -e "${RED}Still failed${NC}"; exit 1; }
    fi
fi

# ── Install ──
echo -e "${YELLOW}[7/7] Installing patched module...${NC}"

# Find the actual module filename
MODULE_SRC=""
for ext in "" ".zst" ".xz" ".gz"; do
    [ -f "/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" ] && MODULE_SRC="/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko${ext}" && break
done
[ -z "$MODULE_SRC" ] && { echo -e "${RED}Cannot find btusb module file${NC}"; exit 1; }
MODULE_EXT="${MODULE_SRC##*btusb.ko}"

# Backup original
[ ! -f "${MODULE_SRC}.bak" ] && cp "$MODULE_SRC" "${MODULE_SRC}.bak" && echo "  Original backed up"

# Compress and install
if [ -n "$MODULE_EXT" ] && [ -n "$COMPRESSOR" ]; then
    $COMPRESSOR -f "$BD/btusb.ko" -o "$BD/btusb.ko${MODULE_EXT}"
    cp "$BD/btusb.ko${MODULE_EXT}" "$MODULE_SRC"
else
    cp "$BD/btusb.ko" "$MODULE_SRC"
fi
depmod -a "$KVER"

# Install auto-update mechanism
if [ "$DISTRO" = "arch" ] && [ -f "${SCRIPT_DIR}/99-patch-btusb-csr8510.hook" ]; then
    mkdir -p /etc/pacman.d/hooks
    cp "${SCRIPT_DIR}/99-patch-btusb-csr8510.hook" /etc/pacman.d/hooks/
    echo "  Pacman hook installed (auto-patches on kernel updates)"
fi

if [ -f "${SCRIPT_DIR}/patch-btusb-csr8510.sh" ]; then
    cp "${SCRIPT_DIR}/patch-btusb-csr8510.sh" /usr/local/bin/
    chmod +x /usr/local/bin/patch-btusb-csr8510.sh
    echo "  Patch script installed to /usr/local/bin/"
    echo "  After kernel updates, run: sudo patch-btusb-csr8510.sh"
fi

# Reload
modprobe -r btusb 2>/dev/null || true
modprobe btusb 2>/dev/null || true

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation complete!                                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Module: $(ls -lh "$MODULE_SRC" | awk '{print $5}') (backup: ${MODULE_SRC}.bak)"
echo "  Distro: $DISTRO  Kernel: $KVER"
echo "  Compiler: $COMPILER  Linker: $LINKER"
echo ""

sleep 2
if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
    echo -e "${GREEN}✓ Bluetooth controller detected!${NC}"
    bluetoothctl show 2>/dev/null | grep -E "Controller|Powered|Name" | head -3
    echo ""
    echo "  If powered off: rfkill unblock bluetooth && bluetoothctl power on"
else
    echo -e "${YELLOW}Unplug and replug the dongle, then: bluetoothctl show${NC}"
fi
echo ""
echo "  Kernel updates: re-run: sudo bash install.sh"
echo "  Uninstall:      sudo bash uninstall.sh"
echo ""
