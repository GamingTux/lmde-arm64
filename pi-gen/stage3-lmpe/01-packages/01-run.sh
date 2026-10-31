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

on_chroot <<- \EOF
	apt-get remove -y xserver-xorg-video-fbdev || true
	systemctl enable glamor-test.service rp1-test.service lightdm || true
	systemctl set-default graphical.target
EOF
