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
cat << 'EOF' > "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/zz-lmpe-touchpad.gschema.override"
[org.cinnamon.desktop.peripherals.touchpad]
tap-to-click=true
click-method='fingers'

[org.gnome.desktop.peripherals.touchpad]
tap-to-click=true
click-method='fingers'
EOF
rm -f "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/99-lmpe*.override"

# 3. CPU-Governor auf schedutil setzen
install -d -m 755 "${ROOTFS_DIR}/etc/udev/rules.d"
echo 'KERNEL=="cpu*", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="schedutil"' > "${ROOTFS_DIR}/etc/udev/rules.d/60-ondemand-governor.rules"

# 4. Kernel-VM, Btrfs-Cache & TCP BBR Tuning
install -d -m 755 "${ROOTFS_DIR}/etc/modules-load.d"
echo "tcp_bbr" > "${ROOTFS_DIR}/etc/modules-load.d/bbr.conf"

install -d -m 755 "${ROOTFS_DIR}/etc/sysctl.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/sysctl.d/99-lmpe-pi5.conf"
vm.swappiness = 180
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
fs.inotify.max_user_watches = 524288
net.core.default_qdisc = fq
net.core.rps_sock_flow_entries = 32768
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF

# 5. Standard-Webbrowser auf Firefox setzen, GPU-WebRender & Codec-Tuning konfigurieren
on_chroot << 'EOF'
update-alternatives --set x-www-browser /usr/bin/firefox || true
update-alternatives --set gnome-www-browser /usr/bin/firefox || true
EOF

install -d -m 755 "${ROOTFS_DIR}/etc/firefox" "${ROOTFS_DIR}/usr/lib/firefox/browser/defaults/preferences"
cat << 'EOF' > "${ROOTFS_DIR}/etc/firefox/99-lmpe-pi5.js"
// LMPE Raspberry Pi 5 GPU- & Codec-Optimierungen für Firefox
pref("gfx.webrender.all", true);
pref("layers.acceleration.force-enabled", true);
pref("media.ffmpeg.vaapi.enabled", false);
pref("widget.dmabuf.textures", false);
pref("media.ffvpx.enabled", true);
pref("media.rdd-ffmpeg.enabled", true);
pref("media.av1.enabled", true);
pref("media.mediasource.vp9.enabled", true);
pref("media.webm.enabled", true);
EOF
cp "${ROOTFS_DIR}/etc/firefox/99-lmpe-pi5.js" "${ROOTFS_DIR}/usr/lib/firefox/browser/defaults/preferences/99-lmpe-pi5.js" 2>/dev/null || true

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

cat << 'EOF' > "${ROOTFS_DIR}/usr/sbin/lmpe-runtime-tune"
#!/bin/sh
# Spread heavy ARM64 GICv2 Level IRQs across CPU0..CPU3
for irq_dir in /proc/irq/[0-9]*; do
    [ -d "$irq_dir" ] || continue
    aff_file="$irq_dir/smp_affinity_list"
    [ -w "$aff_file" ] || continue
    for action_dir in "$irq_dir"/*; do
        [ -d "$action_dir" ] || continue
        name=$(basename "$action_dir")
        case "$name" in
            *dwc2*) echo 1 > "$aff_file" 2>/dev/null || true; break ;;
            *v3d*) echo 2 > "$aff_file" 2>/dev/null || true; break ;;
            *vc4*|*hvs*|*mmc0*|*mmc1*) echo 3 > "$aff_file" 2>/dev/null || true; break ;;
            *rp1*|*xhci*) echo 0 > "$aff_file" 2>/dev/null || true; break ;;
        esac
    done
done

# Enable 4-Core Receive Packet Steering (RPS/RFS) on active network interfaces
for rx_dir in /sys/class/net/wlan*/queues/rx-0 /sys/class/net/eth*/queues/rx-0; do
    [ -d "$rx_dir" ] || continue
    echo f > "$rx_dir/rps_cpus" 2>/dev/null || true
    echo 4096 > "$rx_dir/rps_flow_cnt" 2>/dev/null || true
done
EOF
chmod 755 "${ROOTFS_DIR}/usr/sbin/lmpe-runtime-tune"

cat << 'EOF' > "${ROOTFS_DIR}/etc/udev/rules.d/90-lmpe-runtime.rules"
# Optimal I/O Scheduler, Read-Ahead & Core Queue Affinity for NVMe SSDs, eMMC/SD & USB storage
ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="512", ATTR{queue/rq_affinity}="2"
ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="mmcblk[0-9]*", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/read_ahead_kb}="256", ATTR{queue/rq_affinity}="2"
ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq", ATTR{queue/rq_affinity}="2"
ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/read_ahead_kb}="256", ATTR{queue/rq_affinity}="2"

# 4-Core Receive Packet Steering (RPS/RFS) on network interfaces
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*|eth*", ATTR{queues/rx-0/rps_cpus}="f", ATTR{queues/rx-0/rps_flow_cnt}="4096"

# Runtime IRQ tuning on DRM init
ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card0", RUN+="/usr/sbin/lmpe-runtime-tune"
EOF

# 7. Doppelte Audio-Session unter LightDM verhindern
for unit in pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service filter-chain.service; do
    install -d -m 755 "${ROOTFS_DIR}/etc/systemd/user/${unit}.d"
    cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/user/${unit}.d/nosystem.conf"
[Unit]
ConditionUser=!@system
EOF
done

# 8. Bluetooth beim Booten automatisch aktivieren
chmod 555 "${ROOTFS_DIR}/etc/bluetooth" 2>/dev/null || true
if grep -q "AutoEnable" "${ROOTFS_DIR}/etc/bluetooth/main.conf" 2>/dev/null; then
    sed -i "s/^#*AutoEnable.*/AutoEnable = true/" "${ROOTFS_DIR}/etc/bluetooth/main.conf"
elif [ -f "${ROOTFS_DIR}/etc/bluetooth/main.conf" ]; then
    sed -i "/\\[Policy\\]/a AutoEnable = true" "${ROOTFS_DIR}/etc/bluetooth/main.conf"
fi

# 9. Lokaler DNS-Cache via systemd-resolved
install -d -m 755 "${ROOTFS_DIR}/etc/systemd/resolved.conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/resolved.conf.d/adguard-dns.conf"
[Resolve]
DNS=94.140.14.14 94.140.15.15 2a10:50c0::ad1:ff 2a10:50c0::ad2:ff
FallbackDNS=94.140.14.14 94.140.15.15 2a10:50c0::ad1:ff 2a10:50c0::ad2:ff
Domains=~.
DNSOverTLS=opportunistic
Cache=yes
DNSStubListener=yes
MulticastDNS=no
EOF
rm -f "${ROOTFS_DIR}/etc/resolv.conf"
cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"

# 10. Offizielles LMPE Artwork-, Bootscreen- & Theme-Paket installieren
install -d -m 755 "${ROOTFS_DIR}/tmp/lmpe-theme"
cp files/debs/lmpe-theme_*.deb "${ROOTFS_DIR}/tmp/lmpe-theme/"
on_chroot <<- \EOF
	dpkg -i --force-confnew /tmp/lmpe-theme/lmpe-theme_*.deb || apt-get install -fy
	rm -rf /tmp/lmpe-theme
EOF

# 13. Argon ONE UP Hardware-Pakete für First-Boot Staging bereitstellen (Installation nur bei Auswahl)
install -d -m 755 "${ROOTFS_DIR}/usr/share/argon-debs"
cp files/debs/argon-oneup-*.deb "${ROOTFS_DIR}/usr/share/argon-debs/"

on_chroot <<- \EOF
	plymouth-set-default-theme lmpe || true
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
	glib-compile-schemas /usr/share/glib-2.0/schemas || true
	apt-get remove -y xserver-xorg-video-fbdev || true
	# 14. Boot-Optimierungen: Dynamic ZRAM (kein /var/swap Verschleiß), EEPROM-OneShot & unblocktes Backlight
	install -d -m 755 /etc/rpi
	cat <<- 'SWAPCONF' > /etc/rpi/swap.conf
	# LMPE Dynamic ZRAM Swap Configuration
	# Scales dynamically with physical RAM: Size = min(RAM * RamMultiplier, MaxSizeMiB)
	[Main]
	Mechanism=zram

	[Zram]
	RamMultiplier=1
	MaxSizeMiB=4096

	[File]
	MaxSizeMiB=0
	SWAPCONF
	rm -f /var/swap

	systemctl enable lightdm irqbalance.service systemd-resolved.service fstrim.timer bluetooth.service || true
	systemctl disable glamor-test.service rp1-test.service e2scrub_reap.service e2scrub_all.timer rpi-eeprom-update.service ModemManager.service nfs-blkmap.service rpc-statd-notify.service 2>/dev/null || true
	systemctl mask NetworkManager-wait-online.service systemd-networkd-wait-online.service rpcbind.service rpcbind.socket serial-getty@ttyAMA10.service 2>/dev/null || true
	systemctl set-default graphical.target
EOF
