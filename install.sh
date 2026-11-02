#!/usr/bin/env bash
#
#  Created by Torben Daniel Erz on 01.11.26.
#  Copyright © 2026 NanoApes, Torben Daniel Erz. All rights reserved.
#
# GlassIn — one-command installer for Raspberry Pi OS Lite (Trixie).
#
#   curl -fsSL https://raw.githubusercontent.com/torben-erz/glassin/master/install.sh | sudo bash
#
# Installs the runtime dependencies (minimal: runtime libraries only, no -dev
# packages, no recommends), downloads the latest release matching this system,
# verifies the SHA256 checksum, installs into /opt/glassin + systemd, prepares a
# clean appliance boot and starts the services. Configure afterwards at
# http://<hostname>.local/.
#
# Optional environment variables:
#   GLASSIN_PACKAGE=/path/glassin-<arch>.tar.gz   install a local package (testing)
#   GLASSIN_VERSION=v2.0.0                        install a specific release
#   WIFI_COUNTRY=DE                               set the Wi-Fi country (else: keep)
#
# The source of this script lives in the developer repo (deploy/install.sh); the
# release repo carries a copy.
set -euo pipefail

REPO="torben-erz/glassin"
OPT="/opt/glassin"
ETC="/etc/glassin"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root, e.g.:"
  echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/master/install.sh | sudo bash"
  exit 1
fi

# Raspberry Pi OS Trixie only: the packages are built against Trixie libraries.
. /etc/os-release
if [ "${VERSION_CODENAME:-}" != "trixie" ]; then
  echo "ERROR: GlassIn 2.x needs Raspberry Pi OS Lite based on Debian 13 (Trixie)."
  echo "       This system is '${PRETTY_NAME:-unknown}'. Please flash a current image."
  exit 1
fi

# Package architecture = userland, not kernel: a 32-bit OS on a Pi 4/5 runs a
# 64-bit kernel (uname -m says aarch64) but only 32-bit programs.
case "$(dpkg --print-architecture)" in
  arm64) ARCH="aarch64" ;;
  armhf) [ "$(uname -m)" = "armv6l" ] && ARCH="armv6l" || ARCH="armv7l" ;;
  *)     ARCH="$(uname -m)" ;;
esac
ASSET="glassin-$ARCH.tar.gz"
if [ -n "${GLASSIN_VERSION:-}" ]; then
  BASE="https://github.com/$REPO/releases/download/$GLASSIN_VERSION"
else
  BASE="https://github.com/$REPO/releases/latest/download"
fi
echo "== GlassIn installer ($ARCH) =="

# 1) Runtime dependencies — minimal installation.
#    Mesa EGL/GLES: SDL2 loads them only at runtime (KMSDRM), so they are not pulled
#    in as dependencies. dnsmasq-base: DHCP/DNS for the setup AP. rfkill: unblock
#    Wi-Fi without a Wi-Fi country. gpiozero/lgpio: GPIO reset button (lgpio = Pi 5).
echo "-> Installing dependencies …"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  libsdl2-2.0-0 libsdl2-ttf-2.0-0 libturbojpeg0 libcjson1 libwebsockets19t64 \
  libegl1 libgles2 libegl-mesa0 libgl1-mesa-dri \
  fonts-dejavu-core python3 python3-gpiozero python3-lgpio \
  dnsmasq-base rfkill curl ca-certificates

# 2) Get + verify the package
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if [ -n "${GLASSIN_PACKAGE:-}" ]; then
  echo "-> Using local package $GLASSIN_PACKAGE"
  cp "$GLASSIN_PACKAGE" "$TMP/$ASSET"
  [ -f "$GLASSIN_PACKAGE.sha256" ] && cp "$GLASSIN_PACKAGE.sha256" "$TMP/$ASSET.sha256"
  cd "$TMP"
else
  cd "$TMP"
  echo "-> Downloading $ASSET …"
  curl -fLO "$BASE/$ASSET" \
    || { echo "ERROR: no package for architecture '$ARCH' in this release."; exit 1; }
  curl -fLO "$BASE/$ASSET.sha256" \
    || { echo "ERROR: checksum file missing in the release."; exit 1; }
fi
if [ -f "$ASSET.sha256" ]; then
  echo "-> Verifying checksum …"
  sha256sum -c "$ASSET.sha256"
fi
tar xzf "$ASSET"
[ -d payload ] || { echo "ERROR: package has an unexpected format."; exit 1; }

# Service user = the actual login user. Current Pi images have no fixed "pi" user
# any more → use the invoking login user (via $SUDO_USER when run through sudo).
TARGET_USER="${SUDO_USER:-}"
[ -n "$TARGET_USER" ] || TARGET_USER="$(logname 2>/dev/null || true)"
[ -n "$TARGET_USER" ] || TARGET_USER="$(getent passwd 1000 | cut -d: -f1)"
[ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ] \
  || { echo "ERROR: could not determine the login user for the service."; exit 1; }
echo "-> Service user: $TARGET_USER"

# 3) GlassIn 1.x on this device (/opt/glassout)? Take over its configuration, then
#    retire it — two clients would fight over the display.
if [ -d /opt/glassout ] || [ -f /etc/systemd/system/glassout-pi.service ]; then
  echo "-> Found GlassIn 1.x — taking over its configuration and removing it …"
  mkdir -p "$ETC"
  [ -f /etc/glassout/panel.conf ] && [ ! -f "$ETC/panel.conf" ] && cp /etc/glassout/panel.conf "$ETC/panel.conf"
  for u in glassout-pi glassout-provisioning glassout-ap-autostart glassout-gpio-reset; do
    systemctl disable --now "$u.service" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$u.service"
  done
  # Saved Wi-Fi: rename the 1.x profile — unless a glassin-home already exists (never
  # create two profiles with the same name); then the old one is obsolete.
  if nmcli -t -f NAME connection show 2>/dev/null | grep -qx glassout-home; then
    if nmcli -t -f NAME connection show | grep -qx glassin-home; then
      nmcli connection delete glassout-home >/dev/null 2>&1 || true
    else
      nmcli connection modify glassout-home connection.id glassin-home >/dev/null 2>&1 || true
    fi
  fi
  nmcli connection delete glassout-ap >/dev/null 2>&1 || true
  rm -f /etc/NetworkManager/dnsmasq-shared.d/glassout-captive.conf
  rm -rf /opt/glassout /etc/glassout
fi

# 4) Install (payload/ → /opt/glassin, units → systemd). Stop a running client first
#    (reinstall): its binary cannot be overwritten while it runs ("Text file busy").
systemctl stop glassin.service >/dev/null 2>&1 || true
mkdir -p "$OPT" "$ETC" /etc/NetworkManager/dnsmasq-shared.d
cp -a payload/.         "$OPT/"
cp -a systemd/*.service /etc/systemd/system/
chmod +x "$OPT/glassin-client" "$OPT/ap_mode.sh"
cp "$OPT/dnsmasq-shared.d/glassin-captive.conf" /etc/NetworkManager/dnsmasq-shared.d/

# Default config if none exists (unconfigured → the screen shows "No configuration";
# everything else is set up in the browser).
if [ ! -f "$ETC/panel.conf" ]; then
  cat > "$ETC/panel.conf" <<'CONF'
# GlassIn — factory defaults (unconfigured)
port = 8787
fps = 20
type = viewer
scale = 1
rotate = 0
language = en
CONF
fi

# Client runs as the login user with display/input access (DRM/KMS + touch).
sed -i "s/^User=.*/User=$TARGET_USER/" /etc/systemd/system/glassin.service
usermod -aG video,render,input "$TARGET_USER"

# Wi-Fi country (optional). Without one, Raspberry Pi OS blocks the radio; the
# network service then unblocks it itself (world regulatory domain).
if [ -n "${WIFI_COUNTRY:-}" ] && command -v raspi-config >/dev/null; then
  raspi-config nonint do_wifi_country "$WIFI_COUNTRY" || true
fi

# 5) Clean appliance boot: no kernel/boot messages or logo on the visible screen,
#    no colour splash, no blinking console cursor. Idempotent, with a backup; takes
#    effect after a reboot.
echo "-> Configuring boot for appliance use …"
BOOT=/boot/firmware; [ -d "$BOOT" ] || BOOT=/boot
CMD="$BOOT/cmdline.txt"; CFG="$BOOT/config.txt"
if [ -f "$CMD" ]; then
  cp -n "$CMD" "$CMD.glassin.bak" 2>/dev/null || true
  line="$(tr -d '\n' < "$CMD")"
  line="${line/console=tty1/console=tty3}"   # move boot text off the visible console
  for kv in quiet loglevel=3 logo.nologo vt.global_cursor_default=0; do
    key="${kv%%=*}"
    case " $line " in *" $key"[\ =]*) : ;; *) line="$line $kv" ;; esac
  done
  echo "$line" > "$CMD"
fi
if [ -f "$CFG" ] && ! grep -q '^disable_splash=1' "$CFG"; then
  cp -n "$CFG" "$CFG.glassin.bak" 2>/dev/null || true
  printf '\n# GlassIn: no colour splash at boot\ndisable_splash=1\n' >> "$CFG"
fi
# Silent tty1: getty keeps the console occupied but prints nothing (no banner, no
# login, no prompt) — it just runs "sleep infinity" until the client takes over the
# display. (Do NOT mask/disable getty@tty1: that can take the display away —
# "kmsdrm not available".)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<CONF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login --noissue --nonewline --nohints --nohostname --login-program /usr/bin/sleep --login-options infinity %I \$TERM
CONF
systemctl enable getty@tty1.service >/dev/null 2>&1 || true

# 6) Enable + start the services
#    glassin-network: LAN first, Wi-Fi as fallback, setup AP as last resort.
#    glassin-gpio-reset: hold GPIO 21 (pin 40 → GND pin 39) 5 s → forget Wi-Fi + AP.
echo "-> Enabling services …"
systemctl daemon-reload
systemctl enable --now glassin-network.service
systemctl enable --now glassin-provisioning.service
systemctl enable --now glassin-gpio-reset.service >/dev/null 2>&1 || true
systemctl enable glassin.service
systemctl restart glassin.service

HOST="$(hostname)"
VER="$(grep -oE '^VERSION = "[^"]+"' "$OPT/glassin_provisioning.py" | cut -d'"' -f2)"
echo
echo "Done ✔  GlassIn $VER installed. Configure in your browser:  http://$HOST.local/"
echo "Note: reboot once for the clean boot screen (no logs/logo/cursor):  sudo reboot"
