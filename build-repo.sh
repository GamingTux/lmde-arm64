#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"

# Basis-Architektur-Flags für den BCM2712 (Cortex-A76)
BASE_FLAGS="-march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a76 -flto=auto -ftree-vectorize"
export DEB_LDFLAGS_MAINT_APPEND="-flto=auto"

ROOT_DIR="$(pwd)"
REPO_DIR="$ROOT_DIR/repo"
PACKAGES_FILE="$REPO_DIR/dists/gigi/main/binary-arm64/Packages"

mkdir -p "$REPO_DIR/pool/main" "$REPO_DIR/dists/gigi/main/binary-arm64"

while IFS= read -r -u 3 line || [[ -n "$line" ]]; do
  # Kommentare und Leerzeilen ignorieren
  line="${line%%#*}"
  pkg="$(echo "$line" | xargs)"
  [[ -z "$pkg" ]] && continue

  echo "===================================================================="
  echo ">>> Verarbeite Paket: $pkg"
  echo "===================================================================="

  # 1. Optimierungsstufe setzen (-O3 für Stufe 0, -O2 für Stufe 1)
  case "$pkg" in
    pixman|zstd|libjpeg-turbo|dav1d|ffmpeg)
      OPT_LEVEL="-O3"
      ;;
    *)
      OPT_LEVEL="-O2"
      ;;
  esac
  export DEB_CFLAGS_MAINT_APPEND="$BASE_FLAGS $OPT_LEVEL"
  export DEB_CXXFLAGS_MAINT_APPEND="$BASE_FLAGS $OPT_LEVEL"

  # 2. Upstream-Quellversion und Quellpaket-Name ermitteln (höchste verfügbare Version wählen)
  QUERY_PKG="$pkg"
  if [[ -z "$(apt-cache showsrc "$QUERY_PKG" 2>/dev/null | awk '/^Version:/ {print $2; exit}')" && "$pkg" == "mint-info-gigi" ]]; then
    QUERY_PKG="mint-info"
  fi

  UPSTREAM_VER=""
  for v in $(apt-cache showsrc "$QUERY_PKG" | awk '/^Version:/ {print $2}'); do
    if [[ -z "$UPSTREAM_VER" ]] || dpkg --compare-versions "$v" gt "$UPSTREAM_VER"; then
      UPSTREAM_VER="$v"
    fi
  done

  SRC_NAME="$(apt-cache showsrc "$QUERY_PKG" | awk '/^Package:/ {print $2; exit}')"
  [[ -z "$SRC_NAME" ]] && SRC_NAME="$QUERY_PKG"

  if [[ -z "$UPSTREAM_VER" ]]; then
    echo "FEHLER: Konnte Upstream-Version für $pkg ($QUERY_PKG) nicht ermitteln!" >&2
    exit 1
  fi

  TARGET_VER="${UPSTREAM_VER}+pi5"
  echo ">>> Quellpaket: $SRC_NAME | Upstream-Version: $UPSTREAM_VER | Ziel-Version: $TARGET_VER"

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

  # 4. Delta-Build-Treffer: Kompilieren überspringen, aber .deb-Pakete im Container installieren
  if [[ "$DELTA_HIT" -eq 1 ]]; then
    echo ">>> Delta-Build-Treffer für $pkg ($TARGET_VER). Überspringe Neubau und installiere vorhandene .deb-Pakete..."
    dpkg -i "${EXISTING_DEBS[@]}" || apt-get install -f -y
    continue
  fi

  # 5. Neubau nötig
  echo ">>> Baue $pkg ($TARGET_VER) neu..."

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

  # Quellcode in /tmp/build/<pkg> laden
  rm -rf "/tmp/build/$pkg"
  mkdir -p "/tmp/build/$pkg"
  cd "/tmp/build/$pkg"
  apt-get source "${SRC_NAME}=${UPSTREAM_VER}" || apt-get source "$QUERY_PKG"

  SRC_DIR="$(find "/tmp/build/$pkg" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "$SRC_DIR" ]]; then
    echo "FEHLER: Kein Quellverzeichnis für $pkg in /tmp/build/$pkg gefunden!" >&2
    exit 1
  fi
  cd "$SRC_DIR"

  # Falls <pkg> == mint-info-gigi: Patche debian/control
  if [[ "$pkg" == "mint-info-gigi" ]]; then
    sed -i 's/^Architecture:.*amd64.*/Architecture: arm64/' debian/control
  fi

  # Lokales Versions-Suffix +pi5 an den Changelog anhängen (--force-distribution & < /dev/null verhindert interaktiven Prompt)
  DEBEMAIL="builder@localhost" DEBFULLNAME="LMPE Builder" dch --force-distribution --local +pi5 --distribution gigi "Compiled for Raspberry Pi 5 Cortex-A76" < /dev/null
  sed -i '1s/+pi51)/+pi5)/' debian/changelog

  # Build-Abhängigkeiten installieren
  apt-get build-dep -y ./ < /dev/null

  # Paket kompilieren
  dpkg-buildpackage -b -uc -us -j$(nproc) < /dev/null

  # Debug-Pakete löschen
  rm -f ../*dbgsym*.deb ../*-dbg_*.deb ../*.ddeb

  # Frisch gebaute .deb-Pakete direkt im Container installieren und in den Pool verschieben
  dpkg -i ../*.deb < /dev/null || apt-get install -f -y < /dev/null
  mv -f ../*.deb "$REPO_DIR/pool/main/"

  # Build-Verzeichnis aufräumen
  cd "$ROOT_DIR"
  rm -rf "/tmp/build/$pkg"

done 3< "$ROOT_DIR/packages.txt"

# Repository-Metadaten generieren und signieren
cd "$REPO_DIR"

dpkg-scanpackages --arch arm64 pool/ > dists/gigi/main/binary-arm64/Packages
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
echo "$GPG_PRIVATE_KEY" | gpg --batch --yes --import

rm -f dists/gigi/InRelease dists/gigi/Release.gpg lmde-arm64.gpg
gpg --batch --yes --digest-algo SHA512 --clearsign -o dists/gigi/InRelease dists/gigi/Release
gpg --batch --yes --digest-algo SHA512 -abs -o dists/gigi/Release.gpg dists/gigi/Release
gpg --batch --yes --export > lmde-arm64.gpg

rm -rf "$GNUPGHOME"
echo ">>> APT-Repository erfolgreich erstellt und signiert."
