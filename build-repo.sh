#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"
export DEB_BUILD_PROFILES="nocheck"

# Basis-Architektur-Flags für den BCM2712 (Cortex-A76)
# -ffat-lto-objects stellt sicher, dass statische .a-Archive nach dh_strip ihre Symbole behalten
ARCH_FLAGS="-march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a76 -ftree-vectorize"
LTO_FLAGS="-flto=auto -ffat-lto-objects"

ROOT_DIR="$(pwd)"
REPO_DIR="$ROOT_DIR/repo"
PACKAGES_FILE="$REPO_DIR/dists/gigi/main/binary-arm64/Packages"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/tmp/github_step_summary.md}"

mkdir -p "$REPO_DIR/pool/main" "$REPO_DIR/dists/gigi/main/binary-arm64"
rm -f "$ROOT_DIR/.build_failed"

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

TOTAL="$(grep -vE '^\s*(#|$)' "$ROOT_DIR/packages.txt" | wc -l | xargs)"
CURRENT=0
BUILD_FAILED=0
PENDING_DELTA_DEBS=()

{
  echo "## 🛠️ LMPE ARM64 (Cortex-A76) Build-Dashboard"
  echo ""
  echo "| # | Paket | Version | Optimierung | Status | Dauer |"
  echo "|---|---|---|---|---|---|"
} >> "$SUMMARY_FILE"

while IFS= read -r -u 3 line || [[ -n "$line" ]]; do
  # Kommentare und Leerzeilen ignorieren
  line="${line%%#*}"
  pkg="$(echo "$line" | xargs)"
  [[ -z "$pkg" ]] && continue

  CURRENT=$((CURRENT + 1))
  PKG_START_TIME="$(date +%s)"
  LOG_FILE="/tmp/build-${pkg}.log"
  : > "$LOG_FILE"

  # 1. Optimierungsstufe setzen (-O3 für Stufe 0, -O2 für Stufe 1)
  case "$pkg" in
    zlib|lz4|zstd|xz-utils|bzip2|7zip|nettle|gnutls28|openssl|pixman|libpng1.6|libjpeg-turbo|libwebp|freetype|harfbuzz|cairo|gdk-pixbuf|pango1.0|libdrm|mesa|babl|gegl|sqlite3|opus|flac|libvorbis|lame|dav1d|libvpx|x264|x265|libde265|openh264|pipewire|ffmpeg|mpv|vlc|python3.13)
      OPT_LEVEL="-O3"
      ;;
    *)
      OPT_LEVEL="-O2"
      ;;
  esac

  # Große Pakete mit eigenem Assembler-/Symbol-Versioning ohne erzwungenes LTO im Linker bauen
  case "$pkg" in
    openssl|mesa|pipewire|ffmpeg|vlc|python3.13)
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

  if [[ -z "$UPSTREAM_VER" ]]; then
    DURATION=$(( $(date +%s) - PKG_START_TIME ))
    echo "[$(date -u '+%H:%M:%S')] ❌ [$CURRENT/$TOTAL] Konnte Upstream-Version für $pkg ($QUERY_PKG) nicht ermitteln!"
    echo "| $CURRENT/$TOTAL | \`$pkg\` | \`n/a\` | \`$OPT_LEVEL\` | ❌ Fehler | ${DURATION}s |" >> "$SUMMARY_FILE"
    BUILD_FAILED=1
    break
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

  # 4. Delta-Build-Treffer: Kompilieren überspringen (.deb-Pakete vormerken, falls ein Folgepaket neu gebaut werden muss)
  if [[ "$DELTA_HIT" -eq 1 ]]; then
    PENDING_DELTA_DEBS+=("${EXISTING_DEBS[@]}")
    DURATION=$(( $(date +%s) - PKG_START_TIME ))
    echo "[$(date -u '+%H:%M:%S')] ⏭️ [$CURRENT/$TOTAL] $pkg übersprungen (bereits aktuell im Repo)"
    echo "| $CURRENT/$TOTAL | \`$pkg\` | \`$TARGET_VER\` | \`$OPT_LEVEL\` | ⏭️ Delta-Skip | ${DURATION}s |" >> "$SUMMARY_FILE"
    continue
  fi

  # 5. Neubau nötig (zuvor übersprungene .deb-Abhängigkeiten bei Bedarf jetzt installieren)
  if [[ ${#PENDING_DELTA_DEBS[@]} -gt 0 ]]; then
    dpkg -i "${PENDING_DELTA_DEBS[@]}" < /dev/null >> "$LOG_FILE" 2>&1 || apt-get install -f -y < /dev/null >> "$LOG_FILE" 2>&1
    PENDING_DELTA_DEBS=()
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

    # Falls <pkg> == mint-info-gigi: Patche debian/control
    if [[ "$pkg" == "mint-info-gigi" ]]; then
      sed -i 's/^Architecture:.*amd64.*/Architecture: arm64/' debian/control
    fi

    # Lokales Versions-Suffix +pi5 an den Changelog anhängen
    if ! DEBEMAIL="builder@localhost" DEBFULLNAME="LMPE Builder" dch --force-distribution --local +pi5 --distribution gigi "Compiled for Raspberry Pi 5 Cortex-A76" < /dev/null >> "$LOG_FILE" 2>&1; then
      STEP_OK=0
    else
      sed -i '1s/+pi51)/+pi5)/' debian/changelog
    fi
  fi

  if [[ "$STEP_OK" -eq 1 ]]; then
    if ! (apt-get build-dep -y ./ < /dev/null >> "$LOG_FILE" 2>&1 || apt-get build-dep -y -t trixie-backports ./ < /dev/null >> "$LOG_FILE" 2>&1); then
      STEP_OK=0
    fi
  fi

  # Paket kompilieren mit 60-Sekunden-Heartbeat
  if [[ "$STEP_OK" -eq 1 ]]; then
    dpkg-buildpackage -b -uc -us -j"$(nproc)" < /dev/null >> "$LOG_FILE" 2>&1 &
    BUILD_PID=$!

    (
      ELAPSED=0
      while kill -0 "$BUILD_PID" 2>/dev/null; do
        sleep 60
        if kill -0 "$BUILD_PID" 2>/dev/null; then
          ELAPSED=$((ELAPSED + 60))
          echo "   ⏱️ [$CURRENT/$TOTAL] $pkg kompiliert noch... (${ELAPSED}s)"
        fi
      done
    ) &
    HEARTBEAT_PID=$!

    if wait "$BUILD_PID"; then
      BUILD_RC=0
    else
      BUILD_RC=$?
    fi

    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true

    if [[ "$BUILD_RC" -ne 0 ]]; then
      STEP_OK=0
    fi
  fi

  # Debug-Pakete löschen, .deb-Pakete installieren und in den Pool verschieben
  if [[ "$STEP_OK" -eq 1 ]]; then
    rm -f ../*dbgsym*.deb ../*-dbg_*.deb ../*.ddeb
    if ! (dpkg -i ../*.deb < /dev/null >> "$LOG_FILE" 2>&1 || apt-get install -f -y < /dev/null >> "$LOG_FILE" 2>&1); then
      STEP_OK=0
    else
      mv -f ../*.deb "$REPO_DIR/pool/main/"
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

# Repository-Metadaten generieren und signieren (auch bei Teil-Erfolg / BUILD_FAILED=1!)
cd "$REPO_DIR"

if compgen -G "pool/main/*.deb" > /dev/null; then
  # Debian Trixie t64-Kompatibilität für LMDE-Bibliotheken sicherstellen
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

  echo "[$(date -u '+%H:%M:%S')] 📦 Generiere APT-Repository-Index und GPG-Signaturen..."
  dpkg-scanpackages --arch arm64 pool/ > dists/gigi/main/binary-arm64/Packages 2>/dev/null
  gzip -9c dists/gigi/main/binary-arm64/Packages > dists/gigi/main/binary-arm64/Packages.gz

  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="LMPE" \
    -o APT::FTPArchive::Release::Label="LMPE" \
    -o APT::FTPArchive::Release::Suite="gigi" \
    -o APT::FTPArchive::Release::Codename="gigi" \
    -o APT::FTPArchive::Release::Architectures="arm64" \
    -o APT::FTPArchive::Release::Components="main" \
    release dists/gigi > dists/gigi/Release

  export GNUPGHOME="$(mktemp -d)"
  chmod 700 "$GNUPGHOME"
  echo "$GPG_PRIVATE_KEY" | gpg --batch --yes --import 2>/dev/null

  rm -f dists/gigi/InRelease dists/gigi/Release.gpg lmde-arm64.gpg
  gpg --batch --yes --digest-algo SHA512 --clearsign -o dists/gigi/InRelease dists/gigi/Release
  gpg --batch --yes --digest-algo SHA512 -abs -o dists/gigi/Release.gpg dists/gigi/Release
  gpg --batch --yes --export > lmde-arm64.gpg

  rm -rf "$GNUPGHOME"
  echo "[$(date -u '+%H:%M:%S')] 🔐 APT-Repository erfolgreich signiert."
else
  echo "[$(date -u '+%H:%M:%S')] ⚠️ Keine .deb-Pakete in pool/main vorhanden – überspringe Signierung."
fi

cd "$ROOT_DIR"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "BUILD_FAILED=${BUILD_FAILED}" >> "$GITHUB_ENV"
fi

if [[ "$BUILD_FAILED" -eq 1 ]]; then
  touch "$ROOT_DIR/.build_failed"
  echo "[$(date -u '+%H:%M:%S')] ⚠️ Lauf mit Fehlern beendet (BUILD_FAILED=1). Bisher gebaute Pakete werden als Partial-Deploy gesichert."
else
  echo "[$(date -u '+%H:%M:%S')] 🎉 Alle $TOTAL Pakete erfolgreich verarbeitet!"
fi
