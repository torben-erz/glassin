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

# 3) Entpacken + installieren (payload/ → /opt/glassout, Units → systemd)
tar xzf "$ASSET"
[ -d payload ] || { echo "FEHLER: Paket hat ein unerwartetes Format."; exit 1; }
mkdir -p "$OPT" "$ETC"
cp -a payload/.         "$OPT/"
cp -a systemd/*.service /etc/systemd/system/

# 4) Geräte-Zugriff (Framebuffer/DRM + Eingabe) für den Service-User
SVC_USER="$(sed -n 's/^User=//p' /etc/systemd/system/glassout-pi.service | head -1)"
[ -n "$SVC_USER" ] || SVC_USER="pi"
if id "$SVC_USER" >/dev/null 2>&1; then
  usermod -aG video,render,input "$SVC_USER"
fi

# 5) Dienste aktivieren + starten
echo "-> Dienste aktivieren …"
systemctl daemon-reload
systemctl enable --now glassout-provisioning.service
systemctl enable --now glassout-pi.service

HOST="$(hostname)"
echo
echo "Fertig ✔  Konfiguration im Browser:  http://$HOST.local/"
echo "Hinweis: Der Service-User '$SVC_USER' braucht ggf. ein erneutes Login,"
echo "         damit die neuen Gruppen (video/render/input) greifen."
