# Patch Files

These are **reference** patch files showing the three changes to `btusb.c`.

The actual install script applies these patches using **Python** (not a `patch` command) because the text-based sed approach had escaping issues with tabs (`\t`) across different kernel versions.

## Patch 1 — Device Table (`01-device-table.patch`)

Changes the driver_info flag for `10d7:b012` from `BTUSB_ACTIONS_SEMI` to `BTUSB_CSR`.

**Before:** `{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI },`
**After:** `{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR },`

This tells the kernel this is a CSR device, not Actions Semiconductor.

## Patch 2 — Interrupt Transfer Size (`02-interrupt-size.patch`)

Adds `10d7:b012` to the existing check for `0a12:0001` in the interrupt transfer size workaround.

Fake CSR clones have a different endpoint descriptor than real CSR devices. Without this fix, the driver uses the wrong buffer size and HCI events get truncated.

## Patch 3 — Setup Routing (`03-setup-routing.patch`)

Routes `10d7:b012` through `btusb_setup_csr()` by adding it to the existing check for `0a12:0001`.

`btusb_setup_csr()` is what makes these cheap dongles work:
1. Sends HCI command to read firmware version
2. Detects fake clones by checking manufacturer ID and version consistency
3. Applies broken-command workarounds (clones lie about features they support)
4. Forces a USB suspend/resume cycle to activate the bulk RX endpoint
5. Disables broken remote wakeup

Without this patch, the driver never calls `btusb_setup_csr()` for `10d7:b012`, so firmware never gets uploaded and the dongle times out.
