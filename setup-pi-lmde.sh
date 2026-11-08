#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (e.g. sudo $0)" >&2
  exit 1
fi

# Hardware check: Cortex-A76 binaries will crash with SIGILL on older Pi models
if [[ -f /sys/firmware/devicetree/base/model ]]; then
  MODEL="$(tr -d '\0' < /sys/firmware/devicetree/base/model)"
  if [[ "$MODEL" != *"Raspberry Pi 5"* && "$MODEL" != *"Compute Module 5"* && "$MODEL" != *"Raspberry Pi 500"* ]]; then
    echo "❌ ERROR: This LMDE 7 ARM64 port is exclusively engineered for Raspberry Pi 5 / Compute Module 5 / Pi 500 (Cortex-A76)." >&2
    echo "Detected hardware: $MODEL" >&2
    echo "Older generations (Pi 4, Pi 3, Pi Zero 2W) lack ARMv8.2-A + crypto + dotprod instructions." >&2
    exit 1
  fi
fi

export DEBIAN_FRONTEND=noninteractive

echo ">>> [1/6] Installing prerequisites (curl, wget, gpg, ca-certificates)..."
apt-get update
apt-get install -y curl wget gnupg ca-certificates

echo ">>> [2/6] Importing GPG keys for lmde-arm64 and Linux Mint..."
mkdir -p /usr/share/keyrings
curl -fsSL "https://gamingtux.github.io/lmde-arm64/lmde-arm64.gpg" -o /usr/share/keyrings/lmde-arm64.gpg
chmod 644 /usr/share/keyrings/lmde-arm64.gpg

KEYRING_DEB="$(curl -fsSL http://packages.linuxmint.com/pool/main/l/linuxmint-keyring/ | grep -oE 'linuxmint-keyring_[^"]+\.deb' | sort -V | tail -n 1)"
wget -qO "/tmp/${KEYRING_DEB}" "http://packages.linuxmint.com/pool/main/l/linuxmint-keyring/${KEYRING_DEB}"
dpkg -i "/tmp/${KEYRING_DEB}"
rm -f "/tmp/${KEYRING_DEB}"

echo ">>> [3/6] Configuring APT package sources (/etc/apt/sources.list.d/lmde.list)..."
cat << 'EOF' > /etc/apt/sources.list.d/lmde.list
deb [arch=arm64 signed-by=/usr/share/keyrings/lmde-arm64.gpg] https://gamingtux.github.io/lmde-arm64 gigi main
deb [arch=amd64 signed-by=/usr/share/keyrings/linuxmint-keyring.gpg] http://packages.linuxmint.com gigi main upstream import backport
EOF

echo ">>> [4/6] Configuring APT pinning preferences (/etc/apt/preferences.d/lmde-pi5.pref)..."
cat << 'EOF' > /etc/apt/preferences.d/lmde-pi5.pref
Package: *
Pin: origin "gamingtux.github.io"
Pin-Priority: 1001

Package: *
Pin: origin "archive.raspberrypi.com"
Pin-Priority: 1000

Package: *:amd64
Pin: origin "packages.linuxmint.com"
Pin-Priority: -1

Package: *
Pin: origin "packages.linuxmint.com"
Pin-Priority: 700
EOF

echo ">>> [5/6] Installing LMDE 7 (Cinnamon Wayland) desktop & official Mint tools..."
apt-get update && apt-get full-upgrade -y
apt-get install -y \
  cinnamon \
  muffin \
  nemo \
  lightdm \
  pi-greeter \
  labwc \
  xwayland \
  x11-xserver-utils \
  debian-system-adjustments \
  grub2-theme-mint \
  mintsystem \
  mint-common \
  mint-translations \
  mint-info-cinnamon \
  mint-artwork \
  mint-themes \
  mint-y-icons \
  mint-x-icons \
  bibata-cursor-theme \
  mintupdate \
  mintinstall \
  mintsources \
  mintwelcome \
  mintstick \
  mintreport \
  mintbackup \
  mintlocale \
  timeshift \
  synaptic \
  fonts-ubuntu \
  fonts-cantarell \
  fonts-noto-color-emoji \
  xed \
  xviewer \
  xviewer-plugins \
  xreader \
  pix \
  celluloid \
  hypnotix \
  drawing \
  warpinator \
  xdg-desktop-portal \
  xdg-desktop-portal-xapp \
  xdg-desktop-portal-gtk \
  firefox \
  rpi-firefox-mods \
  ffmpegthumbnailer \
  fastfetch \
  plymouth \
  plymouth-themes

apt-get purge -y 'xserver-xorg*' slick-greeter 2>/dev/null || true
apt-get autoremove -y --purge 2>/dev/null || true

echo ">>> [6/6] Configuring pure Wayland LightDM session & official LMDE Plymouth bootscreen..."
install -d -m 755 /usr/sbin /etc/lightdm/lightdm.conf.d /etc/xdg/labwc-greeter /etc/xdg/autostart /etc/polkit-1/rules.d

cat << 'EOF' > /usr/sbin/lightdm-wayland-session
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
chmod 755 /usr/sbin/lightdm-wayland-session

rm -f /etc/lightdm/lightdm.conf.d/90-slick-greeter.conf
cat << 'EOF' > /etc/lightdm/lightdm.conf.d/90-lmde-wayland.conf
[SeatDefaults]
user-session=cinnamon-wayland

[Seat:*]
greeter-session=pi-greeter-labwc
user-session=cinnamon-wayland
autologin-session=cinnamon-wayland
session-wrapper=/usr/sbin/lightdm-wayland-session
greeter-hide-users=false
EOF

cat << 'EOF' > /etc/lightdm/pi-greeter.conf
[greeter]
default-user-image=/usr/share/icons/hicolor/scalable/apps/linuxmint-logo-ring.svg
desktop_bg=#2f2f2f
wallpaper=/usr/share/backgrounds/linuxmint/default_background.jpg
wallpaper_mode=crop
gtk-theme-name=Mint-Y-Aqua
gtk-icon-theme-name=Mint-Y-Sand
gtk-font-name=Ubuntu 11
EOF

XKB_LAYOUT="$(awk -F'"' '/^XKBLAYOUT=/{print $2}' /etc/default/keyboard 2>/dev/null || true)"
XKB_VARIANT="$(awk -F'"' '/^XKBVARIANT=/{print $2}' /etc/default/keyboard 2>/dev/null || true)"
XKB_LAYOUT="${XKB_LAYOUT:-us}"

cat << 'EOF' > /etc/xdg/labwc-greeter/autostart
/usr/sbin/pi-greeter &
EOF

cat << EOF > /etc/xdg/labwc-greeter/environment
XCURSOR_THEME=Bibata-Modern-Classic
XCURSOR_SIZE=24
LABWC_FALLBACK_OUTPUT=NOOP-1
XKB_DEFAULT_MODEL=pc105
XKB_DEFAULT_LAYOUT=${XKB_LAYOUT}
XKB_DEFAULT_VARIANT=${XKB_VARIANT}
XKB_DEFAULT_OPTIONS=
EOF

cat << 'EOF' > /etc/xdg/labwc-greeter/rc.xml
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

cat << 'EOF' > /etc/xdg/autostart/xwayland-root-xhost.desktop
[Desktop Entry]
Type=Application
Name=XWayland Root GUI Access
Exec=sh -c 'command -v xhost >/dev/null 2>&1 && [ -n "$DISPLAY" ] && xhost +SI:localuser:root >/dev/null 2>&1 || true'
NoDisplay=true
OnlyShowIn=X-Cinnamon;
EOF

cat << 'EOF' > /etc/polkit-1/rules.d/60-aptkit.rules
polkit.addRule(function(action, subject) {
    if ((action.id.indexOf("org.aptkit.") === 0 ||
         action.id.indexOf("org.freedesktop.packagekit.") === 0) &&
        (subject.isInGroup("sudo") || subject.isInGroup("admin"))) {
            return polkit.Result.YES;
    }
});
EOF
chmod 644 /etc/polkit-1/rules.d/60-aptkit.rules

# Import Wayland environment into D-Bus and systemd user session on Cinnamon startup
install -d -m 755 /usr/libexec /etc/xdg/xdg-desktop-portal /etc/sysctl.d

cat << 'EOF' > /usr/libexec/wayland-env-import.sh
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
chmod 755 /usr/libexec/wayland-env-import.sh

cat << 'EOF' > /etc/xdg/autostart/wayland-env-import.desktop
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

cat << 'EOF' > /etc/xdg/xdg-desktop-portal/portals.conf
[preferred]
default=gtk;xapp;
org.freedesktop.impl.portal.Secret=gnome-keyring;
org.freedesktop.impl.portal.Inhibit=none
org.freedesktop.impl.portal.ScreenSaver=none
org.freedesktop.impl.portal.Lockdown=none
EOF
cp /etc/xdg/xdg-desktop-portal/portals.conf /etc/xdg/xdg-desktop-portal/x-cinnamon-portals.conf

cat << 'EOF' > /etc/sysctl.d/99-usb-storage.conf
vm.dirty_background_bytes = 16777216
vm.dirty_bytes = 41943040
EOF

cat << 'EOF' > /usr/bin/cinnamon-session-cinnamon
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
chmod 755 /usr/bin/cinnamon-session-cinnamon

for f in \
  /usr/share/xsessions/cinnamon.desktop \
  /usr/share/xsessions/cinnamon2d.desktop \
  /usr/share/xsessions/lightdm-xsession.desktop \
  /usr/share/xsessions/openbox.desktop \
  /usr/share/wayland-sessions/labwc.desktop; do
  dpkg-divert --package lmde-arm64 --add --rename --divert "${f}.disabled" "$f" 2>/dev/null || true
  rm -f "${f}.disabled"
done

plymouth-set-default-theme -R mint-logo || plymouth-set-default-theme mint-logo || true

systemctl enable lightdm debian-system-adjustments.service mintsystem.service packagekit.service || true
systemctl set-default graphical.target

echo ">>> Installation completed successfully! Please reboot your Raspberry Pi (sudo reboot)."
