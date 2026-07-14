#!/bin/sh
# provision.sh — Full carplay-audio setup on Alpine Linux (Raspberry Pi 4).
# Run as root from a directory containing: provision.sh, overlay/, carplay-audio.
# Safe to re-run after config changes.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
grep -qi alpine /etc/os-release || { echo "this script targets Alpine Linux"; exit 1; }

echo "========================================"
echo "  carplay-audio Alpine setup"
echo "========================================"

# ---------------------------------------------------------------------------
# 1. APK repositories: community + bluez from edge.
#
# Alpine 3.24 ships kernel 6.18.35, which contains the MGMT strict-length
# regression (fixed upstream in 6.18.36), and bluez 5.86, which still sends
# the extra bytes the strict kernel rejects. Either side being fixed is
# enough: bluez >= 5.87 (edge) no longer sends the extra bytes, so LE
# advertising works on the 6.18.35 kernel. Drop the pin once v3.24 ships
# bluez >= 5.87 or linux-rpi >= 6.18.36.
# ---------------------------------------------------------------------------
echo "[1/7] Configuring APK repositories..."
MIRROR="$(grep -om1 'https\?://[^/]*' /etc/apk/repositories || echo https://dl-cdn.alpinelinux.org)"
VER="$(cut -d. -f1,2 /etc/alpine-release)"

grep -q "^${MIRROR}/alpine/v${VER}/community" /etc/apk/repositories 2>/dev/null || \
    echo "${MIRROR}/alpine/v${VER}/community" >> /etc/apk/repositories
grep -q "^@edgemain " /etc/apk/repositories 2>/dev/null || \
    echo "@edgemain ${MIRROR}/alpine/edge/main" >> /etc/apk/repositories
apk update -q

# ---------------------------------------------------------------------------
# 2. Packages
# ---------------------------------------------------------------------------
echo "[2/7] Installing packages..."
# WiFi + BT firmware for the Pi's CYW43455 (brcmfmac43455 + BCM4345C0.hcd)
apk add -q \
    dbus dbus-libs avahi libgcc \
    alsa-lib alsa-utils \
    linux-firmware-brcm \
    wpa_supplicant wireless-regdb iw \
    shairport-sync \
    bluez-alsa bluez-alsa-utils \
    python3 py3-dbus py3-gobject3

# bluez >= 5.87 from edge (see note above)
if apk version bluez 2>/dev/null | grep -q "^bluez-5.8[7-9]\|^bluez-5.9\|^bluez-6"; then
    apk add -q bluez
else
    apk add -q bluez@edgemain
fi
BLUEZ_VER="$(apk info -d bluez 2>/dev/null | head -1 || true)"
echo "  bluez installed: ${BLUEZ_VER:-unknown}"

# ---------------------------------------------------------------------------
# 3. Kernel modules — ALSA loopback with 2 substreams
# ---------------------------------------------------------------------------
echo "[3/7] Configuring ALSA loopback..."
grep -q '^snd_aloop' /etc/modules || echo snd_aloop >> /etc/modules
# modprobe.d options file comes from the overlay (copied below), install it
# first so the modprobe here picks up pcm_substreams=2
cp "$SCRIPT_DIR/overlay/etc/modprobe.d/snd-aloop.conf" /etc/modprobe.d/
modprobe -r snd_aloop 2>/dev/null || true
modprobe snd_aloop pcm_substreams=2

# ---------------------------------------------------------------------------
# 4. Overlay — configs + OpenRC services + bt-agent
# ---------------------------------------------------------------------------
echo "[4/7] Applying overlay..."
cp -a "$SCRIPT_DIR/overlay/etc/." /etc/
cp "$SCRIPT_DIR/overlay/usr/local/bin/bt-agent.py" /usr/local/bin/bt-agent.py
chmod +x /etc/init.d/carplay-audio /etc/init.d/bluealsa-aplay \
         /etc/init.d/bt-agent /etc/init.d/bluetooth-init \
         /usr/local/bin/bt-agent.py

# ---------------------------------------------------------------------------
# 5. carplay-audio binary (musl build: alpine/build.sh)
# ---------------------------------------------------------------------------
echo "[5/7] Deploying carplay-audio binary..."
if [ -f "$SCRIPT_DIR/carplay-audio" ]; then
    install -m 0755 "$SCRIPT_DIR/carplay-audio" /usr/local/bin/carplay-audio
    echo "  Deployed: /usr/local/bin/carplay-audio"
else
    echo "  WARNING: carplay-audio not found next to provision.sh"
    echo "  Build it with alpine/build.sh and re-run (services stay configured)."
fi

# ---------------------------------------------------------------------------
# 6. Boot config — analog jack needs dtparam=audio=on
# ---------------------------------------------------------------------------
echo "[6/7] Checking boot config..."
BOOTCFG=""
for f in /boot/config.txt /media/mmcblk0p1/config.txt; do
    [ -f "$f" ] && BOOTCFG="$f" && break
done
if [ -n "$BOOTCFG" ]; then
    if mount | grep -q "$(dirname "$BOOTCFG").*ro[ ,]"; then
        mount -o remount,rw "$(dirname "$BOOTCFG")" 2>/dev/null || true
    fi
    grep -q '^dtparam=audio=on' "$BOOTCFG" 2>/dev/null || {
        echo 'dtparam=audio=on' >> "$BOOTCFG"
        echo "  Added dtparam=audio=on to $BOOTCFG (reboot required for the jack)"
    }
    echo "  For a HifiBerry DAC add: dtoverlay=hifiberry-dac (or hifiberry-dacplus)"
else
    echo "  WARNING: config.txt not found — add 'dtparam=audio=on' manually"
fi

# ---------------------------------------------------------------------------
# 7. Services
# ---------------------------------------------------------------------------
echo "[7/7] Enabling services..."
for svc in dbus avahi-daemon bluetooth bluetooth-init bluealsa bluealsa-aplay \
           bt-agent shairport-sync carplay-audio; do
    rc-update -q add "$svc" default 2>/dev/null || true
done

# Fresh pairing state after (re)setup
if [ -d /var/lib/bluetooth ]; then
    find /var/lib/bluetooth -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
fi

rc-service dbus restart >/dev/null
rc-service avahi-daemon restart >/dev/null
rc-service bluetooth restart >/dev/null
rc-service bluetooth-init restart >/dev/null || true
for svc in bluealsa bluealsa-aplay bt-agent shairport-sync; do
    rc-service "$svc" restart >/dev/null || echo "  WARNING: $svc failed to start"
done
if [ -f /usr/local/bin/carplay-audio ]; then
    rc-service carplay-audio restart >/dev/null || echo "  WARNING: carplay-audio failed to start"
fi

echo ""
echo "========================================"
echo "  Setup complete"
echo "========================================"
echo ""
echo "AirPlay  : connect to 'BMW E46' from any AirPlay device"
echo "Bluetooth: pair with 'BMW E46' — automatic, no PIN"
echo ""
echo "WiFi: if not configured yet, run setup-interfaces or edit"
echo "  /etc/wpa_supplicant/wpa_supplicant.conf, then: rc-update add wpa_supplicant boot"
echo ""
echo "Diagnostics:"
echo "  rc-status"
echo "  tail -f /var/log/carplay-audio.log"
echo "  bluetoothctl show   (advertising must show ActiveInstances >= 1 once a client scans)"
