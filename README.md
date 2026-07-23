# GlassIn

Nativer Raspberry-Pi-Client für **GlassOut**-Panel-Streams: verbindet sich per
WebSocket mit der GlassOut-Engine, dekodiert die Panel-JPEGs und zeigt sie vollbild
an (Einzelpanel oder Template-Layout), inklusive Touch-Rückkanal. Läuft als Appliance
auf Raspberry Pi OS Lite (ohne Desktop, Ausgabe direkt via KMSDRM).

> Dieses Repository stellt die **Releases** (fertige Pakete) bereit. Das Gerät kann
> sich über seine Konfigurationsseite (Karte **Software**) selbst aktualisieren und
> lädt dabei automatisch das zu seiner Architektur passende Paket.

## Welches Paket brauche ich?

Der Updater auf dem Gerät wählt das passende Asset **automatisch** anhand von
`uname -m`. Für die manuelle Installation gilt folgende Zuordnung — das Asset muss
**exakt** den `uname -m`-Wert des Geräts enthalten:

| `uname -m` | typische Modelle | Asset |
|---|---|---|
| `armv6l`  | Pi Zero, Pi Zero W, Pi 1 (32-bit OS) | `glassin-armv6l.tar.gz` |
| `armv7l`  | Pi 2 / 3 / Zero 2 W (32-bit OS)       | `glassin-armv7l.tar.gz` |
| `aarch64` | Pi Zero 2 W / 3 / 4 / 5 (64-bit OS)   | `glassin-aarch64.tar.gz` |

Architektur auf dem Pi prüfen:

```bash
uname -m
```

**Hinweis:** Ein Release enthält nur die Assets, die dafür gebaut wurden (die Pakete
werden auf einem Pi der jeweiligen Architektur erzeugt). Fehlt dein Asset in einem
Release, ist dieses Release für dein Modell (noch) nicht verfügbar — dann das jüngste
Release wählen, das dein Asset enthält.

## Aktualisieren

**Automatisch (empfohlen):** Konfigurationsseite des Geräts öffnen
(`http://<hostname>.local/`) → Karte **Software** → *Auf Updates prüfen* →
*Installieren*. Das Gerät lädt das passende Paket, verifiziert die SHA256-Summe,
sichert die laufende Version, spielt das Update ein und startet neu; kommt der Client
danach nicht hoch, wird automatisch auf die vorige Version zurückgerollt.

**Manuell:** Passendes `glassin-<arch>.tar.gz` und die zugehörige `.sha256` laden,
Prüfsumme verifizieren, entpacken und einspielen:

```bash
sha256sum -c glassin-<arch>.tar.gz.sha256
tar xzf glassin-<arch>.tar.gz          # enthält payload/ und systemd/
sudo cp -a payload/.         /opt/glassout/
sudo cp -a systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart glassout-pi.service glassout-provisioning.service
```

## Versionshistorie

| Version | Datum      | Architekturen | Anmerkungen |
|---------|------------|---------------|-------------|
| v1.0.1  | 2026-07-23 | `armv6l`      | Erstes über den Update-Mechanismus veröffentlichtes Release. |

Details zu jeder Version stehen in den jeweiligen [Release-Notes](../../releases).
