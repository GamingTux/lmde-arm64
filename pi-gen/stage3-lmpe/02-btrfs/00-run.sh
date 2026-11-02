#!/bin/bash -e

# 1. /etc/fstab auf Btrfs-Root (ohne separates Home, ohne Snapshots) mit Hochleistungs-Optionen + /tmp im RAM setzen
cat << 'EOF' > "${ROOTFS_DIR}/etc/fstab"
proc            /proc           proc    defaults          0       0
BOOTDEV  /boot/firmware  vfat    defaults,noatime,x-systemd.automount,nofail  0  0
ROOTDEV  /               btrfs   defaults,compress=zstd:2,noatime,nodiratime,commit=60,ssd,discard=async 0 0
tmpfs           /tmp            tmpfs   defaults,noatime,nosuid,nodev,mode=1777 0 0
EOF

# 2. Kernel-Kommandozeile (/boot/firmware/cmdline.txt) auf rootfstype=btrfs & Plymouth Boot-Splash umstellen
if [ -f "${ROOTFS_DIR}/boot/firmware/cmdline.txt" ]; then
	sed -i 's/rootfstype=ext4/rootfstype=btrfs rootflags=compress=zstd:2,noatime,nodiratime,commit=60,ssd,discard=async/g' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
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
cat << 'EOF' > "${ROOTFS_DIR}/usr/local/sbin/lmpe-btrfs-resize.sh"
#!/bin/bash
set -e
ROOT_PART="$(findmnt -n -o SOURCE /)"
ROOT_PART="${ROOT_PART%%\[*}"
if [[ "$ROOT_PART" =~ ^/dev/(mmcblk[0-9]+|nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
	DISK="${BASH_REMATCH[1]}"
	PART="${BASH_REMATCH[2]}"
	printf 'Yes\n100%%\n' | parted ---pretend-input-tty "/dev/${DISK}" resizepart "${PART}" || true
	partx -u "/dev/${DISK}" 2>/dev/null || partprobe "/dev/${DISK}" 2>/dev/null || true
elif [[ "$ROOT_PART" =~ ^/dev/(sd[a-z]+)([0-9]+)$ ]]; then
	DISK="${BASH_REMATCH[1]}"
	PART="${BASH_REMATCH[2]}"
	printf 'Yes\n100%%\n' | parted ---pretend-input-tty "/dev/${DISK}" resizepart "${PART}" || true
	partx -u "/dev/${DISK}" 2>/dev/null || partprobe "/dev/${DISK}" 2>/dev/null || true
fi
btrfs filesystem resize max / || true
systemctl disable lmpe-btrfs-resize.service || true
EOF
chmod 755 "${ROOTFS_DIR}/usr/local/sbin/lmpe-btrfs-resize.sh"

cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/system/lmpe-btrfs-resize.service"
[Unit]
Description=Resize Btrfs root filesystem on first boot
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lmpe-btrfs-resize.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

on_chroot <<- \EOF
	systemctl disable rpi-resize.service 2>/dev/null || true
	systemctl enable lmpe-btrfs-resize.service
EOF
