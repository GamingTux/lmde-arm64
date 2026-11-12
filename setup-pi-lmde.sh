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

echo ">>> [5/6] Installing standard LMDE 7 Cinnamon desktop & official Mint tools..."
apt-get update && apt-get full-upgrade -y
apt-get install -y \
  cinnamon \
  muffin \
  nemo \
  lightdm \
  slick-greeter \
  lightdm-settings \
  touchegg \
  xserver-xorg \
  xserver-xorg-core \
  xserver-xorg-input-libinput \
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
  plymouth-themes \
  xserver-xorg \
  xserver-xorg-core \
  xserver-xorg-input-libinput \
  slick-greeter \
  lightdm-settings

# Ensure Xorg uses modesetting driver for vc4 on Raspberry Pi
install -d -m 755 /etc/X11/xorg.conf.d
cat << 'EOF' > /etc/X11/xorg.conf.d/99-vc4.conf
Section "OutputClass"
    Identifier "vc4"
    MatchDriver "vc4"
    Driver "modesetting"
    Option "PrimaryGPU" "true"
EndSection
EOF

echo ">>> [6/6] Configuring standard LMDE Cinnamon X11 session & official bootscreen..."
install -d -m 755 /usr/sbin /etc/lightdm/lightdm.conf.d /etc/xdg/autostart /etc/polkit-1/rules.d

cat << 'EOF' > /usr/sbin/lightdm-wayland-session
#!/bin/bash
# Wayland session wrapper for LightDM (used when Cinnamon Wayland option is selected)
for file in /etc/profile "$HOME/.profile"; do
    if [ -f "$file" ]; then
        . "$file"
    fi
done

export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
export GTK_MODULES="${GTK_MODULES:+$GTK_MODULES:}xapp-gtk3-module"
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
if [ $# -gt 0 ]; then
    eval exec "$@"
else
    exec cinnamon-session-cinnamon --wayland
fi
EOF
chmod 755 /usr/sbin/lightdm-wayland-session

# Ensure Cinnamon Wayland is an option in /usr/share/wayland-sessions
if [ -f /usr/share/wayland-sessions/cinnamon-wayland.desktop ]; then
    sed -i 's|^Exec=.*|Exec=/usr/sbin/lightdm-wayland-session cinnamon-session-cinnamon --wayland|' /usr/share/wayland-sessions/cinnamon-wayland.desktop
fi

# Standard Linux Mint LightDM configuration (X11 default with slick-greeter)
rm -f /etc/lightdm/lightdm.conf.d/90-lmde-wayland.conf
cat << 'EOF' > /etc/lightdm/lightdm.conf.d/70-linuxmint.conf
[SeatDefaults]
greeter-session=slick-greeter
user-session=cinnamon
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

# Ensure /etc/environment does not contain overrides that could break desktop sessions
sed -i '/^GDK_BACKEND=/d' /etc/environment 2>/dev/null || true
sed -i '/^QT_QPA_PLATFORM=/d' /etc/environment 2>/dev/null || true
sed -i '/^MOZ_X11_EGL=/d' /etc/environment 2>/dev/null || true
sed -i '/^MOZ_ENABLE_WAYLAND=/d' /etc/environment 2>/dev/null || true
sed -i '/^CLUTTER_BACKEND=/d' /etc/environment 2>/dev/null || true

# Prevent USB flash drive write stalls specifically without restricting NVMe SSD throughput
install -d -m 755 /etc/udev/rules.d
cat << 'EOF' > /etc/udev/rules.d/99-usb-dirty-bytes.rules
# Throttle writeback dirty buffer specifically on slow USB storage to avoid system freezes,
# while leaving fast NVMe / PCIe SSDs at full unthrottled kernel write cache speed.
ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ATTR{bdi/max_bytes}="41943040", ATTR{bdi/strict_limit}="1"
EOF

for f in \
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
