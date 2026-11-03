#!/bin/sh
# timeTracker - Installation der Linux-Variante (Debian/Ubuntu)
#  - installiert benötigte Pakete per apt
#  - legt Autostart- und Startmenü-Eintrag an
#  - richtet unter GNOME die Tastenkürzel Strg+Alt+Z (Menü) und Strg+Alt+A (Task) ein
# Aufruf: sh install.sh            (im Ordner, in dem zeiterfassung.py liegt)
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$APP_DIR/zeiterfassung.py"
[ -f "$APP" ] || { echo "zeiterfassung.py nicht gefunden in $APP_DIR"; exit 1; }
chmod +x "$APP"

echo "== Pakete installieren (sudo) =="
PKGS="python3 python3-gi gir1.2-gtk-3.0"
# Tray-Bibliothek: Ayatana (Ubuntu >= 20.04, Debian >= 11), sonst klassisch
if apt-cache show gir1.2-ayatanaappindicator3-0.1 >/dev/null 2>&1; then
    PKGS="$PKGS gir1.2-ayatanaappindicator3-0.1"
else
    PKGS="$PKGS gir1.2-appindicator3-0.1"
fi
# GNOME zeigt Tray-Symbole nur mit dieser Erweiterung (unter Ubuntu bereits aktiv)
if [ "${XDG_CURRENT_DESKTOP#*GNOME}" != "$XDG_CURRENT_DESKTOP" ] && ! grep -qi ubuntu /etc/os-release; then
    PKGS="$PKGS gnome-shell-extension-appindicator"
fi
sudo apt-get update && sudo apt-get install -y $PKGS

echo "== Autostart und Startmenü =="
mkdir -p "$HOME/.config/autostart" "$HOME/.local/share/applications"
DESKTOP="[Desktop Entry]
Type=Application
Name=Arbeitszeit
Comment=Arbeitszeit- und Todo-Verwaltung
Exec=/usr/bin/python3 \"$APP\"
Icon=x-office-calendar
Terminal=false
Categories=Office;
X-GNOME-Autostart-enabled=true"
printf '%s\n' "$DESKTOP" > "$HOME/.config/autostart/zeiterfassung.desktop"
printf '%s\n' "$DESKTOP" > "$HOME/.local/share/applications/zeiterfassung.desktop"
echo "   ~/.config/autostart/zeiterfassung.desktop"

if command -v gsettings >/dev/null 2>&1 && gsettings list-schemas | grep -q '^org.gnome.settings-daemon.plugins.media-keys$'; then
    echo "== GNOME-Tastenkürzel =="
    /usr/bin/python3 - "$APP" <<'EOF'
import ast, subprocess, sys
app = sys.argv[1]
base = "org.gnome.settings-daemon.plugins.media-keys"
key = "custom-keybindings"
prefix = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
cur = subprocess.run(["gsettings", "get", base, key], capture_output=True, text=True).stdout.strip()
if cur.startswith("@as "):
    cur = cur[4:]
paths = ast.literal_eval(cur) if cur else []
for name, binding, arg in [("zeiterfassung-menu", "<Control><Alt>z", "--menu"),
                           ("zeiterfassung-task", "<Control><Alt>a", "--add-task")]:
    path = prefix + name + "/"
    if path not in paths:
        paths.append(path)
    schema = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:" + path
    subprocess.run(["gsettings", "set", schema, "name", "Arbeitszeit " + arg], check=True)
    subprocess.run(["gsettings", "set", schema, "command", '/usr/bin/python3 "%s" %s' % (app, arg)], check=True)
    subprocess.run(["gsettings", "set", schema, "binding", binding], check=True)
    print("   %s -> %s" % (binding, arg))
subprocess.run(["gsettings", "set", base, key, str(paths)], check=True)
EOF
else
    echo "== Tastenkürzel bitte in den Systemeinstellungen anlegen =="
    echo "   Strg+Alt+Z:  /usr/bin/python3 \"$APP\" --menu"
    echo "   Strg+Alt+A:  /usr/bin/python3 \"$APP\" --add-task"
fi

echo
echo "Fertig. Starten mit:  /usr/bin/python3 \"$APP\" &"
echo "(GNOME unter Debian: nach Installation der AppIndicator-Erweiterung einmal ab- und anmelden"
echo " und die Erweiterung ggf. unter 'Erweiterungen' aktivieren.)"
