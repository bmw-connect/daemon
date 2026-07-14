bmw-connect — carplay-audio on Alpine Linux (diskless)
=======================================================

This SD card is fully self-contained. The Pi boots into RAM: nothing is
installed, nothing writes to the card except the settings file. Pull the
power whenever you want.

Configuration (edit on any computer):

  wifi.conf            WiFi credentials (copy wifi.conf.example, edit SSID/psk)
  authorized_keys      SSH public key(s) for root login
  carplay-audio.json   daemon settings, created on first run
                       ("output_device": "plughw:Headphones" = Pi 4 jack,
                        "plughw:sndrpihifiberry" = HifiBerry DAC)
  config.txt           Raspberry Pi boot config
                       (dtparam=audio=on is set; for a HifiBerry, uncomment
                        dtoverlay=hifiberry-dac)

Usage: pair Bluetooth with "BMW E46" (no PIN) or connect via AirPlay.

To persist system-level changes made over SSH: lbu commit
