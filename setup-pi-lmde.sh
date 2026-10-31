#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (e.g. sudo $0)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo ">>> [1/6] Installing prerequisites (curl, wget, gpg, ca-certificates)..."
apt-get update
apt-get install -y curl wget gnupg ca-certificates

echo ">>> [2/6] Importing GPG keys for LMPE (lmde-arm64) and Linux Mint..."
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

Package: *
Pin: origin "packages.linuxmint.com"
Pin-Priority: 700
EOF

echo ">>> [5/6] Updating package cache and installing LMPE / Cinnamon Desktop..."
apt-get update && apt-get full-upgrade -y
apt-get install -y \
  cinnamon \
  muffin \
  nemo \
  lightdm \
  slick-greeter \
  mint-themes \
  mint-y-icons \
  mintupdate \
  mintinstall \
  mintsources \
  xed \
  xviewer \
  xviewer-plugins \
  xreader \
  pix \
  xdg-desktop-portal-xapp \
  ffmpegthumbnailer \
  btop \
  htop \
  fastfetch

echo ">>> [6/6] Configuring LightDM with Slick Greeter..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'EOF' > /etc/lightdm/lightdm.conf.d/90-slick-greeter.conf
[Seat:*]
greeter-session=slick-greeter
user-session=cinnamon
EOF

systemctl enable lightdm
systemctl set-default graphical.target

echo ">>> Installation completed successfully! Please reboot your Raspberry Pi (sudo reboot)."
