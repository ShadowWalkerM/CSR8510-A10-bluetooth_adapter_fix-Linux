#!/usr/bin/env python3
"""
Apply CSR8510 A10 (10d7:b012) patches to btusb.c.

Usage: patch_btusb.py <path/to/btusb.c>
Applies 3 patches:
  1. Change BTUSB_ACTIONS_SEMI -> BTUSB_CSR in device table
  2. Add 10d7:b012 to interrupt transfer size check
  3. Add 10d7:b012 to setup function routing
"""

import re
import sys


def patch_btusb(path: str) -> bool:
    with open(path) as f:
        c = f.read()

    modified = False

    # Patch 1: Change BTUSB_ACTIONS_SEMI -> BTUSB_CSR
    old1 = '\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI },'
    new1 = '\t{ USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_CSR }, /* Fake CSR clone - CSR8510 A10 */'
    if old1 in c:
        c = c.replace(old1, new1, 1)
        modified = True
        print("  P1: ACTIONS_SEMI -> CSR")
    else:
        print("  P1: not found or already applied")

    # Patch 2: Add to interrupt transfer size check
    # Match: the block that checks 0a12:0001 for fake CSR interrupt size
    old2 = (
        '\tif (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n'
        '\t    le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001)\n'
        '\t\t/* Fake CSR devices'
    )
    new2 = (
        '\tif ((le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12 &&\n'
        '\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0x0001) ||\n'
        '\t    (le16_to_cpu(data->udev->descriptor.idVendor)  == 0x10d7 &&\n'
        '\t     le16_to_cpu(data->udev->descriptor.idProduct) == 0xb012))\n'
        '\t\t/* Fake CSR devices'
    )
    if old2 in c:
        c = c.replace(old2, new2, 1)
        modified = True
        print("  P2: interrupt size")
    else:
        print("  P2: not found or already applied")

    # Patch 3: Add to setup routing (btusb_check_fake_csr)
    old3 = (
        '\t\tif (le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n'
        '\t\t    le16_to_cpu(udev->descriptor.idProduct) == 0x0001)\n'
        '\t\t\thdev->setup = btusb_setup_csr;'
    )
    new3 = (
        '\t\tif ((le16_to_cpu(udev->descriptor.idVendor)  == 0x0a12 &&\n'
        '\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0x0001) ||\n'
        '\t\t    (le16_to_cpu(udev->descriptor.idVendor)  == 0x10d7 &&\n'
        '\t\t     le16_to_cpu(udev->descriptor.idProduct) == 0xb012))\n'
        '\t\t\thdev->setup = btusb_setup_csr;'
    )
    if old3 in c:
        c = c.replace(old3, new3, 1)
        modified = True
        print("  P3: setup routing")
    else:
        print("  P3: not found or already applied")

    if modified:
        with open(path, 'w') as f:
            f.write(c)
        print("  Patches written")
    else:
        print("  No changes made")

    return modified


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <btusb.c path>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    if not path.endswith('btusb.c'):
        print(f"Warning: expected btusb.c, got {path}", file=sys.stderr)

    patch_btusb(path)


if __name__ == '__main__':
    main()
