#!/usr/bin/env bash
#
# GlassIn — Ein-Kommando-Installer für Raspberry Pi OS Lite.
#
#   curl -fsSL https://raw.githubusercontent.com/torben-erz/glassin/master/install.sh | sudo bash
#
# Installiert die Laufzeit-Abhängigkeiten, lädt das zur Architektur passende
# neueste Release, prüft die SHA256-Summe, installiert nach /opt/glassout +
# systemd und startet die Dienste. Danach: http://<hostname>.local/ konfigurieren.
set -euo pipefail

REPO="torben-erz/glassin"
OPT="/opt/glassout"
ETC="/etc/glassout"

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte als root ausführen, z. B.:"
  echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/master/install.sh | sudo bash"
  exit 1
fi

ARCH="$(uname -m)"
ASSET="glassin-$ARCH.tar.gz"
BASE="https://github.com/$REPO/releases/latest/download"
echo "== GlassIn-Installer ($ARCH) =="

# 1) Laufzeit-Abhängigkeiten
echo "-> Abhängigkeiten installieren …"
apt-get update
apt-get install -y libwebsockets-dev libturbojpeg0-dev libsdl2-dev \
  libsdl2-ttf-dev libcjson-dev fonts-dejavu-core curl ca-certificates

# 2) Neuestes Release-Paket laden + verifizieren
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
echo "-> Lade $ASSET aus dem neuesten Release …"
curl -fLO "$BASE/$ASSET" \
  || { echo "FEHLER: Kein Paket für Architektur '$ARCH' im neuesten Release gefunden."; exit 1; }
curl -fLO "$BASE/$ASSET.sha256" \
  || { echo "FEHLER: Prüfsummen-Datei fehlt im Release."; exit 1; }
echo "-> Prüfsumme verifizieren …"
sha256sum -c "$ASSET.sha256"

# Ziel-User = der tatsächlich anmeldende Benutzer. Moderne Pi-Images haben keinen
# festen „pi"-User mehr, daher NICHT die Unit-Vorgabe verwenden, sondern den
# aufrufenden Login-User (bei `sudo` via $SUDO_USER).
TARGET_USER="${SUDO_USER:-}"
[ -n "$TARGET_USER" ] || TARGET_USER="$(logname 2>/dev/null || true)"
[ -n "$TARGET_USER" ] || TARGET_USER="$(id -un)"
echo "-> Dienst-Benutzer: $TARGET_USER"

# 3) Entpacken + installieren (payload/ → /opt/glassout, Units → systemd)
tar xzf "$ASSET"
[ -d payload ] || { echo "FEHLER: Paket hat ein unerwartetes Format."; exit 1; }
mkdir -p "$OPT" "$ETC"
cp -a payload/.         "$OPT/"
cp -a systemd/*.service /etc/systemd/system/

# Standard-Konfig anlegen, falls keine existiert. Ohne panel.conf beendet sich der
# Client mit „Konfig-Datei nicht lesbar" und startet endlos neu. Unkonfiguriert
# (kein Host) → der Client zeigt „Keine Konfiguration"; eingerichtet wird im Browser.
if [ ! -f "$ETC/panel.conf" ]; then
  cat > "$ETC/panel.conf" <<'CONF'
# GlassIn Pi-Panel — Werkseinstellungen (unkonfiguriert)
port = 8787
fps = 20
type = viewer
scale = 1
rotate = 0
language = en
CONF
fi

# 4) Client-Dienst unter dem tatsächlichen User laufen lassen (Image-User kann
#    abweichen) + Geräte-Zugriff (Framebuffer/DRM + Eingabe) gewähren.
sed -i "s/^User=.*/User=$TARGET_USER/" /etc/systemd/system/glassout-pi.service
if id "$TARGET_USER" >/dev/null 2>&1; then
  usermod -aG video,render,input "$TARGET_USER"
fi

# 5) Sauberer Appliance-Boot: keine Kernel-/Boot-Meldungen und kein Logo auf dem
#    sichtbaren Schirm, kein Farb-Splash, kein blinkender Konsolen-Cursor. (Den
#    Maus-/Touch-Zeiger blendet der SDL-Client im Vollbild ohnehin aus.) Idempotent,
#    mit Backup; greift nach einem Reboot.
echo "-> Boot für Appliance-Betrieb anpassen …"
BOOT=/boot/firmware; [ -d "$BOOT" ] || BOOT=/boot
CMD="$BOOT/cmdline.txt"; CFG="$BOOT/config.txt"
if [ -f "$CMD" ]; then
  cp -n "$CMD" "$CMD.glassin.bak" 2>/dev/null || true
  line="$(tr -d '\n' < "$CMD")"
  line="${line/console=tty1/console=tty3}"   # Boot-Text weg von der sichtbaren Konsole
  for kv in quiet loglevel=3 logo.nologo vt.global_cursor_default=0; do
    key="${kv%%=*}"
    case " $line " in *" $key"[\ =]*) : ;; *) line="$line $kv" ;; esac
  done
  echo "$line" > "$CMD"
fi
if [ -f "$CFG" ] && ! grep -q '^disable_splash=1' "$CFG"; then
  cp -n "$CFG" "$CFG.glassin.bak" 2>/dev/null || true
  printf '\n# GlassIn: kein Farb-Splash beim Boot\ndisable_splash=1\n' >> "$CFG"
fi
# Konsolen-Login auf tty1 per AUTOLOGIN entschärfen: kein „login:"-Prompt, aber die
# Sitzung bleibt bestehen — die der SDL-KMSDRM-Client für den Display-Zugriff braucht.
# (getty@tty1 NICHT maskieren — das nimmt dem Client das Display: „kmsdrm not available".)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<CONF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
CONF

# 6) Dienste aktivieren + starten
echo "-> Dienste aktivieren …"
systemctl daemon-reload
systemctl enable --now glassout-provisioning.service
systemctl enable --now glassout-pi.service

HOST="$(hostname)"
echo
echo "Fertig ✔  Konfiguration im Browser:  http://$HOST.local/"
echo "Hinweis: Der Service-User '$TARGET_USER' braucht ggf. ein erneutes Login,"
echo "         damit die neuen Gruppen (video/render/input) greifen."
echo "Hinweis: Für den sauberen Boot (ohne Logs/Logo/Cursor) einmal neu starten:  sudo reboot"
