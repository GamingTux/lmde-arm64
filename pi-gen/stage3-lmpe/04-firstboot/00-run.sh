#!/bin/bash -e

install -d -m 755 "${ROOTFS_DIR}/usr/local/sbin" "${ROOTFS_DIR}/etc/systemd/system" "${ROOTFS_DIR}/etc/systemd/journald.conf.d"

# Persistente systemd-Logs mit Speicherbegrenzung aktivieren
cat << 'JCONF' > "${ROOTFS_DIR}/etc/systemd/journald.conf.d/00-persistent.conf"
[Journal]
Storage=persistent
SystemMaxUse=100M
RuntimeMaxUse=50M
JCONF
install -d -m 2755 "${ROOTFS_DIR}/var/log/journal"

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

# Plymouth für das interaktive First-Boot-Menü beenden
/usr/bin/plymouth quit 2>/dev/null || true
clear

# --- 1. Keyboard Layout ---
KB_LAYOUT=$(whiptail --title "LMPE First-Boot Setup (1/7) - Keyboard Layout" \
    --menu "Please select your keyboard layout:" 18 70 8 \
    "us"            "English (US QWERTY)" \
    "gb"            "English (UK QWERTY)" \
    "de"            "German (Standard QWERTZ)" \
    "de-nodeadkeys" "German (No dead keys)" \
    "ch"            "German (Switzerland)" \
    "at"            "German (Austria)" \
    "fr"            "French (AZERTY)" \
    "es"            "Spanish" \
    3>&1 1>&2 2>&3) || KB_LAYOUT="us"

if [ "$KB_LAYOUT" = "de-nodeadkeys" ]; then
    sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="de"/; s/^XKBVARIANT=.*/XKBVARIANT="nodeadkeys"/' /etc/default/keyboard
else
    raspi-config nonint do_change_keyboard "$KB_LAYOUT" 2>/dev/null || true
fi
setupcon -k --force /dev/tty1 2>/dev/null || true

whiptail --title "LMPE First-Boot Setup (1/7) - Keyboard Test" \
    --inputbox "Keyboard layout applied. You can test typing here (e.g. Z, Y, @, ?, -, _):\n(Select 'OK' or press Enter to continue)" 12 70 "" 3>&1 1>&2 2>&3 || true

# --- 2. System Language & Timezone ---
LOCALE_CHOICE=$(whiptail --title "LMPE First-Boot Setup (2/7) - Language & Timezone" \
    --menu "Please select your system language and timezone:" 16 70 6 \
    "en_US.UTF-8" "English (US)      - UTC" \
    "en_GB.UTF-8" "English (UK)      - Europe/London" \
    "de_DE.UTF-8" "German (Germany)  - Europe/Berlin" \
    "de_AT.UTF-8" "German (Austria)  - Europe/Vienna" \
    "de_CH.UTF-8" "German (Swiss)    - Europe/Zurich" \
    "fr_FR.UTF-8" "French (France)   - Europe/Paris" \
    3>&1 1>&2 2>&3) || LOCALE_CHOICE="en_US.UTF-8"

case "$LOCALE_CHOICE" in
    en_GB.UTF-8) TZ_CHOICE="Europe/London"; WIFI_CC="GB" ;;
    de_DE.UTF-8) TZ_CHOICE="Europe/Berlin"; WIFI_CC="DE" ;;
    de_AT.UTF-8) TZ_CHOICE="Europe/Vienna"; WIFI_CC="AT" ;;
    de_CH.UTF-8) TZ_CHOICE="Europe/Zurich"; WIFI_CC="CH" ;;
    fr_FR.UTF-8) TZ_CHOICE="Europe/Paris";  WIFI_CC="FR" ;;
    *)           TZ_CHOICE="UTC";           WIFI_CC="US" ;;
esac

raspi-config nonint do_change_locale "$LOCALE_CHOICE" 2>/dev/null || true
raspi-config nonint do_change_timezone "$TZ_CHOICE" 2>/dev/null || true
raspi-config nonint do_wifi_country "$WIFI_CC" 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true

# --- 3. Hostname ---
CURRENT_HOST=$(hostname)
while true; do
    NEW_HOST=$(whiptail --title "LMPE First-Boot Setup (3/7) - Hostname" \
        --inputbox "Enter a network name (hostname) for this Raspberry Pi:" 12 70 "${CURRENT_HOST:-lmpe-pi5}" \
        3>&1 1>&2 2>&3) || NEW_HOST="${CURRENT_HOST:-lmpe-pi5}"
    if echo "$NEW_HOST" | grep -Eq '^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$'; then
        raspi-config nonint do_hostname "$NEW_HOST" 2>/dev/null || hostnamectl set-hostname "$NEW_HOST" 2>/dev/null || true
        break
    else
        whiptail --title "Invalid Hostname" --msgbox "The hostname may only contain letters, numbers, and hyphens." 10 65
    fi
done

# --- 4. Wi-Fi Configuration ---
if whiptail --title "LMPE First-Boot Setup (4/7) - Wi-Fi Setup" \
    --yesno "Would you like to connect to a Wi-Fi network now?\n(Select 'No' if using Ethernet or if you wish to configure Wi-Fi later in the desktop)" 12 70; then
    while true; do
        whiptail --title "Wi-Fi Scan" --infobox "Scanning for Wi-Fi networks..." 8 50
        mapfile -t WIFI_LIST < <(nmcli --terse --fields SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null | awk -F: 'NF>=1 && $1!="" && !seen[$1]++ {printf "%s\n%s%% (%s)\n", $1, $2, $3}')
        if [ "${#WIFI_LIST[@]}" -eq 0 ]; then
            if ! whiptail --title "No Networks Found" --yesno "No Wi-Fi networks were detected. Scan again?" 10 60; then
                break
            fi
            continue
        fi
        SSID=$(whiptail --title "LMPE First-Boot Setup (4/7) - Select Wi-Fi" \
            --menu "Choose your Wi-Fi network (Cancel to skip):" 20 75 10 \
            "${WIFI_LIST[@]}" \
            3>&1 1>&2 2>&3) || break

        PASS_MODE=$(whiptail --title "LMPE First-Boot Setup (4/7) - Password Input" \
            --menu "How would you like to enter the Wi-Fi password for '$SSID'?" 13 65 2 \
            "visible" "Show in plain text (Recommended to prevent typos)" \
            "hidden"  "Mask with asterisks (*)" \
            3>&1 1>&2 2>&3) || PASS_MODE="visible"

        if [ "$PASS_MODE" = "visible" ]; then
            WIFI_PASS=$(whiptail --title "Wi-Fi Password for '$SSID'" \
                --inputbox "Enter password for '$SSID' (leave empty for open networks):" 12 70 \
                3>&1 1>&2 2>&3) || continue
        else
            WIFI_PASS=$(whiptail --title "Wi-Fi Password for '$SSID'" \
                --passwordbox "Enter password for '$SSID' (leave empty for open networks):" 12 70 \
                3>&1 1>&2 2>&3) || continue
        fi

        whiptail --title "Wi-Fi" --infobox "Connecting to '$SSID'..." 8 55
        if [ -n "$WIFI_PASS" ]; then
            CONNECT_OUT=$(nmcli device wifi connect "$SSID" password "$WIFI_PASS" 2>&1)
            RES=$?
        else
            CONNECT_OUT=$(nmcli device wifi connect "$SSID" 2>&1)
            RES=$?
        fi

        if [ $RES -eq 0 ]; then
            whiptail --title "Wi-Fi Connected" --msgbox "Successfully connected to '$SSID'!" 10 60
            break
        else
            whiptail --title "Connection Failed" --yesno "Failed to connect:\n\n$CONNECT_OUT\n\nTry again?" 15 70 || break
        fi
    done
fi

# --- 5. Username & Password ---
FIRST_USER=$(getent passwd 1000 | cut -d: -f1)
FIRST_USER=${FIRST_USER:-pi}

while true; do
    NEW_USER=$(whiptail --title "LMPE First-Boot Setup (5/7) - Username" \
        --inputbox "Desired username (lowercase letters, numbers; starts with a letter):" 12 70 "$FIRST_USER" \
        3>&1 1>&2 2>&3) || NEW_USER="$FIRST_USER"
    if echo "$NEW_USER" | grep -Eq '^[a-z][a-z0-9_-]{0,30}$' && [ "$NEW_USER" != "root" ]; then
        break
    else
        whiptail --title "Invalid Username" --msgbox "Please use lowercase letters, numbers, '-' or '_' (minimum 1 character, not 'root')." 10 70
    fi
done

while true; do
    PASS1=$(whiptail --title "LMPE First-Boot Setup (5/7) - Password" \
        --passwordbox "Enter new password for user '$NEW_USER':" 12 70 \
        3>&1 1>&2 2>&3) || continue
    if [ -z "$PASS1" ]; then
        whiptail --title "Error" --msgbox "The password cannot be empty." 10 50
        continue
    fi
    PASS2=$(whiptail --title "LMPE First-Boot Setup (5/7) - Confirm Password" \
        --passwordbox "Please re-enter the password to confirm:" 12 70 \
        3>&1 1>&2 2>&3) || continue
    if [ "$PASS1" != "$PASS2" ]; then
        whiptail --title "Error" --msgbox "Passwords do not match. Please try again." 10 65
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

# --- 6. Hardware Platform Profile (Standard Pi vs. Argon ONE UP) ---
HW_CHOICE=$(whiptail --title "LMPE First-Boot Setup (6/7) - Hardware Profile" \
    --menu "Please select the hardware profile for this system:" 14 70 2 \
    "generic" "Standard Raspberry Pi 5 / Compute Module 5 (Universal)" \
    "argon"   "Argon ONE UP Laptop (Display backlight, battery & fan drivers)" \
    3>&1 1>&2 2>&3) || HW_CHOICE="generic"

if [ "$HW_CHOICE" = "argon" ]; then
    whiptail --title "Hardware Setup" --infobox "Installing Argon ONE UP hardware packages and drivers..." 8 65
    if compgen -G "/usr/share/argon-debs/*.deb" >/dev/null; then
        dpkg -i --force-confnew /usr/share/argon-debs/*.deb 2>/dev/null || apt-get install -fy 2>/dev/null || true
    fi
    whiptail --title "Hardware Profile" --msgbox "Argon ONE UP hardware profile enabled successfully!" 10 55
else
    # Remove staging debs on generic hardware
    rm -rf /usr/share/argon-debs
    whiptail --title "Hardware Profile" --msgbox "Standard Raspberry Pi 5 / Compute Module 5 profile active." 10 65
fi

# --- 7. Default Desktop Session (X11 vs. Wayland) ---
SESSION_CHOICE=$(whiptail --title "LMPE First-Boot Setup (7/7) - Desktop Session" \
    --menu "Choose the default Cinnamon desktop display session:\n(You can switch sessions anytime on the login screen)" 16 75 2 \
    "cinnamon"         "Cinnamon on X11 (Recommended - Maximum stability)" \
    "cinnamon-wayland" "Cinnamon on Wayland (Experimental - Tear-free rendering)" \
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
TTYPath=/dev/tty1
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
	chown root:systemd-journal /var/log/journal 2>/dev/null || true
	systemctl enable lmpe-firstboot.service
EOF
