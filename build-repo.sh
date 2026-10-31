#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export FORCE_UNSAFE_CONFIGURE=1
export DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"
export DEB_BUILD_PROFILES="nocheck"

# Basis-Architektur-Flags für den BCM2712 (Cortex-A76)
# -ffat-lto-objects stellt sicher, dass statische .a-Archive nach dh_strip ihre Symbole behalten
ARCH_FLAGS="-march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a76 -ftree-vectorize"
LTO_FLAGS="-flto=auto -ffat-lto-objects"

SCRIPT_START_TIME="$(date +%s)"
# 4h 45m (17100s) Zeitbudget pro GitHub-Actions-Lauf (Sicherheitsabstand zum 6h-Hard-Limit)
MAX_RUN_SECONDS=17100
TIME_LIMIT_REACHED=0

ROOT_DIR="$(pwd)"
REPO_DIR="$ROOT_DIR/repo"
PACKAGES_FILE="$REPO_DIR/dists/gigi/main/binary-arm64/Packages"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/tmp/github_step_summary.md}"

mkdir -p "$REPO_DIR/pool/main" "$REPO_DIR/dists/gigi/main/binary-arm64"
rm -f "$ROOT_DIR/.build_failed"

# Unnötige Dokumentations-, Debug-, Source- und Cross-Compile-Pakete aus bestehendem Pool bereinigen
rm -f "$REPO_DIR"/pool/main/*dbgsym*.deb \
      "$REPO_DIR"/pool/main/*-dbg_*.deb \
      "$REPO_DIR"/pool/main/*.ddeb \
      "$REPO_DIR"/pool/main/*-doc_*.deb \
      "$REPO_DIR"/pool/main/*-docs_*.deb \
      "$REPO_DIR"/pool/main/*-examples_*.deb \
      "$REPO_DIR"/pool/main/*-tests_*.deb \
      "$REPO_DIR"/pool/main/*-source_*.deb \
      "$REPO_DIR"/pool/main/*-mingw-*.deb

# Falls zlib1g-dev oder liblz4-dev aus einem früheren Lauf ohne -ffat-lto-objects leere .a-Archive enthalten, zum Neubau entfernen
for check_dev in "$REPO_DIR"/pool/main/zlib1g-dev_*.deb "$REPO_DIR"/pool/main/liblz4-dev_*.deb; do
  [[ -f "$check_dev" ]] || continue
  tmp_chk="$(mktemp -d)"
  dpkg-deb -x "$check_dev" "$tmp_chk"
  a_file="$(find "$tmp_chk" -name "*.a" | head -n 1)"
  if [[ -n "$a_file" ]] && [[ "$(nm "$a_file" 2>/dev/null | grep -c ' T ' || true)" -eq 0 ]]; then
    echo "🧹 Entferne altes Slim-LTO-Paket $(basename "$check_dev") für sauberen Neubau mit -ffat-lto-objects..."
    rm -f "$REPO_DIR"/pool/main/zlib1g*.deb "$REPO_DIR"/pool/main/libminizip*.deb \
          "$REPO_DIR"/pool/main/liblz4*.deb "$REPO_DIR"/pool/main/lz4_*.deb
  fi
  rm -rf "$tmp_chk"
done

# Lokales APT-Repository aktualisieren, damit apt-get build-dep alle bereits gebauten +pi5 Pakete sauber auflöst
update_local_apt_repo() {
  (
    cd "$REPO_DIR"
    if compgen -G "pool/main/*.deb" > /dev/null; then
      for t64_base in libcinnamon-desktop4 libcvc0 libmuffin0; do
        for deb_file in pool/main/${t64_base}_*.deb; do
          [[ -f "$deb_file" ]] || continue
          if ! dpkg-deb -f "$deb_file" Provides 2>/dev/null | grep -q "${t64_base}t64"; then
            deb_ver="$(dpkg-deb -f "$deb_file" Version)"
            tmp_deb_dir="$(mktemp -d)"
            dpkg-deb -R "$deb_file" "$tmp_deb_dir"
            sed -i "/^Provides:/d; /^Replaces:/d; /^Conflicts:/d" "$tmp_deb_dir/DEBIAN/control"
            cat << EOF >> "$tmp_deb_dir/DEBIAN/control"
Provides: ${t64_base}t64 (= ${deb_ver})
Replaces: ${t64_base}t64
Conflicts: ${t64_base}t64
EOF
            dpkg-deb -b "$tmp_deb_dir" "$deb_file" >/dev/null
            rm -rf "$tmp_deb_dir"
          fi
        done
      done
      dpkg-scanpackages --arch arm64 pool/ > dists/gigi/main/binary-arm64/Packages 2>/dev/null || true
      gzip -9c dists/gigi/main/binary-arm64/Packages > dists/gigi/main/binary-arm64/Packages.gz 2>/dev/null || true
    fi
  )
  echo "deb [trusted=yes] file:${REPO_DIR} gigi main" > /etc/apt/sources.list.d/lmpe-local.list
  apt-get update -o Dir::Etc::sourcelist="sources.list.d/lmpe-local.list" \
                 -o Dir::Etc::sourceparts="-" \
                 -o APT::Get::List-Cleanup="0" >/dev/null 2>&1 || apt-get update >/dev/null 2>&1 || true
}

# Zu Beginn sofort den Index aus allen vorhandenen .deb-Dateien in pool/main synchronisieren
update_local_apt_repo

TOTAL="$(grep -vE '^\s*(#|$)' "$ROOT_DIR/packages.txt" | wc -l | xargs)"
CURRENT=0
BUILD_FAILED=0
ALLOWED_SOURCES=()
FINALIZED=0

finalize_and_sign_repo() {
  [[ "$FINALIZED" -eq 1 ]] && return 0
  FINALIZED=1
  set +e

  # Automatischer Orphan-Cleaner: Lösche verwaiste .deb-Pakete in pool/main, deren Quellpaket aus packages.txt entfernt wurde
  if [[ "$TIME_LIMIT_REACHED" -eq 0 && "$CURRENT" -ge "$TOTAL" && ${#ALLOWED_SOURCES[@]} -gt 0 ]]; then
    declare -A ALLOWED_MAP=()
    for s in "${ALLOWED_SOURCES[@]}"; do
      ALLOWED_MAP["$s"]=1
    done
    for deb in "$REPO_DIR"/pool/main/*.deb; do
      [[ -e "$deb" ]] || continue
      deb_src="$(dpkg-deb -f "$deb" Source 2>/dev/null | awk '{print $1}' || true)"
      deb_pkg="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"
      [[ -z "$deb_src" ]] && deb_src="$deb_pkg"
      if [[ -z "${ALLOWED_MAP[$deb_src]:-}" && -z "${ALLOWED_MAP[$deb_pkg]:-}" ]]; then
        echo "🧹 Orphan-Cleaner: Entferne verwaistes Paket $(basename "$deb") (Quellpaket: $deb_src nicht mehr in packages.txt)"
        rm -f "$deb"
      fi
    done
  fi

  cd "$REPO_DIR"
  if compgen -G "pool/main/*.deb" > /dev/null; then
    update_local_apt_repo

    echo "[$(date -u '+%H:%M:%S')] 📦 Generiere APT-Repository-Index und GPG-Signaturen..."
    apt-ftparchive \
      -o APT::FTPArchive::Release::Origin="LMPE" \
      -o APT::FTPArchive::Release::Label="LMPE" \
      -o APT::FTPArchive::Release::Suite="gigi" \
      -o APT::FTPArchive::Release::Codename="gigi" \
      -o APT::FTPArchive::Release::Architectures="arm64" \
      -o APT::FTPArchive::Release::Components="main" \
      release dists/gigi > dists/gigi/Release

    if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
      export GNUPGHOME="$(mktemp -d)"
      chmod 700 "$GNUPGHOME"
      echo "$GPG_PRIVATE_KEY" | gpg --batch --yes --import 2>/dev/null

      rm -f dists/gigi/InRelease dists/gigi/Release.gpg lmde-arm64.gpg
      gpg --batch --yes --digest-algo SHA512 --clearsign -o dists/gigi/InRelease dists/gigi/Release
      gpg --batch --yes --digest-algo SHA512 -abs -o dists/gigi/Release.gpg dists/gigi/Release
      gpg --batch --yes --export > lmde-arm64.gpg

      rm -rf "$GNUPGHOME"
    fi
    REPO_SIZE_MB="$(du -sm pool/main | awk '{print $1}')"
    echo "[$(date -u '+%H:%M:%S')] 🔐 APT-Repository erfolgreich signiert (Aktuelle Pool-Größe: ${REPO_SIZE_MB} MB / 1000 MB GitHub-Pages-Limit)."
  else
    echo "[$(date -u '+%H:%M:%S')] ⚠️ Keine .deb-Pakete in pool/main vorhanden – überspringe Signierung."
  fi

  cd "$ROOT_DIR"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "BUILD_FAILED=${BUILD_FAILED}" >> "$GITHUB_ENV"
    echo "TIME_LIMIT_REACHED=${TIME_LIMIT_REACHED}" >> "$GITHUB_ENV"
  fi

  if [[ "$BUILD_FAILED" -eq 1 ]]; then
    touch "$ROOT_DIR/.build_failed"
    echo "[$(date -u '+%H:%M:%S')] ⚠️ Lauf mit Fehlern beendet (BUILD_FAILED=1). Bisher gebaute Pakete werden als Partial-Deploy gesichert."
  elif [[ "$TIME_LIMIT_REACHED" -eq 1 ]]; then
    echo "[$(date -u '+%H:%M:%S')] ⏳ Zeitbudget erreicht – bisher gebaute Pakete werden veröffentlicht und Folge-Lauf wird gestartet."
  else
    echo "[$(date -u '+%H:%M:%S')] 🎉 Alle $TOTAL Pakete erfolgreich verarbeitet!"
  fi
}

trap finalize_and_sign_repo EXIT

{
  echo "## 🛠️ LMPE ARM64 (Cortex-A76) Build-Dashboard"
  echo ""
  echo "| # | Paket | Version | Optimierung | Status | Dauer |"
  echo "|---|---|---|---|---|---|"
} >> "$SUMMARY_FILE"

run_dpkg_build_with_heartbeat() {
  local pkg_name="$1"
  local cur_idx="$2"
  local tot_idx="$3"
  local log_f="$4"
  local build_flag="${5:--b}"
  local rc=0

  # GITHUB_ACTIONS und CI im Build-Subprozess entfernen, damit Upstream-Buildskripte (wie re2 setup.py) kein Bazel-CI erzwingen
  env -u GITHUB_ACTIONS -u CI dpkg-buildpackage "$build_flag" -uc -us -j"$(nproc)" < /dev/null >> "$log_f" 2>&1 &
  local b_pid=$!

  (
    local elapsed=0
    while kill -0 "$b_pid" 2>/dev/null; do
      sleep 60
      if kill -0 "$b_pid" 2>/dev/null; then
        elapsed=$((elapsed + 60))
        echo "   ⏱️ [$cur_idx/$tot_idx] $pkg_name kompiliert noch... (${elapsed}s)"
      fi
    done
  ) &
  local hb_pid=$!

  if wait "$b_pid"; then
    rc=0
  else
    rc=$?
  fi

  kill "$hb_pid" 2>/dev/null || true
  wait "$hb_pid" 2>/dev/null || true
  return "$rc"
}

while IFS= read -r -u 3 line || [[ -n "$line" ]]; do
  # Kommentare und Leerzeilen ignorieren
  line="${line%%#*}"
  pkg="$(echo "$line" | xargs)"
  [[ -z "$pkg" ]] && continue

  CURRENT=$((CURRENT + 1))
  PKG_START_TIME="$(date +%s)"
  LOG_FILE="/tmp/build-${pkg}.log"
  : > "$LOG_FILE"

  # 1. Optimierungsstufe setzen (-O2 für Stufe 1 Cinnamon/XApps, -O3 für alle Stufe-0-Pakete)
  case "$pkg" in
    xapp|cjs|cinnamon-menus|cinnamon-desktop|muffin|cinnamon-settings-daemon|cinnamon-control-center|cinnamon-screensaver|cinnamon-session|cinnamon|xdg-desktop-portal-xapp|xreader|nemo|nemo-python|nemo-fileroller|nemo-preview|nemo-share|nemo-emblems|nemo-image-converter|nemo-audio-tab|nemo-compare|nemo-media-columns|xed|xviewer|xviewer-plugins|pix|slick-greeter|mint-info-gigi)
      OPT_LEVEL="-O2"
      ;;
    *)
      OPT_LEVEL="-O3"
      ;;
  esac

  # Große Pakete mit eigenem Assembler-/Rust-/Symbol-Versioning direkt ohne erzwungenes LTO im Linker bauen
  USE_LTO=1
  case "$pkg" in
    libgcrypt20)
      USE_LTO=0
      # libgcrypt20 ersetzt in random/Makefile per sed das erste -O2 durch -O0 für jitterentropy; kein zweites -O3 anhängen
      export DEB_CFLAGS_MAINT_APPEND="$ARCH_FLAGS"
      export DEB_CXXFLAGS_MAINT_APPEND="$ARCH_FLAGS"
      export DEB_LDFLAGS_MAINT_APPEND=""
      ;;
    xz-utils|tar|re2|gmp|libxcrypt|nettle|gnutls28|openssl|jemalloc|highway|icu|glib2.0|mesa|xorg-server|xwayland|librsvg|poppler|aom|svt-av1|jpeg-xl|libplacebo|alsa-lib|pulseaudio|pipewire|wireplumber|gstreamer1.0|gst-plugins-base1.0|gst-plugins-good1.0|gst-plugins-bad1.0|gst-plugins-ugly1.0|gst-libav1.0|ffmpeg|mpv|vlc|gtk+3.0|gtk4|mozjs128|python3.13|btop|imagemagick|ghostscript|gimp|inkscape|audacity)
      USE_LTO=0
      export DEB_CFLAGS_MAINT_APPEND="$ARCH_FLAGS $OPT_LEVEL"
      export DEB_CXXFLAGS_MAINT_APPEND="$ARCH_FLAGS $OPT_LEVEL"
      export DEB_LDFLAGS_MAINT_APPEND=""
      ;;
    *)
      export DEB_CFLAGS_MAINT_APPEND="$ARCH_FLAGS $LTO_FLAGS $OPT_LEVEL"
      export DEB_CXXFLAGS_MAINT_APPEND="$ARCH_FLAGS $LTO_FLAGS $OPT_LEVEL"
      export DEB_LDFLAGS_MAINT_APPEND="$LTO_FLAGS"
      ;;
  esac

  if [[ "$pkg" == "python3.13" ]]; then
    export DEB_BUILD_OPTIONS="nocheck nopgo nobench parallel=$(nproc)"
    export DEB_BUILD_PROFILES="nocheck nopgo"
  else
    export DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"
    export DEB_BUILD_PROFILES="nocheck"
  fi

  # 2. Upstream-Quellversion und Quellpaket-Name ermitteln (höchste verfügbare Version wählen, Backports nur bei +rpt)
  QUERY_PKG="$pkg"
  if [[ -z "$(apt-cache showsrc "$QUERY_PKG" 2>/dev/null | awk '/^Version:/ {print $2; exit}')" && "$pkg" == "mint-info-gigi" ]]; then
    QUERY_PKG="mint-info"
  fi

  UPSTREAM_VER=""
  for v in $(apt-cache showsrc "$QUERY_PKG" 2>/dev/null | awk '/^Version:/ {print $2}'); do
    if [[ "$v" == *"~bpo"* && "$v" != *"rpt"* ]]; then
      continue
    fi
    if [[ -z "$UPSTREAM_VER" ]] || dpkg --compare-versions "$v" gt "$UPSTREAM_VER"; then
      UPSTREAM_VER="$v"
    fi
  done

  SRC_NAME="$(apt-cache showsrc "$QUERY_PKG" 2>/dev/null | awk '/^Package:/ {print $2; exit}')"
  [[ -z "$SRC_NAME" ]] && SRC_NAME="$QUERY_PKG"
  ALLOWED_SOURCES+=("$pkg" "$QUERY_PKG" "$SRC_NAME")

  if [[ -z "$UPSTREAM_VER" ]]; then
    DURATION=$(( $(date +%s) - PKG_START_TIME ))
    echo "[$(date -u '+%H:%M:%S')] ❌ [$CURRENT/$TOTAL] Konnte Upstream-Version für $pkg ($QUERY_PKG) nicht ermitteln!"
    echo "| $CURRENT/$TOTAL | \`$pkg\` | \`n/a\` | \`$OPT_LEVEL\` | ❌ Fehler | ${DURATION}s |" >> "$SUMMARY_FILE"
    BUILD_FAILED=1
    continue
  fi

  TARGET_VER="${UPSTREAM_VER}+pi5"

  # 3. Prüfen, ob im bestehenden Packages-Index bereits <upstream_version>+pi5 existiert
  DELTA_HIT=0
  EXISTING_DEBS=()
  if [[ -s "$PACKAGES_FILE" ]]; then
    if awk -v pkg="$pkg" -v qpkg="$QUERY_PKG" -v src="$SRC_NAME" -v ver="$TARGET_VER" '
      BEGIN { RS=""; FS="\n"; found=0 }
      {
        p=""; s=""; v=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^Package: /) { p = substr($i, 10) }
          else if ($i ~ /^Source: /) { s = substr($i, 9); sub(/ .*/, "", s) }
          else if ($i ~ /^Version: /) { v = substr($i, 10) }
        }
        if (s == "") s = p
        if ((s == pkg || s == qpkg || s == src || p == pkg || p == qpkg) && (v == ver || v == ver "1")) {
          found = 1
          exit 0
        }
      }
      END { exit (found ? 0 : 1) }
    ' "$PACKAGES_FILE"; then
      while IFS= read -r rel_deb; do
        [[ -n "$rel_deb" && -f "$REPO_DIR/$rel_deb" ]] && EXISTING_DEBS+=("$REPO_DIR/$rel_deb")
      done < <(awk -v pkg="$pkg" -v qpkg="$QUERY_PKG" -v src="$SRC_NAME" '
        BEGIN { RS=""; FS="\n" }
        {
          p=""; s=""; fn=""
          for (i=1; i<=NF; i++) {
            if ($i ~ /^Package: /) { p = substr($i, 10) }
            else if ($i ~ /^Source: /) { s = substr($i, 9); sub(/ .*/, "", s) }
            else if ($i ~ /^Filename: /) { fn = substr($i, 11) }
          }
          if (s == "") s = p
          if ((s == pkg || s == qpkg || s == src || p == pkg || p == qpkg) && fn != "") {
            print fn
          }
        }
      ' "$PACKAGES_FILE")

      if [[ ${#EXISTING_DEBS[@]} -gt 0 ]]; then
        DELTA_HIT=1
      fi
    fi
  fi

  # 4. Delta-Build-Treffer: Kompilieren überspringen (Pakete sind bereits über lmpe-local.list für apt-get build-dep verfügbar)
  if [[ "$DELTA_HIT" -eq 1 ]]; then
    DURATION=$(( $(date +%s) - PKG_START_TIME ))
    echo "[$(date -u '+%H:%M:%S')] ⏭️ [$CURRENT/$TOTAL] $pkg übersprungen (bereits aktuell im Repo)"
    echo "| $CURRENT/$TOTAL | \`$pkg\` | \`$TARGET_VER\` | \`$OPT_LEVEL\` | ⏭️ Delta-Skip | ${DURATION}s |" >> "$SUMMARY_FILE"
    continue
  fi

  # 4b. Zeitbudget prüfen, bevor ein neuer Paketbau gestartet wird
  TOTAL_ELAPSED=$(( $(date +%s) - SCRIPT_START_TIME ))
  if [[ "$TOTAL_ELAPSED" -ge "$MAX_RUN_SECONDS" ]]; then
    echo "[$(date -u '+%H:%M:%S')] ⏳ Zeitbudget (${TOTAL_ELAPSED}s / ${MAX_RUN_SECONDS}s) erreicht – sichere bisher gebaute Pakete und setze im Folge-Lauf fort."
    TIME_LIMIT_REACHED=1
    break
  fi

  echo "[$(date -u '+%H:%M:%S')] 🚀 [$CURRENT/$TOTAL] Starte $pkg ($UPSTREAM_VER) [Flags: $OPT_LEVEL]..."

  # Alte .deb-Dateien dieses Quellpakets aus ./repo/pool/main/ löschen
  if [[ -s "$PACKAGES_FILE" ]]; then
    while IFS= read -r old_rel; do
      [[ -n "$old_rel" ]] && rm -f "$REPO_DIR/$old_rel"
    done < <(awk -v pkg="$pkg" -v qpkg="$QUERY_PKG" -v src="$SRC_NAME" '
      BEGIN { RS=""; FS="\n" }
      {
        p=""; s=""; fn=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^Package: /) { p = substr($i, 10) }
          else if ($i ~ /^Source: /) { s = substr($i, 9); sub(/ .*/, "", s) }
          else if ($i ~ /^Filename: /) { fn = substr($i, 11) }
        }
        if (s == "") s = p
        if ((s == pkg || s == qpkg || s == src || p == pkg || p == qpkg) && fn != "") {
          print fn
        }
      }
    ' "$PACKAGES_FILE")
  fi

  for deb in "$REPO_DIR"/pool/main/*.deb; do
    [[ -e "$deb" ]] || continue
    deb_src="$(dpkg-deb -f "$deb" Source 2>/dev/null | awk '{print $1}' || true)"
    deb_pkg="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"
    [[ -z "$deb_src" ]] && deb_src="$deb_pkg"
    if [[ "$deb_src" == "$pkg" || "$deb_src" == "$QUERY_PKG" || "$deb_src" == "$SRC_NAME" || "$deb_pkg" == "$pkg" || "$deb_pkg" == "$QUERY_PKG" ]]; then
      rm -f "$deb"
    fi
  done

  # Quellcode laden, patchen und Build-Abhängigkeiten installieren
  STEP_OK=1
  rm -rf "/tmp/build/$pkg"
  mkdir -p "/tmp/build/$pkg"
  cd "/tmp/build/$pkg"

  if ! (apt-get source "${SRC_NAME}=${UPSTREAM_VER}" < /dev/null >> "$LOG_FILE" 2>&1 || apt-get source "$QUERY_PKG" < /dev/null >> "$LOG_FILE" 2>&1); then
    STEP_OK=0
  fi

  SRC_DIR="$(find "/tmp/build/$pkg" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ "$STEP_OK" -eq 1 && -z "$SRC_DIR" ]]; then
    echo "FEHLER: Kein Quellverzeichnis für $pkg in /tmp/build/$pkg gefunden!" >> "$LOG_FILE"
    STEP_OK=0
  fi

  if [[ "$STEP_OK" -eq 1 ]]; then
    cd "$SRC_DIR"

    # Paket-spezifische Upstream-/Debian-Rules-Quirks beheben
    if [[ "$pkg" == "mint-info-gigi" ]]; then
      sed -i 's/^Architecture:.*amd64.*/Architecture: arm64/' debian/control
    elif [[ "$pkg" == "xz-utils" ]]; then
      sed -i 's/findstring nocheck/findstring nodoc/g' debian/rules || true
    elif [[ "$pkg" == "libgcrypt20" ]]; then
      sed -i 's|-O0 /|-O0 /g|g' random/Makefile.am random/Makefile.in 2>/dev/null || true
    elif [[ "$pkg" == "re2" ]]; then
      sed -i "s|export DEB_CXXFLAGS_MAINT_APPEND=.*|export DEB_CXXFLAGS_MAINT_APPEND=-pthread -Wall -std=c++14 ${ARCH_FLAGS} ${OPT_LEVEL}|" debian/rules || true
    fi

    # Lokales Versions-Suffix +pi5 an den Changelog anhängen
    if ! DEBEMAIL="builder@localhost" DEBFULLNAME="LMPE Builder" dch --force-distribution --local +pi5 --distribution gigi "Compiled for Raspberry Pi 5 Cortex-A76" < /dev/null >> "$LOG_FILE" 2>&1; then
      STEP_OK=0
    else
      sed -i '1s/+pi51)/+pi5)/' debian/changelog
    fi
  fi

  if [[ "$STEP_OK" -eq 1 ]]; then
    if ! (apt-get build-dep -y --allow-downgrades ./ < /dev/null >> "$LOG_FILE" 2>&1 || apt-get build-dep -y --allow-downgrades -t trixie-backports ./ < /dev/null >> "$LOG_FILE" 2>&1); then
      STEP_OK=0
    fi
  fi

  # Paket kompilieren mit 60-Sekunden-Heartbeat (inkl. automatischem Non-LTO- und Binary-Arch-Fallback)
  if [[ "$STEP_OK" -eq 1 ]]; then
    BUILD_MODE="-b"
    [[ "$pkg" == "xz-utils" ]] && BUILD_MODE="-B"
    if ! run_dpkg_build_with_heartbeat "$pkg" "$CURRENT" "$TOTAL" "$LOG_FILE" "$BUILD_MODE"; then
      if [[ "$USE_LTO" -eq 1 ]]; then
        echo "   🔄 [$CURRENT/$TOTAL] LTO-Build für $pkg fehlgeschlagen – wiederhole automatisch ohne LTO (mit $ARCH_FLAGS $OPT_LEVEL)..."
        export DEB_CFLAGS_MAINT_APPEND="$ARCH_FLAGS $OPT_LEVEL"
        export DEB_CXXFLAGS_MAINT_APPEND="$ARCH_FLAGS $OPT_LEVEL"
        export DEB_LDFLAGS_MAINT_APPEND=""
        debian/rules clean < /dev/null >> "$LOG_FILE" 2>&1 || true
        if ! run_dpkg_build_with_heartbeat "$pkg" "$CURRENT" "$TOTAL" "$LOG_FILE" "$BUILD_MODE"; then
          STEP_OK=0
        fi
      else
        echo "   🔄 [$CURRENT/$TOTAL] Build (-b) für $pkg fehlgeschlagen – wiederhole automatisch als Binary-Arch-Only (-B)..."
        debian/rules clean < /dev/null >> "$LOG_FILE" 2>&1 || true
        if ! run_dpkg_build_with_heartbeat "$pkg" "$CURRENT" "$TOTAL" "$LOG_FILE" "-B"; then
          STEP_OK=0
        fi
      fi
    fi
  fi

  # Debug-, Doku-, Test- und Cross-Compile-Ballast löschen, .deb-Pakete direkt in den Pool verschieben und lokalen APT-Index aktualisieren
  if [[ "$STEP_OK" -eq 1 ]]; then
    rm -f ../*dbgsym*.deb \
          ../*-dbg_*.deb \
          ../*.ddeb \
          ../*-doc_*.deb \
          ../*-docs_*.deb \
          ../*-examples_*.deb \
          ../*-tests_*.deb \
          ../*-source_*.deb \
          ../*-mingw-*.deb
    if compgen -G "../*.deb" > /dev/null; then
      mv -f ../*.deb "$REPO_DIR/pool/main/"
      update_local_apt_repo
    else
      STEP_OK=0
    fi
  fi

  cd "$ROOT_DIR"
  rm -rf "/tmp/build/$pkg"
  DURATION=$(( $(date +%s) - PKG_START_TIME ))

  if [[ "$STEP_OK" -ne 1 ]]; then
    echo "[$(date -u '+%H:%M:%S')] ❌ [$CURRENT/$TOTAL] Fehler bei $pkg nach ${DURATION}s! Letzte 100 Zeilen aus $LOG_FILE:"
    echo "--------------------------------------------------------------------"
    tail -n 100 "$LOG_FILE" || true
    echo "--------------------------------------------------------------------"
    echo "| $CURRENT/$TOTAL | \`$pkg\` | \`$TARGET_VER\` | \`$OPT_LEVEL\` | ❌ Fehler | ${DURATION}s |" >> "$SUMMARY_FILE"
    BUILD_FAILED=1
    continue
  fi

  rm -f "$LOG_FILE"
  echo "[$(date -u '+%H:%M:%S')] ✅ [$CURRENT/$TOTAL] $pkg fertig gebaut in ${DURATION}s"
  echo "| $CURRENT/$TOTAL | \`$pkg\` | \`$TARGET_VER\` | \`$OPT_LEVEL\` | ✅ Gebaut | ${DURATION}s |" >> "$SUMMARY_FILE"

done 3< "$ROOT_DIR/packages.txt"
