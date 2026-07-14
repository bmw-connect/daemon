# carplay-audio on Alpine Linux (Raspberry Pi 4)

Production-oriented port of the Raspbian setup: musl binaries, OpenRC
services, and a pinned kernel/BlueZ pair known to work.

## Why Alpine 3.24 + bluez from edge

LE advertising is broken by a specific kernel/BlueZ combination:

- Kernels **6.18.34–6.18.35** (and 6.12.92–6.12.93, 7.0.11–7.0.12) contain a
  security hardening commit (`d3f7d17960ed`) that rejects the
  `MGMT_OP_ADD_EXT_ADV_DATA` command when userspace sends stray trailing
  bytes. Fixed kernel-side in 6.18.36+ (`149324fc762c`).
- **bluez <= 5.86** sends those stray bytes; **bluez >= 5.87** doesn't
  (bluez commit `2a6968b403`).

Alpine 3.24 ships kernel **6.18.35** (broken window) and bluez **5.86**
(still buggy) — that pair cannot advertise. Either side being fixed is
enough, so `provision.sh` pins **bluez from edge (5.87+)**. No unstable
kernel needed. Once v3.24 ships bluez >= 5.87 or linux-rpi >= 6.18.36, the
`@edgemain` pin in `/etc/apk/repositories` can be removed.

`provision.sh` detects this automatically: if the stable repo ever provides
bluez >= 5.87 it uses that instead of edge.

## Install

1. **Flash Alpine.** Download the `alpine-rpi-3.24.x-aarch64.tar.gz` build
   from <https://alpinelinux.org/downloads/>, extract it onto a FAT32-
   formatted SD card, and boot the Pi with keyboard + screen (or use a UART
   console).

2. **Install to disk (sys mode).** Alpine boots diskless by default; for a
   persistent install run:

   ```sh
   setup-alpine        # answer the prompts; for disk choose "none" for now
   apk add e2fsprogs
   setup-disk -m sys /dev/mmcblk0   # or install to a USB SSD
   reboot
   ```

   Diskless (RAM-only, read-only SD) also works and is attractive in a car —
   but then `/root/.carplay-audio.json` needs `lbu commit` to persist, which
   the daemon does not do. Use sys mode unless you know what you're doing.

3. **Build and deploy from your machine:**

   ```sh
   alpine/build.sh all                    # builds musl binaries via Docker
   alpine/build.sh deploy root@<pi-ip>    # copies binaries + overlay + provision.sh
   ```

4. **Provision on the Pi (as root):**

   ```sh
   sh provision.sh
   ```

   Re-run it whenever configs change; it is idempotent.

5. **Audio output device.** The service reads `/root/.carplay-audio.json`
   (created with defaults on first run). For the Pi 4 analog jack set:

   ```json
   "output_device": "plughw:Headphones"
   ```

   (needs `dtparam=audio=on` in `config.txt` — provision adds it). For a
   HifiBerry keep the default `plughw:sndrpihifiberry` and add
   `dtoverlay=hifiberry-dac` to `config.txt`.

## What provision.sh sets up

| Component | Role | Service |
|---|---|---|
| bluez (edge) | BT stack, LE advertising | `bluetooth` |
| bluetooth-init | power on, alias "BMW E46", discoverable | `bluetooth-init` (oneshot) |
| bluez-alsa | A2DP sink | `bluealsa` |
| bluez-alsa-utils | BT audio → `hw:Loopback,0,1` | `bluealsa-aplay` |
| bt-agent.py | auto-pairing, no PIN | `bt-agent` |
| shairport-sync | AirPlay → `hw:Loopback,0,0` | `shairport-sync` |
| carplay-audio | DSP: loopbacks → DAC/jack, WS + BLE + socket | `carplay-audio` |
| linux-firmware-brcm | WiFi (brcmfmac43455) + BT (BCM4345C0.hcd) firmware | — |
| wpa_supplicant | WiFi client (configure via `setup-interfaces`) | `wpa_supplicant` |

All long-running services run under `supervise-daemon` with auto-respawn
(equivalent of systemd `Restart=`). Logs: `/var/log/carplay-audio.log`,
`/var/log/bt-agent.log`, and syslog for the rest.

## Differences vs the Raspbian setup

- OpenRC instead of systemd — the `.service` files at the repo root are not
  used; the equivalents live in `overlay/etc/init.d/`.
- Binaries must be the **musl** builds from `alpine/build.sh`
  (`target-alpine/release/`); the glibc builds from `./build.sh` will not run.
- `snd_aloop` is loaded via `/etc/modules` + `/etc/modprobe.d/snd-aloop.conf`.
- Settings file: `/root/.carplay-audio.json` (HOME is pinned in the init
  script, as it was in the systemd unit).

## Upgrades (read before `apk upgrade`)

This is an embedded appliance: kernel and BlueZ versions matter (see top of
this file). After any upgrade involving `linux-rpi` or `bluez`, check that
`/var/log/carplay-audio.log` shows `[ble] GATT server active` within 30 s of
boot before putting the SD card back in the car. To freeze the kernel:

```sh
apk add 'linux-rpi=~6.18.35'   # or apk policy linux-rpi to see versions
```
