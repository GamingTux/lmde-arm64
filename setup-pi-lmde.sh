#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (e.g. sudo $0)" >&2
  exit 1
fi

# Hardware check: LMPE Cortex-A76 binaries will crash with SIGILL on older Pi models
if [[ -f /sys/firmware/devicetree/base/model ]]; then
  MODEL="$(tr -d '\0' < /sys/firmware/devicetree/base/model)"
  if [[ "$MODEL" != *"Raspberry Pi 5"* && "$MODEL" != *"Compute Module 5"* && "$MODEL" != *"Raspberry Pi 500"* ]]; then
    echo "❌ ERROR: LMPE is exclusively engineered for Raspberry Pi 5 / Compute Module 5 (Cortex-A76)." >&2
    echo "Detected hardware: $MODEL" >&2
    echo "Older generations (Pi 4, Pi 3, Pi Zero 2W) lack ARMv8.2-A + crypto + dotprod instructions and cannot run LMPE." >&2
    exit 1
  fi
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
  firefox \
  rpi-firefox-mods \
  ffmpegthumbnailer \
  btop \
  htop \
  fastfetch

echo ">>> [6/6] Configuring LightDM with Slick Greeter and Firefox GPU acceleration..."
mkdir -p /etc/lightdm/lightdm.conf.d /etc/firefox /usr/lib/firefox/browser/defaults/preferences
cat << 'EOF' > /etc/firefox/99-lmpe-pi5.js
// LMPE Raspberry Pi 5 GPU- & Codec-Optimierungen für Firefox
pref("gfx.webrender.all", true);
pref("layers.acceleration.force-enabled", true);
pref("media.ffmpeg.vaapi.enabled", false);
pref("widget.dmabuf.textures", false);
pref("media.ffvpx.enabled", true);
pref("media.rdd-ffmpeg.enabled", false);
pref("media.av1.enabled", true);
pref("media.mediasource.vp9.enabled", true);
pref("media.webm.enabled", true);
EOF
cp /etc/firefox/99-lmpe-pi5.js /usr/lib/firefox/browser/defaults/preferences/99-lmpe-pi5.js 2>/dev/null || true

cat << 'EOF' > /etc/lightdm/lightdm.conf.d/90-slick-greeter.conf
[Seat:*]
greeter-session=slick-greeter
user-session=cinnamon
EOF

systemctl enable lightdm
systemctl set-default graphical.target

echo ">>> Installation completed successfully! Please reboot your Raspberry Pi (sudo reboot)."
