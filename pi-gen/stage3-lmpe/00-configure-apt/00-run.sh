#!/bin/bash -e

install -d -m 755 "${ROOTFS_DIR}/usr/share/keyrings"
install -m 644 files/lmde-arm64.gpg "${ROOTFS_DIR}/usr/share/keyrings/lmde-arm64.gpg"
install -m 644 files/linuxmint-keyring.gpg "${ROOTFS_DIR}/usr/share/keyrings/linuxmint-keyring.gpg"

install -m 644 files/lmde.list "${ROOTFS_DIR}/etc/apt/sources.list.d/lmde.list"
install -m 644 files/lmde-pi5.pref "${ROOTFS_DIR}/etc/apt/preferences.d/lmde-pi5.pref"

install -d -m 755 "${ROOTFS_DIR}/etc/apt/apt.conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/apt/apt.conf.d/99-lmpe.conf"
// LMPE APT Download, Network & Cache Tuning
Acquire::Queue-Mode "host";
Acquire::http::Pipeline-Depth "5";
Acquire::Retries "3";
APT::Keep-Downloaded-Packages "false";
Binary::apt::APT::Keep-Downloaded-Packages "false";
EOF

on_chroot <<- \EOF
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y linuxmint-keyring || true
	apt-get dist-upgrade -y
EOF
