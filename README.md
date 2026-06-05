# CSR8510 A10 Bluetooth Dongle Fix for Linux

Fixes cheap CSR8510 A10 Bluetooth 4.0 USB dongles (USB ID `10d7:b012`) that work on Windows but show **"No default controller available"** on Linux.

---

## Quick Install

```bash
git clone https://github.com/ShadowWalkerM/CSR8510-A10-bluetooth_adapter_fix-Linux.git
cd CSR8510-A10-bluetooth_adapter_fix-Linux
sudo bash install.sh
```

The installer auto-detects your distro, compiler, linker, and module format.

### Verify

```bash
bluetoothctl show
```
Expected: `Controller XX:XX:XX:XX:XX:XX (public)`

If powered off:
```bash
rfkill unblock bluetooth
bluetoothctl power on
```

---

## What This Fix Does

The Linux kernel's `btusb` driver already knows about `10d7:b012` but **misclassifies it** as an Actions Semiconductor device (`BTUSB_ACTIONS_SEMI`) instead of a Cambridge Silicon Radio device (`BTUSB_CSR`). This means the CSR firmware upload path is never triggered, so the dongle runs without firmware and all HCI commands time out.

This fix applies **3 patches** to the kernel's `btusb.c` source, then compiles and installs the patched module:

| Patch | What | Why |
|-------|------|-----|
| 1. Device table | `BTUSB_ACTIONS_SEMI` → `BTUSB_CSR` | Kernel knows it's CSR, not Actions Semi |
| 2. Interrupt size | Adds `10d7:b012` to the fake-CSR fix | Clones need endpoint descriptor size |
| 3. Setup routing | Routes through `btusb_setup_csr()` | Detects clone, applies quirks, activates RX |

---

## Installing Kernel Headers

You need kernel headers **matching your running kernel**. Install them before running the installer:

```bash
# Debian / Ubuntu / Linux Mint
sudo apt install linux-headers-$(uname -r)

# Fedora
sudo dnf install kernel-devel

# openSUSE
sudo zypper install kernel-devel

# Arch Linux (generic kernel)
sudo pacman -S linux-headers

# CachyOS
sudo pacman -S linux-cachyos-headers

# Alpine Linux
sudo apk add linux-headers

# Gentoo
emerge sys-kernel/gentoo-sources
```

Check they're installed:
```bash
ls -d /lib/modules/$(uname -r)/build
```

---

## Distro Support

The installer detects and adapts to your distro automatically:

| Distro | Package manager | Auto-update after kernel upgrade | Status |
|--------|----------------|----------------------------------|--------|
| CachyOS | pacman | Pacman hook | Tested working |
| Arch Linux | pacman | Pacman hook | Tested working |
| Debian / Ubuntu | apt | Manual re-run | Should work |
| Fedora | dnf | Manual re-run | Should work |
| openSUSE | zypper | Manual re-run | Should work |
| Alpine Linux | apk | Manual re-run | Should work |
| Gentoo | emerge | Manual re-run | Untested |

The core fix (patching `btusb.c` + compiling) works on any Linux. The only distro-specific parts are:
- Package manager commands for installing dependencies
- Auto-update hook (pacman hook only works on Arch-based distros)

---

## Manual Install (Without the Script)

If the installer doesn't work for your distro, do it manually:

### 1. Install dependencies

```bash
# Compiler + tools
sudo apt install clang llvm zstd curl python3   # Debian/Ubuntu
sudo dnf install clang llvm zstd curl python3   # Fedora
sudo pacman -S clang zstd curl python3          # Arch

# Kernel headers (must match your kernel!)
sudo apt install linux-headers-$(uname -r)      # Debian/Ubuntu
sudo dnf install kernel-devel                   # Fedora
sudo pacman -S linux-headers                    # Arch
```

### 2. Download kernel source

```bash
KVER=$(uname -r)
KMAJMIN=$(echo "$KVER" | grep -oP '^\d+\.\d+')
mkdir -p /tmp/btusb-fix && cd /tmp/btusb-fix

for f in btusb.c btintel.h btbcm.h btrtl.h btmtk.h; do
    curl -sfL "https://raw.githubusercontent.com/torvalds/linux/v${KMAJMIN}/drivers/bluetooth/$f" -o "$f" ||
    cp "/lib/modules/${KVER}/build/drivers/bluetooth/$f" "$f"
done
```

### 3. Apply patches

```bash
python3 << 'PYEOF'
with open("btusb.c") as f: c = f.read()

# Patch 1: Device table
c = c.replace(
    '\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI },',
    '\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }, /* Fake CSR clone - CSR8510 A10 */'
)

# Patch 2: Interrupt transfer size
c = c.replace(
    '\tif (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n\t    le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001)\n\t\t/* Fake CSR devices',
    '\tif ((le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001) ||\n\t    (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x10d7 &&\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0xb012))\n\t\t/* Fake CSR devices'
)

# Patch 3: Setup routing
c = c.replace(
    '\t\tif (le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n\t\t    le16_to_cpu(udev->descriptor.idProduct) == 0x0001)\n\t\t\thdev->setup = btusb_setup_csr;',
    '\t\tif ((le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0x0001) ||\n\t\t    (le16_to_cpu(udev->descriptor.idVendor)  == 0x10d7 &&\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0xb012))\n\t\t\thdev->setup = btusb_setup_csr;'
)

with open("btusb.c", "w") as f: f.write(c)
print("3 patches applied")
PYEOF
```

### 4. Detect build tools from kernel config

```bash
KCONF="/lib/modules/$(uname -r)/build/.config"

# Detect compiler
grep 'CONFIG_CC_VERSION_TEXT' "$KCONF"
# clang or gcc?

# Detect linker
grep -q 'CONFIG_LD_IS_LLD=y' "$KCONF" && LINKER="ld.lld" || LINKER="ld.bfd"

# Detect module compression
grep 'CONFIG_MODULE_COMPRESS_' "$KCONF"
# ZSTD → .ko.zst, XZ → .ko.xz, GZIP → .ko.gz, none → .ko
```

### 5. Compile

```bash
cat > Makefile << 'EOF'
obj-m += btusb.o
ccflags-y += -DCONFIG_BT_HCIBTUSB_BCM=1 -DCONFIG_BT_HCIBTUSB_RTL=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_MTK=1 -DCONFIG_BT_HCIBTUSB_AUTOSUSPEND=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_POLL_SYNC=1
all:
	$(MAKE) -C /lib/modules/$(KVER)/build M=$(PWD) modules
EOF

# Use the detected compiler and linker
# For clang + lld:
make CC=clang LD=ld.lld

# For gcc + bfd:
make CC=gcc
```

### 6. Install

```bash
# Find the module file for your kernel
KVER=$(uname -r)
MODULE="/lib/modules/${KVER}/kernel/drivers/bluetooth/btusb.ko"
[ -f "${MODULE}.zst" ] && MODULE="${MODULE}.zst"
[ -f "${MODULE}.xz" ]  && MODULE="${MODULE}.xz"

# Backup original
sudo cp "$MODULE" "${MODULE}.bak"

# Install patched module
sudo cp btusb.ko /tmp/
# Compress if needed
[ "${MODULE##*.}" = "zst" ] && sudo zstd -f /tmp/btusb.ko -o "$MODULE"
[ "${MODULE##*.}" = "xz" ]  && sudo xz -f /tmp/btusb.ko && sudo cp /tmp/btusb.ko.xz "$MODULE"
[ "${MODULE##*.}" = "gz" ]  && sudo gzip -f /tmp/btusb.ko && sudo cp /tmp/btusb.ko.gz "$MODULE"
[[ "$MODULE" != *".ko."* ]] && sudo cp /tmp/btusb.ko "$MODULE"

sudo depmod -a "$KVER"
```

### 7. Reload and test

```bash
sudo modprobe -r btusb
sudo modprobe btusb
sleep 2
bluetoothctl show
```

---

## After a Kernel Update

**Yes, you need to re-patch after every kernel update.** A new kernel installs a fresh, unpatched `btusb` module.

### Option 1: Re-run the installer (works on any distro)

```bash
cd CSR8510-A10-bluetooth_adapter_fix-Linux
sudo bash install.sh
```

### Option 2: Auto-patching (Arch/CachyOS only)

The included pacman hook automatically re-patches after kernel updates:

```bash
sudo mkdir -p /etc/pacman.d/hooks
sudo cp 99-patch-btusb-csr8510.hook /etc/pacman.d/hooks/
```

### Option 3: Manual re-patch

```bash
sudo /usr/local/bin/patch-btusb-csr8510.sh
```

Or follow the [Manual Install](#manual-install-without-the-script) steps again.

### How to tell if you need to re-patch

Run the diagnostics:

```bash
bash diagnostics.sh
```

Or check the module size — patched is ~320KB, original is ~38KB:

```bash
ls -la /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.*
```

---

## Files

| File | Purpose |
|------|---------|
| `install.sh` | One-command installer — auto-detects distro, compiler, linker, module format |
| `patch-btusb-csr8510.sh` | Re-patch script — run after kernel updates |
| `99-patch-btusb-csr8510.hook` | Pacman hook — auto-triggers on Arch-based distros after kernel upgrades |
| `diagnostics.sh` | Check if your device is affected and if the patch is applied |
| `uninstall.sh` | Clean removal — restores original module |
| `patches/01-device-table.patch` | Reference: device table change |
| `patches/02-interrupt-size.patch` | Reference: interrupt transfer size fix |
| `patches/03-setup-routing.patch` | Reference: setup routing to btusb_setup_csr() |

---

## Uninstall

```bash
sudo bash uninstall.sh
```

This restores the original `btusb` module from backup and removes the patch script and pacman hook.

If no backup exists (e.g. you deleted it or swapped kernels), reinstall your kernel package:
```bash
# Debian/Ubuntu
sudo apt install --reinstall linux-image-$(uname -r)

# Fedora
sudo dnf reinstall kernel-core

# Arch
sudo pacman -S linux

# openSUSE
sudo zypper install --force kernel-default
```

---

## Troubleshooting

### Compilation fails with "unrecognised emulation mode: llvm"

Your kernel was built with GNU ld, but the installer tried to use LLD. This is handled automatically in the distro-agnostic version.

If manually compiling, use the correct linker:
```bash
# For kernels built with LLD (CachyOS, some Arch):
make CC=clang LD=ld.lld

# For kernels built with GNU ld (Ubuntu, Debian, Fedora):
make CC=gcc
```

### "expected expression" or "undeclared function 't'" errors

This is caused by broken sed-based patching (old versions of this fix). The current version uses Python — these errors should not appear. Make sure you're using the latest files.

### "No default controller available" after install

```bash
# Check module loaded
lsmod | grep btusb

# Check dmesg for errors
sudo dmesg | grep -iE 'hci0|btusb|csr' | tail -20

# Reload module
sudo modprobe -r btusb && sudo modprobe btusb

# Unplug and replug dongle
bluetoothctl show
```

### Dongle works on one USB port but not another

The patch is in the kernel module itself — it applies to all USB ports. If a port doesn't work, it's likely a power delivery issue with that port (cheap dongles are picky). Try a USB 2.0 port on the back of the PC.

---

## How It Works (Short Version)

1. USB subsystem detects `10d7:b012`
2. Kernel matches against btusb's device table
3. **Without patch**: driver_info = `BTUSB_ACTIONS_SEMI` → wrong init path → firmware never uploaded → HCI times out
4. **With patch**: driver_info = `BTUSB_CSR` → `btusb_setup_csr()` called → firmware uploaded → broken commands detected → suspend/resume workaround → dongle works

### Affected USB IDs

| VID:PID | Product | Notes |
|---------|---------|-------|
| `10d7:b012` | CSR8510 A10 | Most common clone — targeted by this fix |
| `0a12:0001` | Cambridge Silicon Radio | Original CSR — already supported by kernel |

---

## License

GPL-2.0 (same as the Linux kernel)
