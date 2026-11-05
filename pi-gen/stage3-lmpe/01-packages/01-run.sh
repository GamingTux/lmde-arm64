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

[org.cinnamon.muffin]
unredirect-fullscreen-windows=true

[org.cinnamon]
window-effect-speed=2
EOF
rm -f "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/99-lmpe*.override"

# 3. CPU-Governor auf schedutil setzen
install -d -m 755 "${ROOTFS_DIR}/etc/udev/rules.d"
echo 'KERNEL=="cpu*", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="schedutil"' > "${ROOTFS_DIR}/etc/udev/rules.d/60-ondemand-governor.rules"
rm -f "${ROOTFS_DIR}/etc/udev/rules.d/60-readahead.rules"

# 4. Kernel-VM, Btrfs-Cache & TCP BBR Tuning
install -d -m 755 "${ROOTFS_DIR}/etc/modules-load.d"
echo "tcp_bbr" > "${ROOTFS_DIR}/etc/modules-load.d/bbr.conf"
echo "i2c-dev" > "${ROOTFS_DIR}/etc/modules-load.d/i2c-dev.conf"

install -d -m 755 "${ROOTFS_DIR}/etc/sysctl.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/sysctl.d/99-lmpe-pi5.conf"
vm.swappiness = 100
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

# 5. Standard-Webbrowser auf Firefox setzen & Hardware-WebRender / Zero-Copy DMABUF für Pi 5 aktivieren
on_chroot << 'EOF'
update-alternatives --set x-www-browser /usr/bin/firefox || true
update-alternatives --set gnome-www-browser /usr/bin/firefox || true
EOF

install -d -m 755 "${ROOTFS_DIR}/etc/firefox/policies"
cat << 'EOF' > "${ROOTFS_DIR}/etc/firefox/policies/policies.json"
{
  "policies": {
    "EncryptedMediaExtensions": {
      "Enabled": true,
      "Locked": false
    },
    "Preferences": {
      "gfx.webrender.all": {
        "Value": true,
        "Status": "default"
      },
      "gfx.canvas.accelerated": {
        "Value": true,
        "Status": "default"
      },
      "layers.gpu-process.enabled": {
        "Value": true,
        "Status": "default"
      },
      "widget.dmabuf.force-enabled": {
        "Value": true,
        "Status": "default"
      },
      "media.ffmpeg.vaapi.enabled": {
        "Value": false,
        "Status": "default"
      },
      "media.rdd-process.enabled": {
        "Value": true,
        "Status": "default"
      },
      "media.av1.enabled": {
        "Value": true,
        "Status": "default"
      },
      "media.eme.enabled": {
        "Value": true,
        "Status": "default"
      },
      "media.gmp-widevinecdm.enabled": {
        "Value": true,
        "Status": "default"
      },
      "media.gmp-widevinecdm.visible": {
        "Value": true,
        "Status": "default"
      },
      "media.gmp-widevinecdm.version": {
        "Value": "latest",
        "Status": "default"
      },
      "media.gmp-widevinecdm.autoupdate": {
        "Value": false,
        "Status": "default"
      }
    }
  }
}
EOF

install -d -m 755 "${ROOTFS_DIR}/etc/chromium.d"
echo 'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --enable-remote-extensions"' > "${ROOTFS_DIR}/etc/chromium.d/00-rpi-vars"
cat << 'EOF' > "${ROOTFS_DIR}/etc/chromium.d/99-lmpe-pi5"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --ozone-platform-hint=auto --enable-gpu-rasterization --enable-oop-rasterization --enable-zero-copy --ignore-gpu-blocklist --num-raster-threads=4 --enable-features=CanvasOopRasterization,BackForwardCache,ParallelDownloading"
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

# 9. Lokaler DNS-Cache via systemd-resolved (nutzt Router/DHCP-DNS + schnelle Fallbacks)
install -d -m 755 "${ROOTFS_DIR}/etc/systemd/resolved.conf.d"
rm -f "${ROOTFS_DIR}/etc/systemd/resolved.conf.d/adguard-dns.conf"
cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/resolved.conf.d/99-lmpe-dns.conf"
[Resolve]
FallbackDNS=1.1.1.1 9.9.9.9 2606:4700:4700::1111 2620:fe::fe
Cache=yes
DNSStubListener=yes
EOF
rm -f "${ROOTFS_DIR}/etc/resolv.conf"
cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"

# 10. Offizielles LMPE Artwork-, Bootscreen- & Theme-Paket sowie universelles rpi-suspend installieren
install -d -m 755 "${ROOTFS_DIR}/tmp/lmpe-theme"
cp files/debs/lmpe-theme_*.deb files/debs/rpi-suspend_*.deb "${ROOTFS_DIR}/tmp/lmpe-theme/"
on_chroot <<- \EOF
	dpkg -i --force-confnew /tmp/lmpe-theme/*.deb || apt-get install -fy
	rm -rf /tmp/lmpe-theme
EOF

# 13. Argon ONE UP Hardware-Pakete für First-Boot Staging bereitstellen (Installation nur bei Auswahl)
install -d -m 755 "${ROOTFS_DIR}/usr/share/argon-debs"
for deb in files/debs/argon-oneup-*.deb files/debs/rpi-vc4-edp*.deb files/debs/cm5-mmc-fix*.deb; do
	[ -f "$deb" ] && cp "$deb" "${ROOTFS_DIR}/usr/share/argon-debs/"
done

on_chroot <<- \EOF
	plymouth-set-default-theme lmpe || true
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
	glib-compile-schemas /usr/share/glib-2.0/schemas || true
	apt-get remove -y xserver-xorg-video-fbdev || true
	# 14. Boot-Optimierungen: Dynamic ZRAM (kein /var/swap Verschleiß, lzo-rle Low-Latency), EEPROM-OneShot & unblocktes Backlight
	install -d -m 755 /etc/rpi /etc/systemd
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

	cat <<- 'ZRAMCONF' > /etc/systemd/zram-generator.conf
	[zram0]
	compression-algorithm = lzo-rle
	ZRAMCONF
	rm -f /var/swap

	install -d -m 755 /etc/systemd/system.conf.d /etc/systemd/user.conf.d /etc/systemd/system/user@.service.d /etc/pipewire/pipewire.conf.d /etc/apt/apt.conf.d
	cat <<- 'SYSCONF' > /etc/systemd/system.conf.d/99-lmpe-timeout.conf
	[Manager]
	DefaultTimeoutStopSec=15s
	SYSCONF

	cat <<- 'USERCONF' > /etc/systemd/user.conf.d/99-lmpe-timeout.conf
	[Manager]
	DefaultTimeoutStopSec=10s
	USERCONF

	cat <<- 'USERSVCCONF' > /etc/systemd/system/user@.service.d/timeout.conf
	[Service]
	TimeoutStopSec=10s
	USERSVCCONF

	rm -f /etc/pipewire/pipewire.conf.d/99-low-latency.conf /etc/apt/apt.conf.d/99-lmpe-speed.conf

	# 16. Desktop Environment Variables (/etc/environment)
	if ! grep -q "QT_QPA_PLATFORM" /etc/environment 2>/dev/null; then
		echo 'QT_QPA_PLATFORM="wayland;xcb"' >> /etc/environment
	fi
	if ! grep -q "MOZ_X11_EGL" /etc/environment 2>/dev/null; then
		echo 'MOZ_X11_EGL=1' >> /etc/environment
	fi

	# 17. PolicyKit-Regeln für Update Manager (AptKit & PackageKit)
	install -d -m 755 /etc/polkit-1/rules.d
	cat <<- 'POLKITCONF' > /etc/polkit-1/rules.d/60-aptkit.rules
	// LMPE PolicyKit rules for AptKit & PackageKit updates
	polkit.addRule(function(action, subject) {
	    if ((action.id.indexOf("org.aptkit.") === 0 ||
	         action.id.indexOf("org.freedesktop.packagekit.") === 0) &&
	        (subject.isInGroup("sudo") || subject.isInGroup("admin"))) {
	            return polkit.Result.YES;
	    }
	});
	POLKITCONF
	chmod 644 /etc/polkit-1/rules.d/60-aptkit.rules

	# 18. LMDE-Kompatibilitätsmarker für mintupdate
	install -d -m 755 /usr/share/doc/debian-system-adjustments
	cat <<- 'LMDEDOC' > /usr/share/doc/debian-system-adjustments/copyright
	Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
	Upstream-Name: debian-system-adjustments
	Source: https://github.com/linuxmint/debian-system-adjustments

	Files: *
	Copyright: 2024 Linux Mint <root@linuxmint.com>
	License: GPL-2+
	LMDEDOC

	# 19. Vorab-Generierung europäischer Standard-Locales (inkl. debconf-Sicherung gegen Überschreiben bei Upgrades)
	echo "locales locales/locales_to_be_generated multiselect de_DE.UTF-8 UTF-8, de_AT.UTF-8 UTF-8, de_CH.UTF-8 UTF-8, en_US.UTF-8 UTF-8, en_GB.UTF-8 UTF-8, fr_FR.UTF-8 UTF-8, fr_BE.UTF-8 UTF-8, fr_CH.UTF-8 UTF-8, es_ES.UTF-8 UTF-8, it_IT.UTF-8 UTF-8, nl_NL.UTF-8 UTF-8, nl_BE.UTF-8 UTF-8, pl_PL.UTF-8 UTF-8, pt_PT.UTF-8 UTF-8, pt_BR.UTF-8 UTF-8" | debconf-set-selections 2>/dev/null || true
	cat <<- 'LOCALECONF' > /etc/locale.gen
	de_DE.UTF-8 UTF-8
	de_AT.UTF-8 UTF-8
	de_CH.UTF-8 UTF-8
	en_US.UTF-8 UTF-8
	en_GB.UTF-8 UTF-8
	fr_FR.UTF-8 UTF-8
	fr_BE.UTF-8 UTF-8
	fr_CH.UTF-8 UTF-8
	es_ES.UTF-8 UTF-8
	it_IT.UTF-8 UTF-8
	nl_NL.UTF-8 UTF-8
	nl_BE.UTF-8 UTF-8
	pl_PL.UTF-8 UTF-8
	pt_PT.UTF-8 UTF-8
	pt_BR.UTF-8 UTF-8
	LOCALECONF
	locale-gen || true

	# 20. Absicherung checkAPT.py gegen NoneType-Crash bei unbekannten/ungenerierten Locales
	if [ -f /usr/lib/linuxmint/mintUpdate/checkAPT.py ]; then
		python3 -c '
path = "/usr/lib/linuxmint/mintUpdate/checkAPT.py"
with open(path, "r") as f:
    c = f.read()
target = """    def apply_l10n_descriptions(self):
        lang, encoding = locale.getlocale()
        if "_" in lang:
            lang = lang.split("_")[0]
        if lang in [None, "C", "en"]:
            return"""
replacement = """    def apply_l10n_descriptions(self):
        try:
            lang, encoding = locale.getlocale()
            if not lang or lang in ["C", "en"]:
                return
            if "_" in lang:
                lang = lang.split("_")[0]
        except Exception:
            return"""
if target in c:
    c = c.replace(target, replacement, 1)
    with open(path, "w") as f:
        f.write(c)
' 2>/dev/null || true
	fi

	# 21. Initialer updates.json Seed für mintupdate (mit gültigem Datum zur Vermeidung von strptime-Tracebacks)
	install -d -m 755 /etc/skel/.linuxmint/mintupdate
	echo '{"version": 1, "updates": {}, "checked": "1970.01.01", "notified": "1970.01.01"}' > /etc/skel/.linuxmint/mintupdate/updates.json

	# 10. Boot-Parallelisierung: systemd-user-sessions von network.target entkoppeln
	cat << 'EOF_SESS' > /etc/systemd/system/systemd-user-sessions.service
[Unit]
Description=Permit User Sessions
Documentation=man:systemd-user-sessions.service(8)
After=remote-fs.target nss-user-lookup.target home.mount

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/lib/systemd/systemd-user-sessions start
ExecStop=/usr/lib/systemd/systemd-user-sessions stop
EOF_SESS

	# 22. Systemd First-Boot Preset-Schutz (verhindert Reaktivierung deaktivierter Dienste bei machine-id=uninitialized)
	install -d -m 755 /etc/systemd/system-preset
	cat << 'EOF_PRESET' > /etc/systemd/system-preset/00-lmpe.preset
disable ssh.service
disable ssh.socket
disable rpi-resize.service
disable systemd-firstboot.service
disable lm-sensors.service
disable glamor-test.service
disable rp1-test.service
disable e2scrub_reap.service
disable e2scrub_all.timer
disable nfs-blkmap.service
disable rpc-statd-notify.service
disable apt-listchanges.timer
EOF_PRESET

	systemctl enable lightdm sshswitch.service rpi-eeprom-update.service ModemManager.service blueman-mechanism.service systemd-resolved.service fstrim.timer bluetooth.service earlyoom.service packagekit.service || true
	systemctl disable ssh.service ssh.socket lm-sensors.service glamor-test.service rp1-test.service e2scrub_reap.service e2scrub_all.timer nfs-blkmap.service rpc-statd-notify.service 2>/dev/null || true
	systemctl mask NetworkManager-wait-online.service systemd-networkd-wait-online.service rpi-resize.service systemd-firstboot.service 2>/dev/null || true
	systemctl set-default graphical.target
EOF
