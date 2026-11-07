#!/bin/bash -e

install -d -m 755 "${ROOTFS_DIR}/boot/firmware"
install -m 644 files/config.txt "${ROOTFS_DIR}/boot/firmware/config.txt"
