# CSR8510 A10 Bluetooth Dongle Patch – Linux (CachyOS)

**TL;DR** – Cheap CSR8510 A10 Bluetooth 4.0 USB dongles (`USB ID 10d7:b012`) show *"No default controller available"* on Linux. This repository contains a kernel‑module patch, an installer script, and a pacman hook that make the dongle work on **CachyOS 7.0.11‑1‑cachyos** (and any Arch‑based distro). The patch survives kernel updates automatically.

---

## 📦 What This Project Does

| Item | Description |
|------|-------------|
| **Kernel patch** | Fixes the device table, interrupt size, and routes initialization through `btusb_setup_csr()` so the dongle receives its firmware. |
| **Installer (`install.sh`)** | Downloads the matching `btusb.c` source, applies the three patches, builds the module with `clang`, backs up the original module, installs the patched one, and registers a pacman hook. |
| **Pacman hook** (`/etc/pacman.d/hooks/99-patch-btusb-csr8510.hook`) | Re‑runs the installer after any kernel or header upgrade, guaranteeing the patch stays applied. |
| **Utility scripts** | `patch-btusb-csr8510.sh` – manual rebuild; `diagnostics.sh` – quick health‑check; `uninstall.sh` – clean removal. |
| **Documentation** | This README, `QUICKSTART.md`, and `UNINSTALL.md`. |

---

## 📋 System Information (auto‑filled)
* **OS:** CachyOS (Arch‑based) 
* **Kernel:** `7.0.11-1-cachyos` (`uname -r`) 
* **Architecture:** x86_64 

---

## 🚀 Quick Install (for strangers)
You only need **one** of the following methods. All of them automatically fetch the latest patch archive from this GitHub repo, so the repository can be cloned anywhere.

### Option A – Direct download (no Git needed)
```bash
curl -L https://github.com/ShadowWalkerM/CSR8510-A10-bluetooth_adapter_fix-Linux/archive/refs/heads/main.tar.gz \
  | tar xz && cd CSR8510-A10-bluetooth_adapter_fix-Linux-main && sudo bash install.sh
```
*The script will download the required kernel source, apply the patches, build the module and install the pacman hook.*

### Option B – Clone the repo (recommended if you want to inspect the code)
```bash
git clone https://github.com/ShadowWalkerM/CSR8510-A10-bluetooth_adapter_fix-Linux.git
cd CSR8510-A10-bluetooth_adapter_fix-Linux
sudo bash install.sh
```
If you prefer SSH (and have a GitHub key configured), you can clone with:
```bash
git clone git@github.com:ShadowWalkerM/CSR8510-A10-bluetooth_adapter_fix-Linux.git
```
*The installer works the same way regardless of how the repo was obtained.*

### What the installer does
1. Checks for required packages (`clang`, `zstd`, `linux-cachyos-headers`, `sudo`).
2. Determines the running kernel version (`uname -r`).
3. Downloads the matching `btusb.c` source from the official Linux kernel GitHub repository.
4. Applies the three patch files located in `patches/`.
5. Compiles the patched `btusb.ko.zst` with the system compiler.
6. Backs up the original module (`btusb.ko.zst.bak`).
7. Installs the new module and registers the pacman hook.
8. Prints a short success message.

After the installer finishes, **reboot** once, then verify:
```bash
bluetoothctl show          # should list a controller (hci0)
lsmod | grep btusb        # module must be loaded
```
If you see a controller, the patch works.

---

## 📦 What Gets Installed (file list)
| Path | Purpose |
|------|---------|
| `/usr/local/bin/patch-btusb-csr8510.sh` | Rebuild the patched `btusb` module on demand. |
| `/etc/pacman.d/hooks/99-patch-btusb-csr8510.hook` | Auto‑run the rebuild after kernel/header upgrades. |
| `/lib/modules/<kernel>/kernel/drivers/bluetooth/btusb.ko.zst.bak` | Backup of the original (unpatched) module. |
| `/usr/local/bin/uninstall.sh` | Helper script that removes the patch and restores the backup. |
| `diagnostics.sh` | Quick health‑check for the dongle. |
| `QUICKSTART.md` | One‑page cheat sheet for newcomers. |
| `UNINSTALL.md` | Detailed uninstall instructions (also included in this README). |

---

## 🛠️ How It Works (short version)
1. **Device matching** – The kernel’s `btusb.c` table incorrectly marked the clone as `BTUSB_ACTIONS_SEMI`. The patch replaces the entry with `BTUSB_CSR`.  
2. **Interrupt size fix** – The clone uses a different endpoint packet size; the patch reads the real `wMaxPacketSize`.  
3. **CSR setup routing** – The driver now calls `btusb_setup_csr()`, which uploads the internal firmware and applies work‑arounds for broken commands.  
Result: the dongle enumerates as a proper Bluetooth controller (`hci0`) and works with the standard BlueZ stack.

---

## 📚 Requirements
* **CachyOS / Arch Linux** (pacman) 
* `clang` – must match the compiler used to build your kernel 
* `zstd` – for compressed kernel modules 
* `linux-cachyos-headers` (or equivalent) 
* `sudo` privileges 
* Internet connection (to fetch the kernel source) 

---

## 🔧 Uninstall (clean removal)
```bash
# Run the built‑in uninstall helper
sudo /usr/local/bin/uninstall.sh
```
Or manually:
```bash
sudo rm /usr/local/bin/patch-btusb-csr8510.sh
sudo rm /etc/pacman.d/hooks/99-patch-btusb-csr8510.hook
sudo cp /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst.bak \
        /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst
sudo reboot
```
After reboot the original (unpatched) driver will be restored and the pacman hook will no longer run.

---

## 🐞 Troubleshooting
| Symptom | Check | Fix |
|---------|-------|-----|
| "No default controller available" after install | `lsmod | grep btusb` (module loaded?) | `sudo rmmod btusb && sudo modprobe btusb` |
| Module appears unpatched | `zstd -d /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst -c \| strings \| grep 'Fake CSR clone'` | Re‑run `sudo patch-btusb-csr8510.sh` |
| Compilation fails | `clang --version` (must be installed) | `sudo pacman -S clang` |
| Header mismatch | `pacman -Q linux-cachyos-headers` & `uname -r` | Install matching headers: `sudo pacman -S linux-cachyos-headers` |
| Dongle still not functional | `sudo dmesg | tail -30` and then `bluetoothctl show` | Replug the dongle, reload module (`sudo rmmod btusb && sudo modprobe btusb`). |

Logs from the installer and hook are stored at `/var/log/patch-btusb-csr8510.log`.

---

## 📂 Repository Layout
```
CSR8510-A10-bluetooth_adapter_fix-Linux/
├─ install.sh                # installer invoked by users
├─ patch-btusb-csr8510.sh   # rebuild script (used by hook)
├─ uninstall.sh              # clean‑up helper
├─ diagnostics.sh            # quick health check
├─ QUICKSTART.md
├─ UNINSTALL.md
├─ README.md                 # (this file)
└─ patches/
   ├─ 01‑add‑csr‑device‑table.patch
   ├─ 02‑fix‑interrupt‑size.patch
   └─ 03‑route‑to‑btusb_setup_csr.patch
```

---

All files in this repository are required for the patch to build, install, and stay functional across kernel upgrades.

---

*Documentation was prepared with the assistance of an AI language model.*