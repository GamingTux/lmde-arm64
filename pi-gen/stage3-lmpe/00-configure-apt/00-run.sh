#!/bin/bash -e

install -d -m 755 "${ROOTFS_DIR}/usr/share/keyrings"
install -m 644 files/lmde-arm64.gpg "${ROOTFS_DIR}/usr/share/keyrings/lmde-arm64.gpg"
curl -fsSL "https://GamingTux.github.io/lmde-arm64/lmde-arm64.gpg" -o "${ROOTFS_DIR}/usr/share/keyrings/lmde-arm64.gpg" || true
chmod 644 "${ROOTFS_DIR}/usr/share/keyrings/lmde-arm64.gpg"

KEYRING_DEB="$(curl -fsSL http://packages.linuxmint.com/pool/main/l/linuxmint-keyring/ | grep -oE 'linuxmint-keyring_[^"]+\.deb' | sort -V | tail -n 1)"
curl -fsSL "http://packages.linuxmint.com/pool/main/l/linuxmint-keyring/${KEYRING_DEB}" -o "${ROOTFS_DIR}/tmp/${KEYRING_DEB}"
on_chroot <<- EOF
	dpkg -i "/tmp/${KEYRING_DEB}"
	rm -f "/tmp/${KEYRING_DEB}"
EOF

install -m 644 files/lmde.list "${ROOTFS_DIR}/etc/apt/sources.list.d/lmde.list"
install -m 644 files/lmde-pi5.pref "${ROOTFS_DIR}/etc/apt/preferences.d/lmde-pi5.pref"

on_chroot <<- \EOF
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get dist-upgrade -y
EOF
