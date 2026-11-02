# GlassIn

Native Raspberry Pi client for **[GlassOut](https://glassout.flyingart.dev/)** panel
streams: connects to the GlassOut engine on your flight-simulator PC over WebSocket, decodes
the panel images and shows them fullscreen on **standard HDMI monitors**: a single panel or
a template layout of several panels, including touch input. Runs as an appliance on
Raspberry Pi OS Lite (no desktop, output straight to the display via KMSDRM). Power on, and
the instrument is there.

GlassOut (the engine that produces the panel streams): <https://glassout.flyingart.dev/>

> This repository hosts the **releases** (prebuilt packages) and the installer. Devices
> update themselves from their configuration page (**Software** card) and automatically
> download the package that matches their system.

## ⚠️ Upgrading from 1.x to 2.0

Version 2.0 is a major rework: besides the new features (multiple monitors, LAN-first
networking, GlassOut profile backups, a new configuration page) everything was renamed from
`glassout` to **`glassin`** (`/opt/glassin`, `/etc/glassin`, `glassin.service` …).

**A 1.x device cannot update itself to 2.x from its configuration page.** Its updater doesn't
know the new names: it offers 2.x, but installing changes nothing. The device keeps running
1.x and offers the update again. Nothing breaks.

To move a 1.x device to 2.0:
- **Device already runs Raspberry Pi OS Trixie** (`cat /etc/os-release`): run the installer
  over SSH (see below). It takes over `panel.conf` and the saved Wi-Fi and removes 1.x.
- **Older systems (Bookworm):** save the configuration on the old config page
  (*Back up configuration*), flash a fresh Raspberry Pi OS Lite (Trixie), run the installer, and
  load the saved file on the new config page (**System → Load configuration**). Set up Wi-Fi
  again.

From 2.0 on, devices update normally from the configuration page again.

## Requirements

- **Raspberry Pi OS Lite based on Debian 13 (Trixie)**, without desktop. Packages are built
  against Trixie libraries; Bookworm and older are not supported.
- A **standard HDMI monitor** (touch optional via USB). A Pi 4/400 or Pi 5/500 can drive
  **two monitors**, each with its own panel or template.
- A brand-name SD card (A1/A2). Counterfeit cards (e.g. reporting as `SD16G`, manufacturer
  `0x000000`) write extremely slowly and corrupt the system.

| Model | 32-bit OS | 64-bit OS | HDMI outputs |
|---|---|---|---|
| Pi 1, Pi Zero, Pi Zero W | ✅ `armv6l` | — | 1 |
| Pi 2 | ✅ `armv7l` | — | 1 |
| Pi Zero 2 W, Pi 3 | ✅ `armv7l` | ✅ `aarch64` (recommended) | 1 |
| Pi 4, Pi 400 | ✅ `armv7l` | ✅ `aarch64` (recommended) | 2 |
| Pi 5, Pi 500 | ✅ `armv7l` | ✅ `aarch64` (recommended) | 2 |

The installer and the updater pick the right package **automatically** (by the system's
userland architecture, so a 32-bit OS on a Pi 4/5 gets the 32-bit package). Pi 1 / Zero:
keep the frame rate low (≈ 20 fps).

**Measured on a Pi 4** (two monitors, 4 panel streams at 20 fps): ≈ 11 % CPU, ≈ 100 MB RAM,
41–42 °C without throttling, ≈ 5 MB/s (≈ 40 Mbit/s) network. Fine over Ethernet; over the
Pi's 2.4 GHz Wi-Fi it gets tight. If it stutters, lower the target frame rate.

## Installation

1. Flash **Raspberry Pi OS Lite (Trixie)** with Raspberry Pi Imager. Choose any user name,
   **enable SSH**, and give the Pi network access for the installation (Ethernet, or Wi-Fi
   set in the Imager). Set the Wi-Fi country if the Imager offers it.
2. SSH in and run the installer:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/torben-erz/glassin/master/install.sh | sudo bash
   sudo reboot
   ```

3. Open **`http://<hostname>.local/`** in a browser and configure it (see below).

Installer options (environment variables, e.g. `… | sudo WIFI_COUNTRY=DE bash`):

| Variable | Effect |
|---|---|
| `WIFI_COUNTRY=DE` | set the Wi-Fi country |
| `GLASSIN_VERSION=v2.0.0` | install a specific release instead of the latest |
| `GLASSIN_PACKAGE=/path/glassin-<arch>.tar.gz` | install a local package |

<details>
<summary>What the installer does</summary>

1. Checks for **Trixie** and determines the package architecture (`dpkg`).
2. Installs the runtime libraries only (**minimal installation**, `--no-install-recommends`,
   no `-dev` packages): SDL2 + SDL2_ttf, TurboJPEG, cJSON, libwebsockets, the Mesa EGL/GLES
   drivers (loaded by SDL2 at runtime), DejaVu font, `dnsmasq-base` (setup hotspot), `rfkill`,
   `python3-gpiozero` + `python3-lgpio` (reset button, `lgpio` for the Pi 5).
3. Downloads the latest release for this architecture and verifies its SHA256 checksum.
4. **GlassIn 1.x found** (`/opt/glassout`)? Takes over its `panel.conf` and saved Wi-Fi and
   removes it.
5. Installs into `/opt/glassin`, creates a default config if none exists, and runs the client
   as **your login user** (groups `video`, `render`, `input`).
6. **Clean appliance boot:** no boot messages, logo, rainbow splash, console cursor or login
   text. tty1 stays occupied by a silent getty instead of being disabled (do **not** mask
   `getty@tty1`: that can take the display away from KMSDRM).
7. Enables `glassin-network`, `glassin-provisioning`, `glassin-gpio-reset` and `glassin`.

The installer can run **repeatedly** (reinstall/repair). Configuration, Wi-Fi and profile
backups are kept.
</details>

## Configuration page

`http://<hostname>.local/` (English, German, Spanish, French). The **Status** card on top
shows the service, each monitor, the detected aircraft and the active network connection.

| Tab | Contents |
|---|---|
| **Display** | Panel or template, rotation, size, position. With two monitors: one sub-tab per monitor, each with an optional name. From monitor 2 on there is **Not used** (the monitor then shows a hint with the config address). |
| **Network** | Wi-Fi (saved network, scan, *Test & save*) |
| **System** | GlassOut engine (host, port, connection type, frame rate), hostname, language, *Back up / Load configuration*, *Reset to factory defaults*, **GlassOut profiles**, **Software** update |

*Apply* writes the configuration and restarts the client.

## Network: LAN first, Wi-Fi as fallback

- **LAN connected** (on-board, LAN HAT or USB adapter): Wi-Fi is switched off.
- **No LAN** (no cable, or no IP within 30 s): a saved Wi-Fi is used.
- **Neither** (after 40 s): the setup hotspot **`GlassIn-<XXXX>`** starts (after boot, or when no
  Wi-Fi is saved). The screen counts down to it and then shows its name and `http://10.42.0.1`.
- **LAN comes back:** Wi-Fi is switched off again.

### Wi-Fi setup

**Via the setup hotspot** (no LAN, no saved Wi-Fi):
1. Connect a phone to the open hotspot **`GlassIn-<XXXX>`** (`XXXX` = last 4 digits of the
   serial number). The setup page opens automatically (captive portal), otherwise browse to
   **`http://10.42.0.1/`**.
2. The page scans for networks right away. Tap yours, enter the password (empty = open
   network), optionally a device name, and send.
3. The hotspot switches off and the Pi joins your Wi-Fi. Reconnect your phone to your Wi-Fi
   and open `http://<device-name>.local/`. If the password was wrong, the hotspot returns
   after ~30 s and the page shows the error.

**Via the configuration page** (**Network** tab): with LAN connected, *Test & save* checks the
credentials (login only, no IP address) and keeps the Wi-Fi as a fallback. Without LAN the
device switches networks. New credentials replace the saved Wi-Fi only if they work.

### Reset button (GPIO)

Optionally wire a momentary push button between **header pin 40 (GPIO 21)** and **pin 39
(GND)**. **Hold it for 5 seconds** to forget the saved Wi-Fi and start the setup hotspot.
With LAN connected the hotspot switches off again right away (set up Wi-Fi on the config page
instead).

## GlassOut profile backup

GlassIn receives all **profiles and templates** from GlassOut and keeps the **last 10 versions**
on the device (FIFO), automatically on every change (default) or only on request (*Save now*
when *Save automatically* is off). On the config page (**System → GlassOut profiles**) pick a
version and a profile and *Download profile* as `<profile>_<date>_<time>.glassout.json`. The file has
the same format as an export from the GlassOut desktop app. **Restore it there via *Import*.**
(GlassIn cannot write profiles back to GlassOut.)

## Updating

**From the configuration page (recommended):** **System → Software** → *Check for updates* →
*Install*. The device downloads the matching package, verifies its checksum, backs up the
running version, installs and restarts; if the client fails to come up, it rolls back
automatically.

**Manually:** run the installer again (see *Installation*). It installs the latest release
and keeps the configuration.

## Version history

| Version | Date       | Architectures | Notes |
|---------|------------|---------------|-------|
| v2.0.0  | 2026-11-01 | `armv6l`, `armv7l`, `aarch64` | **Major release — 1.x devices must be moved over once (see above).** Two monitors on Pi 4/5 (own panel/template, rotation, size and name each). LAN first with Wi-Fi fallback and setup hotspot (countdown and hotspot name on screen). Wi-Fi setup with credential check. GlassOut profile backup with versions and download in the desktop app's import format. New configuration page with tabs, per-monitor status. Minimal installation and new installer (Trixie, clean appliance boot). Updater picks the package by userland architecture. Everything renamed to `glassin`. |
| v1.0.9  | 2026-07-24 | `armv6l`, `armv7l`, `aarch64` | Maintenance release. Multi-arch builds are now built and published directly on the build host. No functional changes. |
| v1.0.8  | 2026-07-24 | `armv6l`, `armv7l`, `aarch64` | Multiple-output support: on a Pi with more than one connected display, the config page shows a monitor selector to pick which output shows the panel. First release covering all three architectures. |
| v1.0.7  | 2026-07-24 | `armv6l`      | GPIO reset button: hold GPIO 21 (pin 40) 5 s to forget Wi-Fi and start the setup AP. |
| v1.0.6  | 2026-07-24 | `armv6l`      | AP-mode onboarding (installer sets up the setup hotspot; device name on the AP page); provisioning service fully English. |
| v1.0.5  | 2026-07-23 | `armv6l`      | Config UI: graceful self-update — waits for the service to come back before reloading (no transient "Load failed"). |
| v1.0.4  | 2026-07-23 | `armv6l`      | Consistent GlassIn branding in the config UI (hostname suggestion, setup hotspot name, labels). |
| v1.0.3  | 2026-07-23 | `armv6l`      | Startup: display init (KMSDRM) retries cleanly during cold boot instead of restart-looping. |
| v1.0.2  | 2026-07-23 | `armv6l`      | Robustness: no crash-loop on missing config; installer seeds a default config and hides the console login. |
| v1.0.1  | 2026-07-23 | `armv6l`      | First release published via the update mechanism. |

See each release's [notes](../../releases) for details.
