# GlassIn

Native Raspberry Pi client for **[GlassOut](https://glassout.flyingart.dev/)** panel
streams: connects to the GlassOut engine over WebSocket, decodes the panel JPEGs and
shows them fullscreen (single panel or template layout), including touch input. Runs
as an appliance on Raspberry Pi OS Lite (no desktop, output straight to the framebuffer
via KMSDRM).

GlassOut (the engine that produces the panel streams): <https://glassout.flyingart.dev/>

> This repository hosts the **releases** (prebuilt packages). Devices update themselves
> from their configuration page (**Software** card) and automatically download the
> package that matches their architecture.

## Which package do I need?

The on-device updater picks the right asset **automatically** based on `uname -m`.
For manual installation the asset must contain **exactly** the device's `uname -m` value:

| `uname -m` | typical models | Asset |
|---|---|---|
| `armv6l`  | Pi Zero, Pi Zero W, Pi 1 (32-bit OS) | `glassin-armv6l.tar.gz` |
| `armv7l`  | Pi 2 / 3 / Zero 2 W (32-bit OS)       | `glassin-armv7l.tar.gz` |
| `aarch64` | Pi Zero 2 W / 3 / 4 / 5 (64-bit OS)   | `glassin-aarch64.tar.gz` |

Check the architecture on the Pi:

```bash
uname -m
```

**Note:** a release only contains the assets it was built for (packages are built on a
Pi of the matching architecture). If your asset is missing from a release, that release
isn't available for your model (yet) — pick the most recent release that includes it.

## First-time installation

Starting point: a fresh **Raspberry Pi OS Lite** image (no desktop) that you reach
over SSH. One command does everything — runtime dependencies, the release package for
your architecture, the systemd services (the client runs under your login user), and a
clean appliance boot (no boot messages, no rainbow splash or logos, no console cursor,
no login prompt):

```bash
curl -fsSL https://raw.githubusercontent.com/torben-erz/glassin/master/install.sh | sudo bash
```

**Reboot once** afterwards so the clean-boot settings take effect (`sudo reboot`).

Then open **`http://<pi-hostname>.local/`** in a browser — use the same hostname you
SSH to (a fresh image keeps its imaged name; you can rename it on the config page).
Set the GlassOut engine host/port and choose a panel or template. Until the client
connects and a flight is active, the screen shows **BOOTING**.

The installer also enables **AP-mode onboarding** — see [Wi-Fi setup via the access point](#wi-fi-setup-via-the-access-point-ap-mode)
below. You still need a network for this first install (Ethernet, or Wi-Fi set in Raspberry Pi
Imager) so the installer can run over SSH.

<details>
<summary>What the script does (equivalent manual steps)</summary>

```bash
# 1) Runtime dependencies (dnsmasq-base = setup-AP DHCP/DNS; gpiozero/lgpio = reset button)
sudo apt update
sudo apt install -y libwebsockets-dev libturbojpeg0-dev libsdl2-dev \
    libsdl2-ttf-dev libcjson-dev fonts-dejavu-core dnsmasq-base \
    python3-gpiozero python3-lgpio

# 2) Download + verify the package for this architecture
ARCH=$(uname -m)
BASE=https://github.com/torben-erz/glassin/releases/latest/download
curl -LO $BASE/glassin-$ARCH.tar.gz
curl -LO $BASE/glassin-$ARCH.tar.gz.sha256
sha256sum -c glassin-$ARCH.tar.gz.sha256

# 3) Install (payload/ -> /opt/glassout, units -> systemd)
tar xzf glassin-$ARCH.tar.gz
sudo mkdir -p /opt/glassout /etc/glassout
sudo cp -a payload/.         /opt/glassout/
sudo cp -a systemd/*.service /etc/systemd/system/
# default config so the client starts (unconfigured -> "No configuration")
[ -f /etc/glassout/panel.conf ] || printf 'port = 8787\nfps = 20\ntype = viewer\nscale = 1\nrotate = 0\nlanguage = en\n' | sudo tee /etc/glassout/panel.conf >/dev/null

# 4) Run the client under your user + device access (framebuffer/DRM + input)
sudo sed -i "s/^User=.*/User=$USER/" /etc/systemd/system/glassout-pi.service
sudo usermod -aG video,render,input "$USER"   # then log out and back in

# 5) Enable + start the services
sudo systemctl daemon-reload
sudo systemctl enable --now glassout-provisioning.service
sudo systemctl enable --now glassout-pi.service

# 6) Clean appliance boot (edit /boot/firmware/, older images: /boot/)
#    cmdline.txt (single line): send console off tty1 + quiet + hide logo/cursor
sudo sed -i 's/console=tty1/console=tty3/; s/$/ quiet loglevel=3 logo.nologo vt.global_cursor_default=0/' /boot/firmware/cmdline.txt
#    config.txt: no rainbow splash
echo 'disable_splash=1' | sudo tee -a /boot/firmware/config.txt
#    console autologin on tty1: no login prompt, but keeps the session the
#    KMSDRM client needs (do NOT mask getty@tty1 — that breaks the display)
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF

# 7) AP onboarding (starts a setup hotspot only when there is no network at boot)
sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
sudo cp /opt/glassout/dnsmasq-shared.d/glassout-captive.conf /etc/NetworkManager/dnsmasq-shared.d/
sudo chmod +x /opt/glassout/ap_mode.sh
sudo systemctl enable glassout-ap-autostart.service

# 8) GPIO reset button (hold GPIO 21 / pin 40 → GND / pin 39 for 5 s)
sudo systemctl enable --now glassout-gpio-reset.service

sudo reboot   # apply the boot settings
```
</details>

## Wi-Fi setup via the access point (AP mode)

If the device boots **without a network connection** — no Ethernet and no known Wi-Fi —
it automatically starts an open setup hotspot so you can configure Wi-Fi from a phone or
laptop. While it is connected (Ethernet or a known Wi-Fi), the hotspot never starts.

1. Power on the Pi with no cable and no known Wi-Fi in range. After ~40 s it brings up the
   hotspot **`GlassIn-<serial-suffix>`** (open, no password).
2. Connect a phone or laptop to that hotspot. The setup page opens automatically (captive
   portal); if not, browse to **`http://10.42.0.1/`**.
3. Choose your Wi-Fi network, enter the password, and optionally set a **device name**
   (hostname). Tap **Connect**.
4. The Pi joins your Wi-Fi and the hotspot switches off. Reconnect your phone/laptop to
   your normal Wi-Fi and open **`http://<device-name>.local/`** (the name you set, or the
   IP shown on the device's screen) to finish configuration.

If the Wi-Fi password is wrong, the Pi automatically brings the hotspot back so you can
retry. (The first install still needs a network so `install.sh` can run over SSH — the
AP covers later boots without a known network.)

## Reset button (GPIO)

Optionally wire a momentary push button between **header pin 40 (GPIO 21)** and
**pin 39 (GND)**. **Hold it for 5 seconds** to forget the saved Wi-Fi networks and bring
up the setup access point (see above) — handy when the device was moved to a network it
can't join and you want to reconfigure Wi-Fi from a phone. Ethernet/LAN settings are left
untouched. The installer sets this up automatically; no button connected → nothing happens.

## Updating

**Automatic (recommended):** open the device's configuration page
(`http://<hostname>.local/`) → **Software** card → *Check for updates* → *Install*.
The device downloads the matching package, verifies its SHA256 checksum, backs up the
running version, installs the update and restarts; if the client fails to come up, it
automatically rolls back to the previous version.

**Manual:** download the matching `glassin-<arch>.tar.gz` and its `.sha256`, verify the
checksum, extract and install:

```bash
sha256sum -c glassin-<arch>.tar.gz.sha256
tar xzf glassin-<arch>.tar.gz          # contains payload/ and systemd/
sudo cp -a payload/.         /opt/glassout/
sudo cp -a systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart glassout-pi.service glassout-provisioning.service
```

## Version history

| Version | Date       | Architectures | Notes |
|---------|------------|---------------|-------|
| v1.0.7  | 2026-07-24 | `armv6l`      | GPIO reset button: hold GPIO 21 (pin 40) 5 s to forget Wi-Fi and start the setup AP. |
| v1.0.6  | 2026-07-24 | `armv6l`      | AP-mode onboarding (installer sets up the setup hotspot; device name on the AP page); provisioning service fully English. |
| v1.0.5  | 2026-07-23 | `armv6l`      | Config UI: graceful self-update — waits for the service to come back before reloading (no transient "Load failed"). |
| v1.0.4  | 2026-07-23 | `armv6l`      | Consistent GlassIn branding in the config UI (hostname suggestion, setup hotspot name, labels). |
| v1.0.3  | 2026-07-23 | `armv6l`      | Startup: display init (KMSDRM) retries cleanly during cold boot instead of restart-looping. |
| v1.0.2  | 2026-07-23 | `armv6l`      | Robustness: no crash-loop on missing config; installer seeds a default config and hides the console login. |
| v1.0.1  | 2026-07-23 | `armv6l`      | First release published via the update mechanism. |

See each release's [notes](../../releases) for details.
