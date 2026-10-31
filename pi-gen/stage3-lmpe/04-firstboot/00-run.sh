#!/bin/bash -e

install -d -m 755 "${ROOTFS_DIR}/usr/local/sbin" "${ROOTFS_DIR}/etc/systemd/system"

cat << 'EOF' > "${ROOTFS_DIR}/usr/local/sbin/lmpe-firstboot.sh"
#!/bin/bash
set -u

export TERM=linux
export NEWT_COLORS='
root=,blue
window=,lightgray
border=black,lightgray
shadow=,black
title=blue,lightgray
button=white,blue
actbutton=white,red
listbox=black,lightgray
actlistbox=white,blue
textbox=black,lightgray
entry=black,white
'

# Auf sauberes Terminal (tty8) umschalten, damit keine Kernel-Meldungen das Menü stören
if [ -t 0 ]; then
    chvt 8 || true
fi
clear

# --- 1. Tastaturlayout ---
KB_LAYOUT=$(whiptail --title "LMPE First-Boot Setup (1/6) - Tastaturlayout" \
    --menu "Bitte wähle dein Tastaturlayout:" 18 70 8 \
    "de"            "Deutsch (Standard QWERTZ)" \
    "de-nodeadkeys" "Deutsch (ohne Akzenttasten / Deadkeys)" \
    "ch"            "Deutsch (Schweiz)" \
    "at"            "Deutsch (Österreich)" \
    "us"            "Englisch (US QWERTY)" \
    "gb"            "Englisch (UK QWERTY)" \
    "fr"            "Französisch (AZERTY)" \
    3>&1 1>&2 2>&3) || KB_LAYOUT="de"

if [ "$KB_LAYOUT" = "de-nodeadkeys" ]; then
    sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="de"/; s/^XKBVARIANT=.*/XKBVARIANT="nodeadkeys"/' /etc/default/keyboard
    setupcon -k --force 2>/dev/null || true
else
    raspi-config nonint do_change_keyboard "$KB_LAYOUT" 2>/dev/null || true
    setupcon -k --force 2>/dev/null || true
fi

# --- 2. Systemsprache & Zeitzone ---
LOCALE_CHOICE=$(whiptail --title "LMPE First-Boot Setup (2/6) - Sprache & Zeitzone" \
    --menu "Bitte wähle die Systemsprache und Zeitzone:" 16 70 5 \
    "de_DE.UTF-8" "Deutsch (Deutschland) - Europe/Berlin" \
    "de_AT.UTF-8" "Deutsch (Österreich)  - Europe/Vienna" \
    "de_CH.UTF-8" "Deutsch (Schweiz)     - Europe/Zurich" \
    "en_US.UTF-8" "English (USA)         - UTC" \
    "en_GB.UTF-8" "English (UK)          - Europe/London" \
    3>&1 1>&2 2>&3) || LOCALE_CHOICE="de_DE.UTF-8"

case "$LOCALE_CHOICE" in
    de_DE.UTF-8) TZ_CHOICE="Europe/Berlin"; WIFI_CC="DE" ;;
    de_AT.UTF-8) TZ_CHOICE="Europe/Vienna"; WIFI_CC="AT" ;;
    de_CH.UTF-8) TZ_CHOICE="Europe/Zurich"; WIFI_CC="CH" ;;
    en_GB.UTF-8) TZ_CHOICE="Europe/London"; WIFI_CC="GB" ;;
    *)           TZ_CHOICE="UTC";           WIFI_CC="DE" ;;
esac

raspi-config nonint do_change_locale "$LOCALE_CHOICE" 2>/dev/null || true
raspi-config nonint do_change_timezone "$TZ_CHOICE" 2>/dev/null || true
raspi-config nonint do_wifi_country "$WIFI_CC" 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true

# --- 3. Hostname ---
CURRENT_HOST=$(hostname)
while true; do
    NEW_HOST=$(whiptail --title "LMPE First-Boot Setup (3/6) - Hostname" \
        --inputbox "Wie soll dieser Raspberry Pi im Netzwerk heißen (Hostname)?" 12 70 "${CURRENT_HOST:-lmpe-pi5}" \
        3>&1 1>&2 2>&3) || NEW_HOST="${CURRENT_HOST:-lmpe-pi5}"
    if echo "$NEW_HOST" | grep -Eq '^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$'; then
        raspi-config nonint do_hostname "$NEW_HOST" 2>/dev/null || hostnamectl set-hostname "$NEW_HOST" 2>/dev/null || true
        break
    else
        whiptail --title "Ungültiger Hostname" --msgbox "Der Hostname darf nur aus Buchstaben, Zahlen und Bindestrichen bestehen." 10 65
    fi
done

# --- 4. WLAN-Konfiguration ---
if whiptail --title "LMPE First-Boot Setup (4/6) - WLAN" \
    --yesno "Möchtest du jetzt eine WLAN-Verbindung einrichten?\n(Bei LAN-Kabel oder späterer Einrichtung im Desktop 'Nein' wählen)" 12 70; then
    while true; do
        whiptail --title "WLAN-Suche" --infobox "Suche nach WLAN-Netzwerken..." 8 50
        mapfile -t WIFI_LIST < <(nmcli --terse --fields SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null | awk -F: 'NF>=1 && $1!="" && !seen[$1]++ {printf "%s\n%s%% (%s)\n", $1, $2, $3}')
        if [ "${#WIFI_LIST[@]}" -eq 0 ]; then
            if ! whiptail --title "Keine Netzwerke gefunden" --yesno "Es wurden keine WLAN-Netzwerke gefunden. Erneut suchen?" 10 60; then
                break
            fi
            continue
        fi
        SSID=$(whiptail --title "LMPE First-Boot Setup (4/6) - WLAN auswählen" \
            --menu "Wähle dein WLAN-Netzwerk (Abbrechen zum Überspringen):" 20 75 10 \
            "${WIFI_LIST[@]}" \
            3>&1 1>&2 2>&3) || break

        WIFI_PASS=$(whiptail --title "WLAN-Passwort" \
            --passwordbox "Bitte Passwort für '$SSID' eingeben (leer lassen bei offenem WLAN):" 12 70 \
            3>&1 1>&2 2>&3) || continue

        whiptail --title "WLAN" --infobox "Verbinde mit '$SSID'..." 8 55
        if [ -n "$WIFI_PASS" ]; then
            nmcli device wifi connect "$SSID" password "$WIFI_PASS" >/dev/null 2>&1 && break
        else
            nmcli device wifi connect "$SSID" >/dev/null 2>&1 && break
        fi
        if ! whiptail --title "Verbindung fehlgeschlagen" --yesno "Verbindung mit '$SSID' fehlgeschlagen. Erneut versuchen?" 10 65; then
            break
        fi
    done
fi

# --- 5. Benutzername & Passwort ---
FIRST_USER=$(getent passwd 1000 | cut -d: -f1)
FIRST_USER=${FIRST_USER:-pi}

while true; do
    NEW_USER=$(whiptail --title "LMPE First-Boot Setup (5/6) - Benutzername" \
        --inputbox "Gewünschter Benutzername (Kleinbuchstaben, beginnt mit Buchstabe):" 12 70 "$FIRST_USER" \
        3>&1 1>&2 2>&3) || NEW_USER="$FIRST_USER"
    if echo "$NEW_USER" | grep -Eq '^[a-z][a-z0-9_-]{0,30}$' && [ "$NEW_USER" != "root" ]; then
        break
    else
        whiptail --title "Ungültiger Benutzername" --msgbox "Bitte nur Kleinbuchstaben, Zahlen, '-' oder '_' verwenden (mind. 1 Zeichen, nicht 'root')." 10 70
    fi
done

while true; do
    PASS1=$(whiptail --title "LMPE First-Boot Setup (5/6) - Passwort" \
        --passwordbox "Bitte neues Passwort für '$NEW_USER' eingeben:" 12 70 \
        3>&1 1>&2 2>&3) || continue
    if [ -z "$PASS1" ]; then
        whiptail --title "Fehler" --msgbox "Das Passwort darf nicht leer sein." 10 50
        continue
    fi
    PASS2=$(whiptail --title "LMPE First-Boot Setup (5/6) - Passwort bestätigen" \
        --passwordbox "Bitte das Passwort zur Bestätigung erneut eingeben:" 12 70 \
        3>&1 1>&2 2>&3) || continue
    if [ "$PASS1" != "$PASS2" ]; then
        whiptail --title "Fehler" --msgbox "Die Passwörter stimmen nicht überein. Bitte erneut eingeben." 10 65
        continue
    fi
    break
done

if [ "$NEW_USER" != "$FIRST_USER" ] && getent passwd "$FIRST_USER" >/dev/null; then
    usermod -l "$NEW_USER" -d "/home/$NEW_USER" -m "$FIRST_USER" 2>/dev/null || true
    groupmod -n "$NEW_USER" "$FIRST_USER" 2>/dev/null || true
    if [ -f /etc/sudoers.d/010_pi-nopasswd ]; then
        sed -i "s/^${FIRST_USER}\b/${NEW_USER}/" /etc/sudoers.d/010_pi-nopasswd 2>/dev/null || true
    fi
fi
echo "${NEW_USER}:${PASS1}" | chpasswd

# --- 6. Standard-Sitzung (X11 vs. Wayland) ---
SESSION_CHOICE=$(whiptail --title "LMPE First-Boot Setup (6/6) - Desktop-Sitzung" \
    --menu "Welche Cinnamon-Sitzung soll standardmäßig starten?\n(Kann später jederzeit oben rechts im Login-Bildschirm gewechselt werden)" 16 75 2 \
    "cinnamon"         "Cinnamon auf X11 (Empfohlen - Maximal stabil)" \
    "cinnamon-wayland" "Cinnamon auf Wayland (Experimentell - Kein Tearing, geringerer Lag)" \
    3>&1 1>&2 2>&3) || SESSION_CHOICE="cinnamon"

mkdir -p /etc/lightdm/lightdm.conf.d
cat << LCONF > /etc/lightdm/lightdm.conf.d/90-slick-greeter.conf
[Seat:*]
greeter-session=slick-greeter
user-session=${SESSION_CHOICE}
greeter-hide-users=false
LCONF

# Auch das X11-Tastaturlayout für LightDM / Cinnamon synchronisieren
localectl set-x11-keymap "${KB_LAYOUT%%-*}" pc105 "${KB_LAYOUT#*-}" 2>/dev/null || true

# First-Boot-Service deaktivieren, damit er nur beim allerersten Start läuft
systemctl disable lmpe-firstboot.service 2>/dev/null || true
sync

if [ -t 0 ]; then
    chvt 1 || true
fi
exit 0
EOF
chmod 755 "${ROOTFS_DIR}/usr/local/sbin/lmpe-firstboot.sh"

cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/system/lmpe-firstboot.service"
[Unit]
Description=LMPE Interactive TTY First-Boot Configuration Wizard
After=systemd-user-sessions.service NetworkManager.service lmpe-btrfs-resize.service
Before=lightdm.service display-manager.service getty@tty1.service
ConditionPathExists=/usr/local/sbin/lmpe-firstboot.sh

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lmpe-firstboot.sh
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty8
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

on_chroot <<- \EOF
	apt-get purge -y cloud-init rpi-cloud-init-mods rpi-connect-lite rpi-keyboard-config rpi-keyboard-fw-update rpi-usb-gadget rpicam-apps-lite rpi-update libpam-chksshpwd userconf-pi 2>/dev/null || true
	apt-get autoremove -y --purge 2>/dev/null || true
	systemctl enable lmpe-firstboot.service
EOF
