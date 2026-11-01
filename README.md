# LMPE — Linux Mint Pi Edition 🍓🍃

[![Build LMPE Repo](https://github.com/GamingTux/lmde-arm64/actions/workflows/build.yml/badge.svg)](https://github.com/GamingTux/lmde-arm64/actions/workflows/build.yml)
[![Build LMPE Image](https://github.com/GamingTux/lmde-arm64/actions/workflows/build-image.yml/badge.svg)](https://github.com/GamingTux/lmde-arm64/actions/workflows/build-image.yml)
[![GitHub Release](https://img.shields.io/github/v/release/GamingTux/lmde-arm64?include_prereleases&style=flat-square&color=87cf3e)](https://github.com/GamingTux/lmde-arm64/releases)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64%20(Cortex--A76)-blue?style=flat-square)](https://github.com/GamingTux/lmde-arm64)
[![Base](https://img.shields.io/badge/Base-Debian%2013%20Trixie%20%2F%20LMDE%207-green?style=flat-square)](https://www.linuxmint.com/)
[![Filesystem](https://img.shields.io/badge/RootFS-Btrfs%20%2B%20zstd%3A2-orange?style=flat-square)](https://btrfs.readthedocs.io/)
[![License](https://img.shields.io/github/license/GamingTux/lmde-arm64?style=flat-square)](LICENSE)

> **The premier Linux Mint Cinnamon desktop experience engineered exclusively for Raspberry Pi 5, Compute Module 5 (CM5), and Raspberry Pi 500.**  
> Built upon **LMDE 7 ("gigi")** and **Debian 13 Trixie**, LMPE delivers a responsive, feature-rich Linux Mint desktop natively compiled and aggressively optimized for the **Broadcom BCM2712 (ARM Cortex-A76)** 64-bit microarchitecture.

> [!IMPORTANT]
> **Hardware Exclusivity:** LMPE is strictly engineered for the **Raspberry Pi 5**, **Compute Module 5 (CM5)**, and **Raspberry Pi 500**. It compiles and leverages ARMv8.2-A, Dot Product, FP16, and hardware cryptography instructions that are physically absent on older Raspberry Pi generations (Pi 4, Pi 3, Pi Zero 2W). Attempting to run LMPE on older boards will result in immediate `Illegal instruction` (SIGILL) termination.

---

<p align="center">
  <img src="assets/lmpe-hero.png" alt="LMPE - Linux Mint Pi Edition Boot Splash (Tatooine Edition)" width="850">
</p>

---

## 🌟 Why LMPE?

Linux Mint is globally celebrated for its elegance, stability, and intuitive Cinnamon desktop environment. However, **Linux Mint does not offer an official ARM64 image for single-board computers**.

**LMPE (Linux Mint Pi Edition)** bridges this gap, transforming the Raspberry Pi 5 into a first-class, workstation-grade Linux Mint desktop:

1. **Ready-to-Flash Bootable OS Images:** Out-of-the-box system images featuring a high-performance **Btrfs** root filesystem with transparent Zstandard (`zstd:2`) compression.
2. **Dedicated GPG-Signed APT Repository:** Over **160+ system and desktop packages** recompiled specifically with Cortex-A76 SIMD vectorization and Link-Time Optimization (`-flto=auto`).
3. **Native Raspberry Pi 5 Hardware Acceleration:** Official 64-bit Raspberry Pi kernel (`linux-image-rpi-2712`), VideoCore VII Mesa GPU drivers (OpenGL 3.1 & Vulkan 1.3), and seamless 4K60 dual-HDMI output.
4. **Fine-Tuned Kernel & Memory Architecture:** Pure compressed ZRAM swap, high-throughput I/O schedulers, accelerated Btrfs background TRIM, and expanded inotify watchers for developers.
5. **Universal Hardware Design:** 100% vendor-agnostic architecture running seamlessly on standard Raspberry Pi 5 boards, industrial CM5 carrier boards, and portable laptops (such as the Argon ONE UP) via an interactive first-boot hardware configuration assistant.

---

## 🌌 Galactic Codenames: The Star Wars Release Cycle

Just as Debian names its releases after *Toy Story* characters and Ubuntu after animals, **LMPE names its major releases after iconic planets from the Star Wars galaxy**.

### Current Release: **LMPE "Tatooine"** ☀️☀️
> *"The journey begins where two suns rise..."*

* **The Upstream Heritage:** In tribute to our upstream Debian 13 (**T**rixie) foundation, our primary release cycle begins with the letter **T**.
* **Where the Saga Begins:** In the Star Wars universe, Tatooine is the legendary desert world where epic journeys begin. For LMPE, *Tatooine* marks our first official universal release: resilient, dependable, and built to venture across any Raspberry Pi 5 and Compute Module 5 platform.
* **The Twin Suns:** Tatooine's dual suns are reflected in our official branding—one glowing in Linux Mint emerald green, the other in Raspberry/Debian crimson.
* **Dual Artwork Standard:** Every LMPE release features a coordinated artwork duo: an atmospheric Plymouth vector boot splash with boot spinner and a matching, distraction-free desktop wallpaper.

---

## 🚀 Key Features

### 🍃 Complete Linux Mint Cinnamon Desktop & XApps Suite
Includes the complete, uncompromised Linux Mint desktop experience:
* **Cinnamon 6.x Desktop:** Modern composited desktop with Muffin window manager, Slick Greeter display manager, and official Mint-Y themes & icon sets.
* **Full Mint Utilities:** Timeshift (system restore snapshots), MintWelcome, MintStick (USB formatter and ISO writer), MintReport, MintBackup, MintLocale, Bulky (batch file renamer), Folder Color Switcher, Sticky Notes, and Thingy (document organizer).
* **Multimedia & Creativity:** Celluloid (hardware-accelerated media player), Hypnotix (live IPTV streaming), Drawing, and Pix image viewer.
* **System Diagnostics:** GParted partition manager, Baobab disk usage analyzer, Pavucontrol audio manager, Seahorse keyring manager, Btop, and Fastfetch.

### ⚡ Broadcom BCM2712 (Cortex-A76) Microarchitecture Tuning
Packages are compiled natively with advanced ARMv8.2-A compiler flags:
```text
-march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a76 -ftree-vectorize -flto=auto
```
Multimedia engines and mathematical routines (`ffmpeg`, `dav1d`, `libvpx`, `pixman`, `cairo`, `zstd`) utilize `-O3` vectorization, delivering smooth 1080p60 video playback with low CPU overhead.

### 🗄️ Resilient Btrfs Root Filesystem
* Transparent `zstd:2` compression saves up to 40% disk space while doubling random read throughput on NVMe SSDs and MicroSD cards.
* Flash-friendly mount parameters: `defaults,compress=zstd:2,noatime,nodiratime,ssd,discard=async`.
* RAM-backed `/tmp` (`tmpfs`) to prevent unnecessary flash storage writes.
* Automatic first-boot partition expansion (`lmpe-btrfs-resize`) accommodating any drive size.

### 🧠 Pure ZRAM Compressed Memory Architecture
* 4 GB compressed ZRAM swap (`lz4`) with high swap priority (`100`), eliminating slow flash disk swap files and reducing physical memory pressure.
* Aggressive kernel swappiness (`vm.swappiness = 180`) that moves stale memory pages into ZRAM to keep physical RAM available for Btrfs caches and applications.
* Disabled swap readahead (`vm.page-cluster = 0`) to prevent decompression latency spikes.

### 🏎️ High-Throughput Storage Schedulers & Ultra-Fast Boot
* **Direct Hardware Multi-Queue:** NVMe SSDs operate with scheduler `none` and 512KB read-ahead for zero CPU submission overhead.
* **Flash Wear-Leveling:** MicroSD cards and eMMC storage utilize `mq-deadline` with 256KB read-ahead.
* **Rotational Drive Balancing:** External USB mechanical hard drives automatically receive `bfq` (Budget Fair Queueing).
* **Boot-Fsck Bypass:** FAT32 `/boot/firmware` fsck pass is set to `0` in `/etc/fstab`, shaving 250–300 ms off every boot sequence.
* **Blocking Services Masked:** Eliminates stalls by masking `NetworkManager-wait-online.service` and `systemd-networkd-wait-online.service`.

### 🛠️ Developer-Ready System Limits
* Pre-configured `fs.inotify.max_user_watches = 524288` eliminates "System limit for number of file watchers reached" errors when running VS Code, Codium, file synchronizers, or large codebases.
* Pre-tuned `vm.vfs_cache_pressure = 50`, `vm.dirty_background_ratio = 5`, and `vm.dirty_ratio = 10` ensure ultra-fluid desktop responsiveness even during heavy background writes.

### 🌐 High-Performance Networking & APT Engine
* Google TCP BBR congestion control and Fair Queueing (`fq`).
* 4-core Receive Packet Steering (RPS/RFS) spreading network interrupts evenly across all Cortex-A76 cores.
* Consolidated APT configuration (`/etc/apt/apt.conf.d/99-lmpe.conf`) with connection pipelining, host queues, and automatic retry handling.
* Local DNS caching with opportunistic DNS-over-TLS via `systemd-resolved`.

---

## 💻 Hardware Compatibility Matrix

| Device | Status | Architecture | Specifications |
| :--- | :---: | :---: | :--- |
| **Raspberry Pi 5 (4GB / 8GB / 16GB)** | ✅ Full Support | ARMv8.2-A Cortex-A76 | VideoCore VII (OpenGL 3.1, Vulkan 1.3), PCIe 2.0 / 3.0 NVMe, dual 4K60 HDMI. |
| **Raspberry Pi Compute Module 5 (CM5)** | ✅ Full Support | ARMv8.2-A Cortex-A76 | DWC2 USB 2.0 host routing for internal keyboards, trackpads, and carrier IO boards. |
| **Raspberry Pi 500** | ✅ Full Support | ARMv8.2-A Cortex-A76 | Integrated keyboard unit with BCM2712 architecture. |
| **Argon ONE UP Laptop & Modular Enclosures** | ✅ Full Support | ARMv8.2-A Cortex-A76 | Interactive First-Boot setup installs tailored battery monitors, backlight controls, and fan daemon. |
| **Raspberry Pi 4 / 400 / 3 / Zero 2W** | ❌ Incompatible | ARMv8-A Cortex-A72/A53 | **Unsupported.** Lacks ARMv8.2-A, Dot Product, and Crypto instructions (`Illegal instruction` crash). |

---

## 📥 Downloads & Installation

### Option 1: Flash the Pre-Built Image (Recommended)

1. Download the latest bootable release image from **[GitHub Releases](https://github.com/GamingTux/lmde-arm64/releases/latest)**:
   * Image: `image_YYYY-MM-DD-lmpe-arm64-pi5-cinnamon-btrfs.img.xz`
2. Flash the compressed `.img.xz` file directly onto an NVMe SSD or MicroSD card:
   * **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** (*Select "Use Custom"*)
   * **[Balena Etcher](https://etcher.balena.io/)**
   * Command Line (`dd`):
     ```bash
     xz -dc image_*-lmpe-arm64-pi5-cinnamon-btrfs.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
     ```
3. Insert the drive into your Raspberry Pi 5 / CM5 and power on.
4. On first boot:
   * The interactive wizard lets you set your language, keyboard layout, hostname, and optional hardware profiles.
   * The Btrfs root filesystem automatically resizes to fill your entire storage medium.

---

### Option 2: Convert Existing Raspberry Pi OS (Trixie Lite)

If you have an existing minimal installation of **Raspberry Pi OS Lite (64-bit, Debian 13 Trixie)**, convert it to LMPE with a single automated script:

```bash
curl -fsSL https://raw.githubusercontent.com/GamingTux/lmde-arm64/main/setup-pi-lmde.sh | sudo bash
```

After installation completes, reboot into the Cinnamon desktop:
```bash
sudo reboot
```

---

## ⚙️ Architecture Optimization Tiers

Standard multi-arch Debian and Ubuntu ARM64 binaries target an older baseline (`armv8-a`) to maintain compatibility with legacy Raspberry Pi 3 chips.

LMPE compiles packages specifically for the modern **ARMv8.2-A Cortex-A76** core inside the Raspberry Pi 5:

| Optimization Tier | Target Packages | Compiler Flags |
| :--- | :--- | :--- |
| **Tier 0 (`-O3`)**<br>Hotspots & Multimedia | Crypto (`openssl`, `gnutls28`, `nettle`, `libgcrypt20`), Compression (`zstd`, `lz4`, `7zip`, `libarchive`), Graphics & Math (`pixman`, `cairo`, `pango`, `mesa`, `libdrm`, `highway`), Media & DSP (`ffmpeg`, `pipewire`, `opus`, `flac`, `dav1d`, `x264`, `x265`, `mpv`), Python 3.13 | `-march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a76 -ftree-vectorize -O3` |
| **Tier 1 (`-O2`)**<br>Desktop & UI Stack | Cinnamon Desktop, Muffin Window Manager, Nemo File Manager & Plugins, CJS, XApps (`xed`, `xviewer`, `xreader`, `pix`), Slick Greeter | `-march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a76 -ftree-vectorize -flto=auto -ffat-lto-objects -O2` |

Every custom package carries the `+pi5` local version suffix and is cryptographically signed with the LMPE repository GPG key.

---

## 🎛️ APT Repository & Package Priorities

LMPE configures APT pinning to ensure continuous security updates while preserving custom Cortex-A76 performance packages:

```text
/etc/apt/preferences.d/lmde-pi5.pref:

Package: *
Pin: origin "gamingtux.github.io"
Pin-Priority: 1001

Package: *
Pin: origin "archive.raspberrypi.com"
Pin-Priority: 1000

Package: *
Pin: origin "packages.linuxmint.com"
Pin-Priority: 700
```

* **`gamingtux.github.io` (Priority 1001):** Highest priority. Delivers Cortex-A76 recompiled packages (`+pi5`).
* **`archive.raspberrypi.com` (Priority 1000):** Protects the official Raspberry Pi kernel (`linux-image-rpi-2712`), firmware, bootloader, EEPROM, and VideoCore VII GPU drivers.
* **`packages.linuxmint.com` (Priority 700):** Delivers architecture-independent (`Architecture: all`) Linux Mint components (`mintupdate`, `mintinstall`, `mintsources`, Mint-Y themes, icons).

---

## ❓ Frequently Asked Questions (FAQ)

<details>
<summary><b>Can I install software using Flatpak and Flathub?</b></summary>
Yes! Flatpak and Flathub are enabled out of the box in LMPE. You can install apps graphically using the Linux Mint Software Manager (<code>mintinstall</code>) or via the terminal:

```bash
flatpak install flathub <app_name>
```
</details>

<details>
<summary><b>How do I enable PCIe Gen 3 for my NVMe SSD?</b></summary>
The Raspberry Pi 5 PCIe FFC interface defaults to PCIe Gen 2 (5 Gbps) to ensure maximum electrical compatibility across all third-party HATs and flex cables.

If your NVMe HAT and SSD support PCIe Gen 3 (8 Gbps), enable it by adding these options to <code>/boot/firmware/config.txt</code>:

```ini
dtparam=nvme
dtparam=pciex1_gen=3
```

*(Note: On the Argon ONE UP laptop, the First-Boot wizard configures PCIe Gen 3 automatically as part of the hardware profile).*
</details>

<details>
<summary><b>How is video playback (YouTube / streaming) accelerated?</b></summary>
The Broadcom BCM2712 SoC includes dedicated hardware decoding for HEVC/H.265. For modern streaming formats (VP9, AV1, H.264), playback relies on CPU software decoding.

This is where <b>LMPE's Cortex-A76 optimizations excel</b>: multimedia decoders such as <code>dav1d</code> (AV1), <code>libvpx</code> (VP9), and <code>ffmpeg</code> (H.264) are compiled with ARMv8.2-A NEON vectorization and <code>-O3</code>, delivering smooth 1080p60 playback without dropped frames. Mozilla Firefox is pre-configured with <code>rpi-firefox-mods</code> and Widevine DRM (<code>libwidevinecdm0</code>) for Spotify, Netflix, and other DRM platforms.
</details>

<details>
<summary><b>How do I keep LMPE updated?</b></summary>
You can update your system using the graphical Linux Mint Update Manager (<code>mintupdate</code>) in the system tray, or via terminal:

```bash
sudo apt update && sudo apt full-upgrade
```
</details>

<details>
<summary><b>Why is Raspberry Pi 4 / 3 not supported?</b></summary>
LMPE is explicitly compiled for the <b>ARMv8.2-A Cortex-A76 CPU architecture</b>. Older Raspberry Pi models (Pi 4 with Cortex-A72, Pi 3 with Cortex-A53) physically lack ARMv8.2-A, hardware cryptography, and dot product instructions. Running LMPE binaries on these boards will trigger immediate <code>Illegal instruction</code> (SIGILL) crashes.
</details>

---

## 🏷️ Tags & Keywords

`raspberry-pi-5` • `cinnamon-desktop` • `linux-mint` • `lmde` • `arm64` • `compute-module-5` • `cm5` • `bcm2712` • `cortex-a76` • `btrfs` • `zstd` • `zram` • `videocore-vii` • `argon-one-up` • `operating-system` • `debian-13` • `trixie`

---

## ⚖️ License & Community Disclaimer

* **License:** Code and build scripts in this repository are licensed under the [MIT License](LICENSE). Software included in the distribution is licensed under their respective upstream open-source licenses (GPL, LGPL, BSD, MIT).
* **Disclaimer:** *LMPE (Linux Mint Pi Edition)* is an independent, community-driven open source project. It is **not** affiliated with, endorsed by, or sponsored by Linux Mint or Raspberry Pi Ltd. "Linux Mint", "Cinnamon", and "Raspberry Pi" are trademarks of their respective owners.

---

<p align="center">
  <b>Engineered with ❤️ for the Raspberry Pi and Linux Mint communities.</b>
</p>
