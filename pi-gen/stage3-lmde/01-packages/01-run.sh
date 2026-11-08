#!/bin/bash -e

# Remove any Xorg configuration files from base stages
rm -rf "${ROOTFS_DIR}/etc/X11/xorg.conf.d/99-v3d.conf" \
       "${ROOTFS_DIR}/usr/share/X11/xorg.conf.d/99-v3d.conf" \
       "${ROOTFS_DIR}/etc/X11/xorg.conf.d/40-libinput-touchpad.conf" \
       "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/90-slick-greeter.conf"

# 1. Pure Wayland LightDM Session Wrapper & Greeter Configuration (LMDE Mint-Y styled)
install -d -m 755 "${ROOTFS_DIR}/usr/sbin" \
                  "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d" \
                  "${ROOTFS_DIR}/etc/xdg/labwc-greeter" \
                  "${ROOTFS_DIR}/etc/xdg/autostart"

cat << 'EOF' > "${ROOTFS_DIR}/usr/sbin/lightdm-wayland-session"
#!/bin/bash
# Pure Wayland session wrapper for LightDM (replaces X11-only /etc/X11/Xsession)
for file in /etc/profile "$HOME/.profile"; do
    if [ -f "$file" ]; then
        . "$file"
    fi
done

export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
export GTK_MODULES="${GTK_MODULES:+$GTK_MODULES:}xapp-gtk3-module"
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export CLUTTER_BACKEND="wayland"
export SDL_VIDEODRIVER="wayland,x11"
export MOZ_ENABLE_WAYLAND="1"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-X-Cinnamon}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-cinnamon-wayland}"

if [ -z "$XDG_DATA_DIRS" ]; then
    export XDG_DATA_DIRS="/usr/share/gnome:/home/$USER/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
else
    case ":$XDG_DATA_DIRS:" in
        *:/var/lib/flatpak/exports/share:*) ;;
        *) export XDG_DATA_DIRS="/home/$USER/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:$XDG_DATA_DIRS" ;;
    esac
fi

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd --all 2>/dev/null || true
fi

# LightDM passes the entire desktop file Exec string as a single argument ($1).
# Using eval exec ensures word-splitting occurs so arguments (--wayland, etc.) are parsed.
if [ $# -gt 0 ]; then
    eval exec "$@"
else
    exec cinnamon-session-cinnamon --wayland
fi
EOF
chmod 755 "${ROOTFS_DIR}/usr/sbin/lightdm-wayland-session"

cat << 'EOF' > "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/90-lmde-wayland.conf"
[SeatDefaults]
user-session=cinnamon-wayland

[Seat:*]
greeter-session=pi-greeter-labwc
user-session=cinnamon-wayland
autologin-session=cinnamon-wayland
session-wrapper=/usr/sbin/lightdm-wayland-session
greeter-hide-users=false
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/lightdm/pi-greeter.conf"
[greeter]
default-user-image=/usr/share/icons/hicolor/scalable/apps/linuxmint-logo-ring.svg
desktop_bg=#2f2f2f
wallpaper=/usr/share/backgrounds/linuxmint/default_background.jpg
wallpaper_mode=crop
gtk-theme-name=Mint-Y-Aqua
gtk-icon-theme-name=Mint-Y-Sand
gtk-font-name=Ubuntu 11
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/labwc-greeter/autostart"
/usr/sbin/pi-greeter &
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/labwc-greeter/environment"
XCURSOR_THEME=Bibata-Modern-Classic
XCURSOR_SIZE=24
LABWC_FALLBACK_OUTPUT=NOOP-1
XKB_DEFAULT_MODEL=pc105
XKB_DEFAULT_LAYOUT=us
XKB_DEFAULT_VARIANT=
XKB_DEFAULT_OPTIONS=
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/labwc-greeter/rc.xml"
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Mint-Y-Aqua</name>
    <cornerRadius>6</cornerRadius>
    <font place="ActiveWindow">
      <name>Ubuntu</name>
      <size>11</size>
      <weight>Normal</weight>
      <slant>Normal</slant>
    </font>
    <font place="InactiveWindow">
      <name>Ubuntu</name>
      <size>11</size>
      <weight>Normal</weight>
      <slant>Normal</slant>
    </font>
  </theme>
  <keyboard>
    <numlock>off</numlock>
  </keyboard>
</openbox_config>
EOF

# Allow administrative GUI apps (Timeshift, Synaptic, GParted, MintSources) via XWayland
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/xwayland-root-xhost.desktop"
[Desktop Entry]
Type=Application
Name=XWayland Root GUI Access
Exec=sh -c 'command -v xhost >/dev/null 2>&1 && [ -n "$DISPLAY" ] && xhost +SI:localuser:root >/dev/null 2>&1 || true'
NoDisplay=true
OnlyShowIn=X-Cinnamon;
EOF

# 2. Prevent LightDM Wayland greeter system user from holding ALSA/HDMI audio devices
for unit in pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service filter-chain.service; do
    install -d -m 755 "${ROOTFS_DIR}/etc/systemd/user/${unit}.d"
    cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/user/${unit}.d/nosystem.conf"
[Unit]
ConditionUser=!@system
EOF
done

# 3. Import Wayland environment into D-Bus and systemd user session on Cinnamon startup
install -d -m 755 "${ROOTFS_DIR}/usr/libexec" "${ROOTFS_DIR}/etc/xdg/xdg-desktop-portal" "${ROOTFS_DIR}/etc/sysctl.d"

cat << 'EOF' > "${ROOTFS_DIR}/usr/libexec/wayland-env-import.sh"
#!/bin/bash
for i in $(seq 1 50); do
    if [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
        break
    fi
    sleep 0.1
done
export WAYLAND_DISPLAY="wayland-0"
export DISPLAY="${DISPLAY:-:0}"
export XDG_CURRENT_DESKTOP="X-Cinnamon"
export XDG_SESSION_TYPE="wayland"
export XDG_SESSION_DESKTOP="cinnamon-wayland"
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP 2>/dev/null || true
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
fi
EOF
chmod 755 "${ROOTFS_DIR}/usr/libexec/wayland-env-import.sh"

cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/wayland-env-import.desktop"
[Desktop Entry]
Type=Application
Name=Wayland Environment Importer
Comment=Imports WAYLAND_DISPLAY and DISPLAY into D-Bus and systemd user session
Exec=/usr/libexec/wayland-env-import.sh
OnlyShowIn=X-Cinnamon;
NoDisplay=true
X-GNOME-Autostart-Phase=Initialization
X-GNOME-Autostart-Notify=false
X-GNOME-AutoRestart=false
EOF

# 4. Pure Wayland portal configuration (prevents xdg-desktop-portal 25s timeout)
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/xdg-desktop-portal/portals.conf"
[preferred]
default=gtk;xapp;
org.freedesktop.impl.portal.Secret=gnome-keyring;
org.freedesktop.impl.portal.Inhibit=none
org.freedesktop.impl.portal.ScreenSaver=none
org.freedesktop.impl.portal.Lockdown=none
EOF
cp "${ROOTFS_DIR}/etc/xdg/xdg-desktop-portal/portals.conf" "${ROOTFS_DIR}/etc/xdg/xdg-desktop-portal/x-cinnamon-portals.conf"

# 5. Prevent USB flash drive write stalls and buffer bloat
cat << 'EOF' > "${ROOTFS_DIR}/etc/sysctl.d/99-usb-storage.conf"
vm.dirty_background_bytes = 16777216
vm.dirty_bytes = 41943040
EOF

# 6. Cinnamon session launcher with automatic Wayland background environment sync
cat << 'EOF' > "${ROOTFS_DIR}/usr/bin/cinnamon-session-cinnamon"
#!/bin/sh
if [ "$1" = "--wayland" ]; then
    (
        for i in $(seq 1 50); do
            if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
                sleep 0.1
                dbus-update-activation-environment --systemd WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=wayland XDG_SESSION_DESKTOP=cinnamon-wayland 2>/dev/null || true
                systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP 2>/dev/null || true
                systemctl --user restart xdg-desktop-portal 2>/dev/null || true
                break
            fi
            sleep 0.1
        done
    ) &
    exec cinnamon-session --session cinnamon-wayland
else
    exec cinnamon-session --session cinnamon "$@"
fi
EOF
chmod 755 "${ROOTFS_DIR}/usr/bin/cinnamon-session-cinnamon"

on_chroot <<- \EOF
	# Remove any Xorg server packages so the system is 100% pure Wayland (+ XWayland)
	apt-get purge -y 'xserver-xorg*' 2>/dev/null || true
	apt-get autoremove -y --purge 2>/dev/null || true

	# Hide X11 sessions and standalone labwc session cleanly across upgrades; keep only cinnamon-wayland
	for f in \
		/usr/share/xsessions/cinnamon.desktop \
		/usr/share/xsessions/cinnamon2d.desktop \
		/usr/share/xsessions/lightdm-xsession.desktop \
		/usr/share/xsessions/openbox.desktop \
		/usr/share/wayland-sessions/labwc.desktop; do
		dpkg-divert --package lmde-arm64 --add --rename --divert "${f}.disabled" "$f" 2>/dev/null || true
		rm -f "${f}.disabled"
	done

	# Default web browser
	update-alternatives --set x-www-browser /usr/bin/firefox || true
	update-alternatives --set gnome-www-browser /usr/bin/firefox || true

	# Official LMDE Plymouth bootscreen (mint-logo from debian-system-adjustments)
	plymouth-set-default-theme mint-logo || true

	# Flathub integration (standard in LMDE) & GSettings schema compilation
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
	glib-compile-schemas /usr/share/glib-2.0/schemas || true

	# Use Pi OS native ZRAM-only mechanism (avoids /var/swap file on compressed Btrfs)
	install -d -m 755 /etc/rpi/swap.conf.d
	cat <<- 'SWAPCONF' > /etc/rpi/swap.conf.d/zram-only.conf
	[Main]
	Mechanism=zram
	SWAPCONF
	rm -f /var/swap /etc/systemd/zram-generator.conf

	# Qt Wayland fallback environment
	if ! grep -q "QT_QPA_PLATFORM" /etc/environment 2>/dev/null; then
		echo 'QT_QPA_PLATFORM="wayland;xcb"' >> /etc/environment
	fi
	sed -i '/^MOZ_X11_EGL=/d' /etc/environment 2>/dev/null || true

	# PolicyKit rules for Linux Mint Update Manager & Software Manager on Debian Trixie
	install -d -m 755 /etc/polkit-1/rules.d
	cat <<- 'POLKITCONF' > /etc/polkit-1/rules.d/60-aptkit.rules
	polkit.addRule(function(action, subject) {
	    if ((action.id.indexOf("org.aptkit.") === 0 ||
	         action.id.indexOf("org.freedesktop.packagekit.") === 0) &&
	        (subject.isInGroup("sudo") || subject.isInGroup("admin"))) {
	            return polkit.Result.YES;
	    }
	});
	POLKITCONF
	chmod 644 /etc/polkit-1/rules.d/60-aptkit.rules

	# Pre-generate common locales for instant language switching in First-Boot & MintLocale
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

	# Guard mintUpdate checkAPT.py against NoneType locale return on initial boot
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

	# Initial valid date seed for mintupdate
	install -d -m 755 /etc/skel/.linuxmint/mintupdate
	echo '{"version": 1, "updates": {}, "checked": "1970.01.01", "notified": "1970.01.01"}' > /etc/skel/.linuxmint/mintupdate/updates.json

	# Systemd first-boot preset protection (keeps SSH & ext4-only services disabled on first boot)
	install -d -m 755 /etc/systemd/system-preset
	cat << 'EOF_PRESET' > /etc/systemd/system-preset/00-lmde.preset
disable ssh.service
disable ssh.socket
disable rpi-resize.service
disable systemd-firstboot.service
disable e2scrub_reap.service
disable e2scrub_all.timer
disable apt-listchanges.timer
EOF_PRESET

	systemctl enable lightdm rpi-eeprom-update.service ModemManager.service blueman-mechanism.service fstrim.timer bluetooth.service packagekit.service debian-system-adjustments.service mintsystem.service || true
	systemctl disable ssh.service ssh.socket e2scrub_reap.service e2scrub_all.timer 2>/dev/null || true
	systemctl mask NetworkManager-wait-online.service systemd-networkd-wait-online.service rpi-resize.service systemd-firstboot.service 2>/dev/null || true
	systemctl set-default graphical.target
EOF
