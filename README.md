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
