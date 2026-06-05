# CSR8510 A10 Bluetooth Dongle Patch for Linux

**Fixes cheap CSR8510 A10 Bluetooth 4.0 USB dongles that work on Windows but fail on Linux.**

If you bought a cheap Bluetooth dongle and Linux shows "No default controller available" or the dongle just doesn't work at all — this fix is for you.

---

## Quick Install

```bash
# If you have rclone with Google Drive configured:
rclone copy gdrive100:csr8510-btusb-patch.tar.gz ~ && tar xzf ~/csr8510-btusb-patch.tar.gz -C ~ && sudo bash ~/csr8510-btusb-patch/install.sh

# Or download from GitHub and install:
curl -sL https://raw.githubusercontent.com/nosferatu/csr8510-btusb-patch/main/install.sh | sudo bash
```

That's it. After install, your Bluetooth dongle should work immediately. The patch also auto-reapplies after kernel updates.

---

## What This Fixes

### The Problem

Cheap CSR8510 A10 Bluetooth dongles (USB ID `10d7:b012`) are everywhere — Amazon, AliExpress, eBay. They work fine on Windows because the Windows driver includes firmware that gets uploaded to the dongle at startup.

On Linux, the `btusb` kernel module already knows about this USB ID but **classifies it wrong** — it marks the device as `BTUSB_ACTIONS_SEMI` (an Actions Semiconductor device) instead of `BTUSB_CSR` (a Cambridge Silicon Radio device). This means:

1. The CSR firmware upload path is never triggered
2. The dongle's controller has no firmware running
3. All HCI commands time out with error `-110`
4. `bluetoothctl show` says "No default controller available"

### The Fix

This patch modifies the `btusb` kernel module to:

1. **Add `10d7:b012` to the CSR device table** — so the kernel knows this is a CSR device that needs firmware upload
2. **Fix the interrupt transfer size** — fake CSR dongles use a different transfer size than real ones
3. **Route through `btusb_setup_csr()`** — this function detects the clone, applies workarounds for broken commands, and forces a suspend/resume cycle that makes the dongle's bulk RX endpoint work

### Technical Details

The `btusb` kernel module (`drivers/bluetooth/btusb.c`) has a device table that maps USB IDs to driver behavior flags. The kernel already has this entry:

```c
{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI },
```

This is wrong for the CSR8510 A10 clone. The device needs `BTUSB_CSR` so it goes through the CSR initialization path (`btusb_setup_csr()`), which:

- Reads the local version to detect if it's a fake CSR (checks manufacturer ID and version mismatch)
- Applies broken-command workarounds (these clones don't implement all HCI commands correctly)
- Forces a suspend/resume cycle to activate the bulk RX endpoint
- Sets proper quirks so the Bluetooth stack doesn't send unsupported commands

The patch also adds the device to two other places in the code:
- **Interrupt transfer size fix**: Fake CSR dongles need `wMaxPacketSize` from the endpoint descriptor instead of the fixed size used by real CSR devices
- **Setup function routing**: The `btusb_check_fake_csr()` function needs to know about this device ID to set `hdev->setup = btusb_setup_csr`

### Affected Devices

Any USB Bluetooth dongle with these IDs:
- `10d7:b012` — Most common, sold as "CSR8510 A10" but actually Actions Semiconductor or other clones
- `0a12:0001` — Original Cambridge Silicon Radio CSR8510 A10 (already supported, included for completeness)

Common product names:
- CSR8510 A10 Bluetooth 4.0 USB Dongle
- Generic "Bluetooth 4.0 Adapter" from AliExpress/Amazon/eBay
- Any cheap BT dongle that works on Windows but not Linux

### How to Check If You're Affected

```bash
# 1. Find your device ID
lsusb | grep -iE 'bluetooth|csr|cambridge'

# Look for: Bus XXX Device XXX: ID 10d7:b012  CSR8510 A10

# 2. Check if it's working
bluetoothctl show

# If you see "No default controller available", you need this patch

# 3. Check for timeout errors
sudo dmesg | grep -iE 'hci0.*timeout|hci0.*failed.*-110'
```

---

## What Gets Installed

| File | Purpose |
|------|---------|
| `/usr/local/bin/patch-btusb-csr8510.sh` | Patch/rebuild script — downloads btusb.c, applies patches, compiles, installs |
| `/etc/pacman.d/hooks/99-patch-btusb-csr8510.hook` | Pacman hook — auto-runs the patch after kernel updates |
| `/lib/modules/*/kernel/drivers/bluetooth/btusb.ko.zst.bak` | Backup of the original (unpatched) module |

### Auto-Update Behavior

The pacman hook triggers on `linux-cachyos` and `linux-cachyos-headers` package install/upgrade. When a new kernel is installed:

1. The hook runs `patch-btusb-csr8510.sh`
2. The script checks all installed kernel versions
3. For each kernel, if the module isn't already patched, it:
   - Downloads btusb.c from the matching Linux kernel tag on GitHub (falls back to local kernel source)
   - Applies the 3 patches
   - Compiles with `clang` (matching the kernel's build compiler)
   - Backs up the original module and installs the patched one
4. Logs to `/var/log/patch-btusb-csr8510.log`

---

## Requirements

- **Arch Linux** or **CachyOS** (pacman-based)
- `clang` — kernel compiler (must match what the kernel was built with)
- `zstd` — module compression
- Kernel headers — `linux-cachyos-headers` (or your distro's equivalent)
- Internet access — to download btusb.c from GitHub (or local kernel source as fallback)
- sudo access

---

## Uninstall

```bash
# Remove the patch script and hook
sudo rm /usr/local/bin/patch-btusb-csr8510.sh
sudo rm /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook

# Restore original module (for current kernel)
sudo cp /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst.bak \
        /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst

# Reboot to reload the unpatched module
sudo reboot
```

---

## Troubleshooting

### "No default controller available" after install
```bash
# Check if the module is patched
zstd -d /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst -c | strings | grep 'Fake CSR clone'

# Check dmesg for errors
sudo dmesg | grep -iE 'bluetooth|hci0' | tail -20

# Try reloading the module
sudo rmmod btusb && sudo modprobe btusb
sleep 3 && bluetoothctl show
```

### Compilation fails
```bash
# Make sure you have the right compiler
clang --version

# Make sure kernel headers match your running kernel
pacman -Q linux-cachyos-headers
uname -r

# Check the log
cat /var/log/patch-btusb-csr8510.log
```

### Dongle still doesn't work after patch
```bash
# Unplug and replug the dongle, then:
sudo dmesg | tail -30
bluetoothctl show
```

---

## How It Works (Full Explanation)

When you plug in a USB Bluetooth dongle, the Linux kernel:

1. Matches the USB ID against the `btusb` driver's device table
2. Loads the appropriate driver behavior flags
3. For CSR devices (`BTUSB_CSR`), calls `btusb_setup_csr()` during initialization
4. `btusb_setup_csr()` detects fake clones and applies workarounds
5. The dongle becomes usable

For the `10d7:b012` clone, step 2 was wrong — the kernel loaded `BTUSB_ACTIONS_SEMI` flags instead of `BTUSB_CSR`. This meant step 3 never happened, so the dongle's firmware was never uploaded and it never became usable.

This patch fixes step 2 by adding a correct entry with `BTUSB_CSR` flags, and also fixes two other places in the code that need to know about this specific device ID.

---

## Credits

- Original patch approach by [14-debug](https://github.com/14-debug/patch-btusb-csr8510-10d7-b012)
- Kernel btusb CSR detection logic by the Linux Bluetooth subsystem maintainers
- This package and documentation by OWL/nosferatu

## License

GPL-2.0 (same as the Linux kernel)
