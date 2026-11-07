# LMPE — Unofficial Linux Mint Pi Edition 🍓🍃

[![Status](https://img.shields.io/badge/Status-Unofficial%20Community%20Port-orange?style=flat-square)](#-license--community-disclaimer)
[![Build LMPE Repo](https://github.com/GamingTux/lmde-arm64/actions/workflows/build.yml/badge.svg)](https://github.com/GamingTux/lmde-arm64/actions/workflows/build.yml)
[![Build LMPE Image](https://github.com/GamingTux/lmde-arm64/actions/workflows/build-image.yml/badge.svg)](https://github.com/GamingTux/lmde-arm64/actions/workflows/build-image.yml)
[![GitHub Release](https://img.shields.io/github/v/release/GamingTux/lmde-arm64?include_prereleases&style=flat-square&color=87cf3e)](https://github.com/GamingTux/lmde-arm64/releases)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64%20(Cortex--A76)-blue?style=flat-square)](https://github.com/GamingTux/lmde-arm64)
[![Base](https://img.shields.io/badge/Base-Debian%2013%20Trixie%20%2F%20LMDE%207-green?style=flat-square)](https://www.linuxmint.com/)
[![Display](https://img.shields.io/badge/Display-Pure%20Wayland-5fb336?style=flat-square)](https://wayland.freedesktop.org/)
[![Filesystem](https://img.shields.io/badge/RootFS-Btrfs%20%2B%20zstd%3A2-orange?style=flat-square)](https://btrfs.readthedocs.io/)
[![License](https://img.shields.io/github/license/GamingTux/lmde-arm64?style=flat-square)](LICENSE)

> **An authentic, pure Linux Mint Debian Edition (LMDE 7 "Gigi") Cinnamon desktop experience on Wayland — engineered exclusively for Raspberry Pi 5, Compute Module 5 (CM5), and Raspberry Pi 500.**  
> Built upon **LMDE 7 ("gigi")** and **Debian 13 Trixie**, LMPE delivers an unmodified, upstream-faithful Linux Mint desktop running **100% pure Wayland** and natively compiled for the **Broadcom BCM2712 (ARM Cortex-A76)** 64-bit microarchitecture.  
>  
> *Disclaimer: LMPE is an independent community project by GamingTux and is NOT officially affiliated with, sponsored by, or endorsed by the Linux Mint team or Clement Lefebvre.*

> [!IMPORTANT]
> **Hardware Exclusivity:** LMPE is strictly engineered for the **Raspberry Pi 5**, **Compute Module 5 (CM5)**, and **Raspberry Pi 500**. It compiles and leverages ARMv8.2-A, Dot Product, FP16, and hardware cryptography instructions that are physically absent on older Raspberry Pi generations (Pi 4, Pi 3, Pi Zero 2W). Attempting to run LMPE on older boards will result in immediate `Illegal instruction` (SIGILL) termination.

---

## 🌟 Why LMPE?

Linux Mint is celebrated for its clean design, stability, and intuitive Cinnamon desktop environment. However, **the Linux Mint team does not publish an official ARM64 edition for single-board computers**.

**LMPE (Unofficial Linux Mint Pi Edition)** bridges this gap by combining an authentic, untinkered **LMDE 7 ("Gigi")** desktop experience with the Raspberry Pi 5's modern graphics and storage stack:

1. **Authentic LMDE 7 Experience:** Ships the official Linux Mint `mint-logo` Plymouth boot splash, official Mint wallpapers (`mint-artwork`), `Mint-Y` themes and icon sets, `debian-system-adjustments`, and the complete Mint XApps & utility suite — without custom theme forks or non-standard kernel/sysctl overrides.
2. **100% Xorg-Free Pure Wayland Stack:** Built directly around Raspberry Pi's KMS/DRM VideoCore VII driver architecture. Both the LightDM login screen (`pi-greeter-labwc`) and the desktop session (`cinnamon-wayland`) run natively on Wayland, with `xwayland` transparently supporting legacy X11 and administrative tools.
3. **Dedicated GPG-Signed Cortex-A76 APT Repository:** Over **290+ system, Wayland, multimedia, and Linux Mint source packages** natively compiled for the Raspberry Pi 5's **ARMv8.2-A Cortex-A76** CPU (`-mcpu=cortex-a76+crypto`, 16 KB ELF page alignment, VideoCore VII-pruned Mesa, and PGO-optimized Python 3.13).
4. **Snapshot-Ready Btrfs + ZRAM Foundation:** Ready-to-flash OS images featuring a **Btrfs** root filesystem with transparent `zstd:2` compression (ideal for instant **Timeshift** snapshots) and Raspberry Pi OS native ZRAM swap.

---

## 🚀 Key Features

### 🍃 Authentic LMDE 7 Cinnamon Desktop & XApps Suite
Includes the genuine Linux Mint Debian Edition 7 desktop stack out of the box:
* **Cinnamon 6.6 Desktop on Wayland:** Modern composited Cinnamon Wayland desktop (`muffin`), official `mint-logo` Plymouth boot screen, and official Linux Mint backgrounds, `Mint-Y` themes, and icons.
* **Complete Mint Utilities:** Timeshift (instant Btrfs system snapshots), MintUpdate, MintInstall (Software Manager with Flatpak/Flathub), MintSources, MintWelcome, MintStick, MintReport, MintBackup, MintLocale, Warpinator, Gufw, Bulky, Folder Color Switcher, Sticky Notes, and Thingy.
* **Multimedia & Everyday Apps:** Firefox (with `rpi-firefox-mods` & Widevine DRM), Celluloid, Hypnotix, Drawing, Xed, Xviewer, Xreader, Pix, GParted, Baobab, Pavucontrol, and Seahorse.

### 🪟 Pure Wayland Display Architecture
Raspberry Pi's VideoCore VII (`v3d` / `vc4`) KMS/DRM graphics stack is designed first and foremost for Wayland:
* **Zero Xorg Server:** No `xserver-xorg` packages or legacy X11 drivers are installed.
* **Wayland Login Greeter:** LightDM launches a Mint-Y styled Wayland greeter (`pi-greeter-labwc`) before handing off cleanly to `cinnamon-wayland`.
* **Seamless XWayland Compatibility:** On-demand `xwayland` support with automatic local root Xauthority access (`xhost +SI:localuser:root`) ensures administrative applications like **Timeshift**, **Synaptic**, and **GParted** work out of the box.
* **Rolling Upstream Improvements:** As Linux Mint refines Wayland support in Cinnamon and Muffin, updates arrive directly through `mintupdate` / `apt full-upgrade`.

### ⚡ Broadcom BCM2712 (Cortex-A76) Native Repository
Packages in the LMPE repository are compiled natively for the BCM2712's Cortex-A76 microarchitecture, cache geometry, and `rpi-2712` 16 KB hardware page size:
```text
-mcpu=cortex-a76+crypto -mtune=cortex-a76 -mno-outline-atomics -mearly-ra=all -O3 -flto=auto
-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384
```
* **Pruned VideoCore VII Mesa:** `mesa` is built specifically for Raspberry Pi 5 (`v3d`, `vc4`, `zink`, `llvmpipe` & `broadcom` Vulkan) without x86/desktop GPU driver bloat.
* **Python 3.13 with PGO:** Built with Profile-Guided Optimization (`+15–25%` faster execution across Cinnamon settings, MintUpdate, MintInstall, and Nemo extensions).
* **SIMD Multimedia:** `ffmpeg`, `dav1d`, `libvpx`, `pixman`, `cairo`, and `pipewire` leverage NEON/DotProd/FP16 `-O3` vectorization for smooth 1080p60 playback.

### 🗄️ Btrfs Root Filesystem & Native ZRAM
* **Transparent Compression:** `defaults,compress=zstd:2,noatime,ssd,discard=async` saves flash space, reduces SD/NVMe wear, and enables instantaneous copy-on-write **Timeshift** snapshots.
* **Automatic First-Boot Resize:** `lmpe-btrfs-resize.service` automatically expands the Btrfs partition and filesystem to fill your MicroSD card or NVMe SSD on initial boot.
* **Pure ZRAM Swap:** Uses Raspberry Pi OS's native ZRAM mechanism (`rpi-swap` configured to `Mechanism=zram`), avoiding swap files on flash storage.

---

## 💻 Hardware Compatibility Matrix

| Device | Status | Architecture | Specifications |
| :--- | :---: | :---: | :--- |
| **Raspberry Pi 5 (4GB / 8GB / 16GB)** | ✅ Full Support | ARMv8.2-A Cortex-A76 | VideoCore VII (OpenGL 3.1, Vulkan 1.3), PCIe NVMe, dual 4K60 HDMI. |
| **Raspberry Pi Compute Module 5 (CM5)** | ✅ Full Support | ARMv8.2-A Cortex-A76 | Stock Raspberry Pi OS Trixie firmware & device-tree configuration (`dwc2` host routing). |
| **Raspberry Pi 500** | ✅ Full Support | ARMv8.2-A Cortex-A76 | Integrated keyboard computer based on BCM2712. |
| **Raspberry Pi 4 / 400 / 3 / Zero 2W** | ❌ Incompatible | ARMv8-A Cortex-A72/A53 | **Unsupported.** Lacks ARMv8.2-A, Dot Product, and Crypto instructions (`Illegal instruction` crash). |

---

## 📥 Downloads & Installation

### Option 1: Flash the Pre-Built Image (Recommended)

1. Download the latest bootable release image from **[GitHub Releases](https://github.com/GamingTux/lmde-arm64/releases/latest)**:
   * Image: `image_YYYY-MM-DD-lmpe-arm64-pi5-cinnamon-btrfs.img.xz`
2. Flash the compressed `.img.xz` file directly onto an NVMe SSD or MicroSD card:
   * **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** (*Select "Use Custom"* — do not apply OS customisation, as LMPE includes its own first-boot wizard)
   * **[Balena Etcher](https://etcher.balena.io/)**
   * Command Line (`dd`):
     ```bash
     xz -dc image_*-lmpe-arm64-pi5-cinnamon-btrfs.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
     ```
3. Insert the drive into your Raspberry Pi 5 / CM5 / Pi 500 and power on.
4. On first boot:
   * The Btrfs root filesystem automatically expands to fill your storage drive.
   * A clean 5-step setup wizard configures your **keyboard layout**, **language & timezone**, **hostname**, **Wi-Fi**, and **user account / automatic login**, then launches the Cinnamon Wayland desktop.

---

### Option 2: Convert Existing Raspberry Pi OS (Trixie Lite)

If you have an existing minimal installation of **Raspberry Pi OS Lite (64-bit, Debian 13 Trixie)** on a Raspberry Pi 5, CM5, or Pi 500, convert it to LMPE (LMDE 7 Wayland) with a single script:

```bash
curl -fsSL https://raw.githubusercontent.com/GamingTux/lmde-arm64/main/setup-pi-lmde.sh | sudo bash
```

After installation completes, reboot into Cinnamon Wayland:
```bash
sudo reboot
```

---

## ⚙️ Architecture Optimization Tiers

Standard Debian ARM64 binaries target the baseline `armv8-a` instruction set for compatibility with older boards. LMPE compiles its repository packages specifically for the **ARMv8.2-A Cortex-A76** core in the Raspberry Pi 5:

| Optimization Profile | Target Packages | Compiler & Linker Highlights |
| :--- | :--- | :--- |
| **Core, Multimedia & Graphics (`-O3` + Graphite + LTO)** | `glibc`, Compression (`zlib`, `lz4`, `libzstd`, `xz-utils`), Crypto (`openssl`, `gnutls28`, `nettle`), System & IPC (`systemd`, `dbus`, `glib2.0`, `flatpak`, `packagekit`), Pure Wayland & 3D (`wayland`, `wlroots`, `labwc`, `lightdm`, `pi-greeter`, `xwayland`, pruned `mesa` `v3d`/`vc4`), Codecs & Audio (`ffmpeg`, `dav1d`, `libvpx`, `pipewire`, `gstreamer1.0`), `python3.13` (with PGO) | `-mcpu=cortex-a76+crypto -mtune=cortex-a76 -mno-outline-atomics -mearly-ra=all --param l1-cache-size=64 --param l2-cache-size=512 -O3 -fgraphite-identity -floop-nest-optimize -flto=auto` + `16 KB` ELF page alignment |
| **LMDE 7 / Cinnamon Wayland Stack (`-O3`)** | Cinnamon 6.6, Muffin Wayland Compositor, Nemo & Extensions, CJS, XApps (`xed`, `xviewer`, `xreader`, `pix`), `libadwaita-1`, `libadapta-1`, Timeshift, Warpinator | Full Cortex-A76 `-O3` vectorization with automatic 3-stage self-healing fallback (`-O3+LTO` → `-O3` → `-O2`) and `xz -9e` package compression |

Every custom package carries the `+pi5` local version suffix and is cryptographically signed with the LMPE repository GPG key.

---

## 🎛️ APT Repository & Package Priorities

LMPE uses clean APT pinning to combine Cortex-A76 packages, official Raspberry Pi kernel/firmware updates, upstream Linux Mint `all` packages, and Debian 13 Trixie:

```text
/etc/apt/preferences.d/lmde-pi5.pref:

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
```

* **`gamingtux.github.io` (Priority 1001):** Delivers Cortex-A76 compiled LMDE 7 desktop and multimedia packages (`+pi5`).
* **`archive.raspberrypi.com` (Priority 1000):** Supplies the official Raspberry Pi kernel (`linux-image-rpi-2712`), firmware, bootloader, EEPROM, and VideoCore VII stack.
* **`packages.linuxmint.com` (`*:amd64` Priority -1):** Blocks foreign `amd64` binary packages from Linux Mint.
* **`packages.linuxmint.com` (Priority 700):** Delivers architecture-independent (`Architecture: all`) Linux Mint packages (`debian-system-adjustments`, `mintupdate`, `mintinstall`, `mintsources`, `mint-artwork`, `mint-themes`, `mint-y-icons`).
* **`deb.debian.org` (Priority 500 / default):** Supplies the full Debian 13 (Trixie) ARM64 software archive.

---

## ❓ Frequently Asked Questions (FAQ)

<details>
<summary><b>Why does LMPE run pure Wayland without Xorg?</b></summary>
Raspberry Pi 5's VideoCore VII graphics architecture (<code>v3d</code> / <code>vc4</code> KMS/DRM) is engineered primarily for Wayland compositors rather than legacy Xorg drivers. Running pure Wayland eliminates screen tearing and legacy X11 overhead while <code>xwayland</code> keeps older X11 and root administrative tools working transparently. As Linux Mint continues improving Cinnamon's Wayland session across point releases, LMPE automatically benefits through normal system updates.
</details>

<details>
<summary><b>Can I install software using Flatpak and Flathub?</b></summary>
Yes! Flatpak and Flathub are enabled out of the box, just like in upstream LMDE 7. You can install Flatpaks graphically in the Linux Mint Software Manager (<code>mintinstall</code>) or via terminal:

```bash
flatpak install flathub <app_name>
```
</details>

<details>
<summary><b>How do I enable PCIe Gen 3 for my NVMe SSD?</b></summary>
LMPE ships with the unmodified stock Raspberry Pi OS <code>/boot/firmware/config.txt</code>, which defaults to PCIe Gen 2 for maximum HAT compatibility. If your NVMe adapter and SSD support PCIe Gen 3, add the following lines to <code>/boot/firmware/config.txt</code>:

```ini
dtparam=nvme
dtparam=pciex1_gen=3
```
</details>

<details>
<summary><b>How is video playback (YouTube / streaming) accelerated?</b></summary>
The Broadcom BCM2712 SoC provides hardware decoding for HEVC/H.265, while VP9, AV1, and H.264 are decoded on the Cortex-A76 CPU using ARMv8.2-A SIMD-optimized libraries (<code>dav1d</code>, <code>libvpx</code>, <code>ffmpeg</code>). Firefox comes pre-configured with <code>rpi-firefox-mods</code> and Widevine DRM (<code>libwidevinecdm0</code>).
</details>

<details>
<summary><b>How do I keep LMPE updated?</b></summary>
Use the graphical Linux Mint Update Manager (<code>mintupdate</code>) in the panel tray, or run:

```bash
sudo apt update && sudo apt full-upgrade
```
</details>

<details>
<summary><b>Why is Raspberry Pi 4 / 3 not supported?</b></summary>
LMPE binaries are compiled specifically for the <b>ARMv8.2-A Cortex-A76</b> microarchitecture. Older Raspberry Pi generations (Pi 4 Cortex-A72, Pi 3 Cortex-A53) lack ARMv8.2-A, hardware cryptography, and dot product instructions and will fail with <code>Illegal instruction</code> (SIGILL).
</details>

---

## 🏷️ Tags & Keywords

`raspberry-pi-5` • `cinnamon-desktop` • `wayland` • `linux-mint` • `lmde` • `arm64` • `compute-module-5` • `cm5` • `bcm2712` • `cortex-a76` • `btrfs` • `zstd` • `zram` • `videocore-vii` • `debian-13` • `trixie`

---

## ⚖️ License & Community Disclaimer

* **License:** Code and build scripts in this repository are licensed under the [MIT License](LICENSE). Software included in the distribution is licensed under their respective upstream open-source licenses (GPL, LGPL, BSD, MIT).
* **Community Project Disclaimer:** *LMPE* is an independent, community-driven open source project developed by GamingTux. It is **not** an official distribution by Linux Mint, Clement Lefebvre, or Raspberry Pi Ltd., nor is it officially endorsed or sponsored by them. "Linux Mint", "LMDE", "Cinnamon", and "Raspberry Pi" are trademarks of their respective owners.

---

<p align="center">
  <b>Engineered with ❤️ for the Raspberry Pi and Linux Mint communities.</b>
</p>
