#!/bin/bash -e

install -d -m 755 "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/90-slick-greeter.conf"
[Seat:*]
greeter-session=slick-greeter
user-session=cinnamon
greeter-hide-users=false
EOF

install -d -m 755 "${ROOTFS_DIR}/etc/X11/xorg.conf.d" "${ROOTFS_DIR}/usr/share/X11/xorg.conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/xorg.conf.d/99-v3d.conf"
Section "OutputClass"
  Identifier "vc4"
  MatchDriver "vc4"
  Driver "modesetting"
  Option "PrimaryGPU" "true"
EndSection
EOF
cp "${ROOTFS_DIR}/etc/X11/xorg.conf.d/99-v3d.conf" "${ROOTFS_DIR}/usr/share/X11/xorg.conf.d/99-v3d.conf"

cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/xorg.conf.d/40-libinput-touchpad.conf"
Section "InputClass"
  Identifier "libinput touchpad catchall"
  MatchIsTouchpad "on"
  MatchDevicePath "/dev/input/event*"
  Driver "libinput"
  Option "Tapping" "on"
  Option "ClickMethod" "clickfinger"
EndSection
EOF

install -d -m 755 "${ROOTFS_DIR}/usr/share/glib-2.0/schemas"
cat << 'EOF' > "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/99-lmpe-touchpad.gschema.override"
[org.cinnamon.desktop.peripherals.touchpad]
tap-to-click=true
click-method='fingers'

[org.gnome.desktop.peripherals.touchpad]
tap-to-click=true
click-method='fingers'
EOF

# 3. CPU-Governor auf schedutil setzen
install -d -m 755 "${ROOTFS_DIR}/etc/udev/rules.d"
echo 'KERNEL=="cpu*", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="schedutil"' > "${ROOTFS_DIR}/etc/udev/rules.d/60-ondemand-governor.rules"

# 4. Kernel-VM & Btrfs-Cache-Tuning
install -d -m 755 "${ROOTFS_DIR}/etc/sysctl.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/sysctl.d/99-lmpe-pi5.conf"
vm.swappiness = 100
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF

# 5. Chromium Flags (Xorg & Wayland kompatibel via --ozone-platform-hint=auto)
install -d -m 755 "${ROOTFS_DIR}/etc/chromium.d"
echo 'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --enable-remote-extensions"' > "${ROOTFS_DIR}/etc/chromium.d/00-rpi-vars"
cat << 'EOF' > "${ROOTFS_DIR}/etc/chromium.d/99-lmpe-pi5"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --ozone-platform-hint=auto --enable-gpu-rasterization --enable-oop-rasterization --enable-zero-copy --ignore-gpu-blocklist"
EOF

# 6. WLAN-Powersave deaktivieren
install -d -m 755 "${ROOTFS_DIR}/etc/NetworkManager/conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/NetworkManager/conf.d/99-lmpe-wifi-powersave-off.conf"
[connection]
wifi.powersave = 2
EOF

on_chroot <<- \EOF
	glib-compile-schemas /usr/share/glib-2.0/schemas || true
	apt-get remove -y xserver-xorg-video-fbdev || true
	systemctl enable glamor-test.service rp1-test.service lightdm || true
	systemctl set-default graphical.target
EOF
