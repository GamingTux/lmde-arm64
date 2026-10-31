# LMPE (`lmde-arm64`) – LMDE 7 ("gigi") für Raspberry Pi 5 / CM5

Vollautomatisches Build-System und signiertes APT-Repository, das den kompletten **LMDE 7 ("gigi", Basis Debian 13 Trixie)** Cinnamon- & XApps-Desktop-Stack sowie zentrale System-Performance-Bibliotheken nativ und hochoptimiert für den **Raspberry Pi 5 / Compute Module 5 (Broadcom BCM2712, ARM Cortex-A76)** kompiliert.

---

## Schnellinstallation (Raspberry Pi OS Lite 64-Bit / Debian 13 Trixie)

Auf einem frisch installierten **Raspberry Pi OS Lite (64-Bit, Trixie)** genügt folgender Einzeiler:

```bash
curl -fsSL https://raw.githubusercontent.com/GamingTux/lmde-arm64/main/setup-pi-lmde.sh | sudo bash
```

Nach Abschluss der Installation das System neu starten:

```bash
sudo reboot
```

---

## Cortex-A76 Hardware-Optimierungen (BCM2712)

Alle Pakete erhalten das lokale Versions-Suffix `+pi5` und werden mit Link-Time Optimization (LTO) sowie automatischer Vektorisierung speziell für die Mikroarchitektur des **ARM Cortex-A76** übersetzt:

- **Basis-Compiler-Flags (`CFLAGS` / `CXXFLAGS`):**
  ```text
  -march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a76 -flto=auto -ftree-vectorize
  ```
- **Linker-Flags (`LDFLAGS`):**
  ```text
  -flto=auto
  ```
- **Stufe 0 – Performance-Hotspots (`-O3`):**
  `pixman`, `zstd`, `libjpeg-turbo`, `dav1d`, `ffmpeg`
- **Stufe 1 – LMDE 7 / Cinnamon 6.8 & XApps Desktop-Stack (`-O2`):**
  `xapp`, `cjs`, `cinnamon-menus`, `cinnamon-desktop`, `muffin`, `cinnamon-settings-daemon`, `cinnamon-control-center`, `cinnamon-screensaver`, `cinnamon-session`, `cinnamon`, `xdg-desktop-portal-xapp`, `nemo` (+ Extensions), `xed`, `xviewer`, `xviewer-plugins`, `xreader`, `pix`, `slick-greeter`, `mint-info-gigi`

---

## Architektur & APT-Pinning

- **`archive.raspberrypi.com` (`Pin-Priority: 1000`):** Schützt den Raspberry-Pi-5-Kernel (`linux-image-rpi-2712`), Bootloader/Firmware sowie die für die **VideoCore VII GPU** gepatchten `mesa`- und `libdrm`-Pakete vor dem Überschreiben.
- **`https://GamingTux.github.io/lmde-arm64` (`Pin-Priority: 700`):** Liefert die nativ für `arm64` (Cortex-A76) gebauten Binärpakete (`+pi5`).
- **`http://packages.linuxmint.com` (`Pin-Priority: 700`):** Liefert alle architekturunabhängigen (`Architecture: all`) LMDE-7-Pakete wie `mintupdate`, `mintinstall`, `mintsources`, `mint-themes`, `mint-y-icons` und Sprachpakete.
