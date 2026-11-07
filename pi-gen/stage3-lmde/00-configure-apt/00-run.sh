#!/bin/bash -e

install -d -m 755 "${ROOTFS_DIR}/usr/share/keyrings"
install -m 644 files/lmde-arm64.gpg "${ROOTFS_DIR}/usr/share/keyrings/lmde-arm64.gpg"
install -m 644 files/linuxmint-keyring.gpg "${ROOTFS_DIR}/usr/share/keyrings/linuxmint-keyring.gpg"

install -m 644 files/lmde.list "${ROOTFS_DIR}/etc/apt/sources.list.d/lmde.list"
install -m 644 files/lmde-pi5.pref "${ROOTFS_DIR}/etc/apt/preferences.d/lmde-pi5.pref"

on_chroot <<- \EOF
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y linuxmint-keyring || true
	apt-get dist-upgrade -y --allow-downgrades
EOF
