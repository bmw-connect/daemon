#!/bin/sh
# mkimage.sh — Build a fully plug-and-play SD card image for the Pi 4.
# Runs INSIDE an alpine:3.24 aarch64 container (see alpine/build.sh overlay).
#
# The image boots Alpine in diskless mode: the whole system is assembled in
# RAM at every boot from the apk cache on the FAT partition, the apkovl
# applies our configs + the carplay-audio binary, and nothing ever writes to
# the SD card except the daemon settings file. Fully offline.
set -eu

MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org}"
BRANCH=v3.24
ARCH=aarch64
BUILD=/build
OUT="$BUILD/target-alpine"
SD="$OUT/sdcard"
DL="$OUT/dl"
BIN="$OUT/release/carplay-audio"
IMG="$OUT/bmw-connect-alpine.img"

[ -f "$BIN" ] || { echo "ERROR: $BIN missing — run alpine/build.sh build first"; exit 1; }

echo "[1/6] Tooling..."
apk add -q --no-progress mtools dosfstools sfdisk

echo "[2/6] Fetching Alpine RPi release..."
mkdir -p "$DL"
wget -q -O "$DL/latest-releases.yaml" \
    "$MIRROR/alpine/$BRANCH/releases/$ARCH/latest-releases.yaml"
TARBALL=$(awk '/file: alpine-rpi-.*\.tar\.gz$/ {print $2; exit}' "$DL/latest-releases.yaml")
[ -n "$TARBALL" ] || { echo "ERROR: no alpine-rpi tarball in latest-releases.yaml"; exit 1; }
echo "  $TARBALL"
[ -f "$DL/$TARBALL" ] || wget -q -O "$DL/$TARBALL" \
    "$MIRROR/alpine/$BRANCH/releases/$ARCH/$TARBALL"

rm -rf "$SD"
mkdir -p "$SD"
tar xzf "$DL/$TARBALL" -C "$SD"

echo "[3/6] Populating offline apk cache (incl. bluez >= 5.87 from edge)..."
REPOS="$OUT/repositories.img"
cat > "$REPOS" <<EOF
$MIRROR/alpine/$BRANCH/main
$MIRROR/alpine/$BRANCH/community
@edgemain $MIRROR/alpine/edge/main
EOF

mkdir -p "$SD/cache"
ROOT=$(mktemp -d)
mkdir -p "$ROOT/etc/apk"
cp -r /etc/apk/keys "$ROOT/etc/apk/keys"

# Installing into a throwaway root with --cache-dir downloads every package
# AND the signed repo indexes into the cache — exactly what the diskless
# initramfs needs to install the world offline at boot.
apk add --root "$ROOT" --initdb --no-progress \
    --repositories-file "$REPOS" \
    --cache-dir "$SD/cache" --update-cache \
    alpine-base busybox-mdev-openrc openssh chrony \
    dbus dbus-libs avahi libgcc alsa-lib alsa-utils \
    linux-firmware-brcm wpa_supplicant wireless-regdb iw \
    shairport-sync bluez-alsa bluez-alsa-utils \
    python3 py3-dbus py3-gobject3 \
    bluez@edgemain

BLUEZ=$(awk -F: '$1 == "P" && $2 == "bluez" {found = 1} found && $1 == "V" {print $2; exit}' \
    "$ROOT/lib/apk/db/installed")
case "$BLUEZ" in
    5.8[7-9]*|5.9*|6*) echo "  bluez-$BLUEZ (>= 5.87, LE advertising OK)" ;;
    *) echo "ERROR: expected bluez >= 5.87 from edge, got '$BLUEZ'"; exit 1 ;;
esac
ls "$SD/cache" | grep -q "^APKINDEX" || { echo "ERROR: no APKINDEX in cache"; exit 1; }

echo "[4/6] Building apkovl..."
OVL=$(mktemp -d)
cp -a "$BUILD/alpine/overlay/." "$OVL/"
cp -a "$BUILD/alpine/image/etc/." "$OVL/etc/"
install -m 0755 "$BIN" "$OVL/usr/local/bin/carplay-audio"
chmod 0755 "$OVL"/etc/init.d/* "$OVL/usr/local/bin/bt-agent.py"

echo bmw-connect > "$OVL/etc/hostname"
mkdir -p "$OVL/etc/apk"
cp "$REPOS" "$OVL/etc/apk/repositories"
cp "$ROOT/etc/apk/world" "$OVL/etc/apk/world"
ln -sf /media/mmcblk0p1/cache "$OVL/etc/apk/cache"

printf 'af_packet\nsnd_aloop\n' > "$OVL/etc/modules"
mkdir -p "$OVL/etc/lbu"
echo 'LBU_MEDIA=mmcblk0p1' > "$OVL/etc/lbu/lbu.conf"

rl() {
    lvl=$1; shift
    mkdir -p "$OVL/etc/runlevels/$lvl"
    for s in "$@"; do ln -sf "/etc/init.d/$s" "$OVL/etc/runlevels/$lvl/$s"; done
}
rl sysinit devfs dmesg mdev hwdrivers modloop
rl boot modules sysctl hostname bootmisc syslog swclock seedrng \
        media-config wpa_supplicant networking
rl default dbus avahi-daemon bluetooth bluetooth-init bluealsa bluealsa-aplay \
           bt-agent shairport-sync carplay-audio chronyd sshd local
rl shutdown mount-ro killprocs savecache

tar czf "$SD/bmw-connect.apkovl.tar.gz" -C "$OVL" etc usr

echo "[5/6] Boot partition extras..."
if [ -f "$SD/config.txt" ] && ! grep -q '^dtparam=audio=on' "$SD/config.txt"; then
    cat >> "$SD/config.txt" <<'EOF'

# carplay-audio
dtparam=audio=on
# For a HifiBerry DAC, uncomment ONE of:
#dtoverlay=hifiberry-dac
#dtoverlay=hifiberry-dacplus
# Serial console for debugging:
#enable_uart=1
EOF
fi
cp "$BUILD/alpine/image/fat/wifi.conf.example" "$SD/"
cp "$BUILD/alpine/image/fat/SDCARD-README.txt" "$SD/"

echo "[6/6] Building flashable image..."
SIZE_MB=$(du -sm "$SD" | cut -f1)
PART_MB=$((SIZE_MB + 160))
PART="$OUT/.part.img"
rm -f "$PART" "$IMG"
truncate -s "${PART_MB}M" "$PART"
mkfs.vfat -F 32 -n BMWCONNECT "$PART" > /dev/null
mcopy -s -Q -i "$PART" "$SD"/* ::/

truncate -s "$((PART_MB + 2))M" "$IMG"
sfdisk -q "$IMG" <<EOF
label: dos
start=2048, size=$((PART_MB * 2048)), type=c, bootable
EOF
dd if="$PART" of="$IMG" bs=1M seek=1 conv=notrunc status=none
rm -f "$PART"
rm -rf "$ROOT" "$OVL"

echo ""
echo "Done:"
echo "  $IMG ($(du -h "$IMG" | cut -f1)) — flash with dd or Raspberry Pi Imager"
echo "  $SD/ — same content, to copy manually onto a FAT32 card"
