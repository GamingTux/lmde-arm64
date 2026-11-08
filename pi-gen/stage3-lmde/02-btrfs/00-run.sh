#!/bin/bash -e

# 1. /etc/fstab auf Btrfs-Root setzen
cat << 'EOF' > "${ROOTFS_DIR}/etc/fstab"
proc            /proc           proc    defaults          0       0
BOOTDEV  /boot/firmware  vfat    defaults,noatime,x-systemd.automount,nofail  0  0
ROOTDEV  /               btrfs   defaults,compress=zstd:1,noatime,commit=60 0 0
EOF

# 2. Kernel-Kommandozeile (/boot/firmware/cmdline.txt) auf rootfstype=btrfs & Plymouth Bootscreen (mint-logo) umstellen
if [ -f "${ROOTFS_DIR}/boot/firmware/cmdline.txt" ]; then
	sed -i 's/rootfstype=ext4/rootfstype=btrfs rootflags=compress=zstd:1,noatime,commit=60/g' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
	sed -i 's/fsck.repair=yes/fsck.repair=no/g' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
	sed -i 's/\bresize\b//g; s/[[:space:]]*$//' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
	if ! grep -q "splash" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"; then
		sed -i 's/$/ quiet splash plymouth.ignore-serial-consoles vt.global_cursor_default=0 loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
	fi
fi

# 3. Btrfs- & Zstd-Module fest in die initramfs aufnehmen
install -d -m 755 "${ROOTFS_DIR}/etc/initramfs-tools"
for mod in btrfs zstd_compress crc32c; do
	if ! grep -qx "$mod" "${ROOTFS_DIR}/etc/initramfs-tools/modules" 2>/dev/null; then
		echo "$mod" >> "${ROOTFS_DIR}/etc/initramfs-tools/modules"
	fi
done

# 4. First-Boot Online-Resize für Btrfs-Root-Dateisystem einrichten
cat << 'EOF' > "${ROOTFS_DIR}/usr/local/sbin/btrfs-root-resize.sh"
#!/bin/bash
set -e
ROOT_PART="$(findmnt -n -o SOURCE /)"
ROOT_PART="${ROOT_PART%%\[*}"
if [[ "$ROOT_PART" =~ ^/dev/(mmcblk[0-9]+|nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
	DISK="${BASH_REMATCH[1]}"
	PART="${BASH_REMATCH[2]}"
	if command -v growpart >/dev/null 2>&1; then
		growpart "/dev/${DISK}" "${PART}" 2>/dev/null || true
	else
		echo ", +" | sfdisk -N "${PART}" --no-reread "/dev/${DISK}" 2>/dev/null || true
	fi
	partx -u "${PART}" "/dev/${DISK}" 2>/dev/null || partprobe "/dev/${DISK}" 2>/dev/null || true
elif [[ "$ROOT_PART" =~ ^/dev/(sd[a-z]+)([0-9]+)$ ]]; then
	DISK="${BASH_REMATCH[1]}"
	PART="${BASH_REMATCH[2]}"
	if command -v growpart >/dev/null 2>&1; then
		growpart "/dev/${DISK}" "${PART}" 2>/dev/null || true
	else
		echo ", +" | sfdisk -N "${PART}" --no-reread "/dev/${DISK}" 2>/dev/null || true
	fi
	partx -u "${PART}" "/dev/${DISK}" 2>/dev/null || partprobe "/dev/${DISK}" 2>/dev/null || true
fi
btrfs filesystem resize max / || true
systemctl disable btrfs-root-resize.service || true
EOF
chmod 755 "${ROOTFS_DIR}/usr/local/sbin/btrfs-root-resize.sh"

cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/system/btrfs-root-resize.service"
[Unit]
Description=Resize Btrfs root filesystem on first boot
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
TimeoutStartSec=60
ExecStart=/usr/local/sbin/btrfs-root-resize.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

on_chroot <<- \EOF
	systemctl disable rpi-resize.service 2>/dev/null || true
	systemctl mask rpi-resize.service 2>/dev/null || true
	systemctl enable btrfs-root-resize.service
EOF
