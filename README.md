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

For a fresh **Raspberry Pi OS Lite** (no desktop). The client renders straight to the
framebuffer via KMSDRM; everything else is configured from the browser.

1. **Install the runtime dependencies** (this set also covers building from source):

   ```bash
   sudo apt update
   sudo apt install -y libwebsockets-dev libturbojpeg0-dev libsdl2-dev \
       libsdl2-ttf-dev libcjson-dev fonts-dejavu-core
   ```

2. **Download and verify** the package for your architecture (see the table above):

   ```bash
   ARCH=$(uname -m)
   BASE=https://github.com/torben-erz/glassin/releases/latest/download
   curl -LO $BASE/glassin-$ARCH.tar.gz
   curl -LO $BASE/glassin-$ARCH.tar.gz.sha256
   sha256sum -c glassin-$ARCH.tar.gz.sha256
   ```

3. **Install** it (`payload/` → `/opt/glassout`, units → systemd):

   ```bash
   tar xzf glassin-$ARCH.tar.gz
   sudo mkdir -p /opt/glassout /etc/glassout
   sudo cp -a payload/.         /opt/glassout/
   sudo cp -a systemd/*.service /etc/systemd/system/
   ```

4. **Grant device access** (framebuffer/DRM + input), then log out and back in:

   ```bash
   sudo usermod -aG video,render,input "$USER"
   ```

5. **Enable and start** the services:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now glassout-provisioning.service
   sudo systemctl enable --now glassout-pi.service
   ```

6. **Configure** in the browser: open `http://<hostname>.local/` (default hostname
   `glassout-<serial-suffix>`). Set the GlassOut engine host/port and choose a panel or
   template. Until the client connects and a flight is active, the screen shows
   **BOOTING**.

> Optional wireless onboarding: an access-point setup mode (`glassout-ap-autostart`,
> `ap_mode.sh`) is included, but additionally needs `dnsmasq-base` and a NetworkManager
> captive-DNS config. For a wired or pre-configured Wi-Fi connection it is not required.

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
| v1.0.1  | 2026-07-23 | `armv6l`      | First release published via the update mechanism. |

See each release's [notes](../../releases) for details.
