#!/usr/bin/env bash
#
# GlassIn — one-command installer for Raspberry Pi OS Lite.
#
#   curl -fsSL https://raw.githubusercontent.com/torben-erz/glassin/master/install.sh | sudo bash
#
# Installs the runtime dependencies, downloads the latest release matching this
# architecture, verifies the SHA256 checksum, installs into /opt/glassout + systemd
# and starts the services. Afterwards configure at http://<hostname>.local/.
set -euo pipefail

REPO="torben-erz/glassin"
OPT="/opt/glassout"
ETC="/etc/glassout"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root, e.g.:"
  echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/master/install.sh | sudo bash"
  exit 1
fi

ARCH="$(uname -m)"
ASSET="glassin-$ARCH.tar.gz"
BASE="https://github.com/$REPO/releases/latest/download"
echo "== GlassIn installer ($ARCH) =="

# 1) Runtime dependencies
echo "-> Installing dependencies …"
apt-get update
apt-get install -y libwebsockets-dev libturbojpeg0-dev libsdl2-dev \
  libsdl2-ttf-dev libcjson-dev fonts-dejavu-core curl ca-certificates

# 2) Download + verify the latest release package
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
echo "-> Downloading $ASSET from the latest release …"
curl -fLO "$BASE/$ASSET" \
  || { echo "ERROR: no package for architecture '$ARCH' in the latest release."; exit 1; }
curl -fLO "$BASE/$ASSET.sha256" \
  || { echo "ERROR: checksum file missing in the release."; exit 1; }
echo "-> Verifying checksum …"
sha256sum -c "$ASSET.sha256"

# Target user = the actual login user. Modern Pi images no longer have a fixed
# "pi" user, so don't use the unit's default — use the invoking login user
# (via $SUDO_USER when run through `sudo`).
TARGET_USER="${SUDO_USER:-}"
[ -n "$TARGET_USER" ] || TARGET_USER="$(logname 2>/dev/null || true)"
[ -n "$TARGET_USER" ] || TARGET_USER="$(id -un)"
echo "-> Service user: $TARGET_USER"

# 3) Unpack + install (payload/ -> /opt/glassout, units -> systemd)
tar xzf "$ASSET"
[ -d payload ] || { echo "ERROR: package has an unexpected format."; exit 1; }
mkdir -p "$OPT" "$ETC"
cp -a payload/.         "$OPT/"
cp -a systemd/*.service /etc/systemd/system/

# Create a default config if none exists. Without panel.conf the client exits with
# "config file not readable" and restart-loops. Unconfigured (no host) -> the client
# shows "No configuration"; it is set up from the browser.
if [ ! -f "$ETC/panel.conf" ]; then
  cat > "$ETC/panel.conf" <<'CONF'
# GlassIn Pi panel — factory defaults (unconfigured)
port = 8787
fps = 20
type = viewer
scale = 1
rotate = 0
language = en
CONF
fi

# 4) Run the client service as the actual user (image user may differ) and grant
#    device access (framebuffer/DRM + input).
sed -i "s/^User=.*/User=$TARGET_USER/" /etc/systemd/system/glassout-pi.service
if id "$TARGET_USER" >/dev/null 2>&1; then
  usermod -aG video,render,input "$TARGET_USER"
fi

# 5) Clean appliance boot: no kernel/boot messages or logo on the visible screen,
#    no colour splash, no blinking console cursor. (The SDL client hides the mouse/
#    touch cursor in fullscreen anyway.) Idempotent, with a backup; takes effect
#    after a reboot.
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
# Defuse the console login on tty1 via AUTOLOGIN: no "login:" prompt, but the session
# stays — the SDL/KMSDRM client needs it for display access.
# (Do NOT mask getty@tty1 — that takes the display away: "kmsdrm not available".)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<CONF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
CONF

# 6) Enable + start the services
echo "-> Enabling services …"
systemctl daemon-reload
systemctl enable --now glassout-provisioning.service
systemctl enable --now glassout-pi.service

HOST="$(hostname)"
echo
echo "Done ✔  Configure in your browser:  http://$HOST.local/"
echo "Note: the service user '$TARGET_USER' may need to log in again"
echo "      for the new groups (video/render/input) to take effect."
echo "Note: for the clean boot (no logs/logo/cursor) reboot once:  sudo reboot"
