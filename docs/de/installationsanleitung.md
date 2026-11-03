# Installationsanleitung

timeTracker besteht aus einem einzigen Script je Betriebssystem. Die Daten liegen **im selben
Ordner wie das Script**. Wer mehrere Rechner nutzt, legt diesen Ordner in einen synchronisierten
Ordner (Nextcloud, Syncthing, OneDrive, Netzlaufwerk …) und kopiert beide Scripts hinein.

```
Nextcloud/Zeiterfassung/
├── zeiterfassung.ps1          (Windows)
├── start-zeiterfassung.cmd    (Windows)
├── zeiterfassung.py           (Linux)
└── install.sh                 (Linux)
```

## Windows

**Voraussetzungen:** Windows 10 oder 11. PowerShell 5.1 ist vorinstalliert; PowerShell 7 funktioniert ebenfalls.

1. `windows/zeiterfassung.ps1` und `windows/start-zeiterfassung.cmd` in den Datenordner kopieren.
2. Falls die Dateien aus dem Internet geladen wurden: Rechtsklick → *Eigenschaften* →
   *Zulassen* (Haken bei „Zulassen“) und *OK* – oder in PowerShell:
   ```powershell
   Unblock-File .\zeiterfassung.ps1
   ```
3. Starten: Doppelklick auf `start-zeiterfassung.cmd`.
   Das Symbol erscheint im Infobereich der Taskleiste (ggf. unter dem Pfeil `^`).
4. **Autostart:** `Win+R` → `shell:startup` → Verknüpfung auf `start-zeiterfassung.cmd` anlegen.

Tastenkürzel (systemweit): **Strg+Alt+Z** öffnet das Menü, **Strg+Alt+A** startet „Task hinzufügen“.

Zur Fehlersuche das Script direkt in einer PowerShell-Konsole starten – die Konsole zeigt dann ein Protokoll:

```powershell
powershell -ExecutionPolicy Bypass -File .\zeiterfassung.ps1
```

## Linux (Debian / Ubuntu)

**Voraussetzungen:** eine Desktop-Umgebung mit Infobereich (GNOME mit AppIndicator-Erweiterung,
KDE Plasma, Xfce, Cinnamon, MATE …). Alle Pakete stammen aus den Standard-Paketquellen.

1. `linux/zeiterfassung.py` und `linux/install.sh` in den Datenordner kopieren.
2. Im Terminal im Datenordner:
   ```sh
   sh install.sh
   ```
   Das Script
   - installiert per `apt`: `python3`, `python3-gi`, `gir1.2-gtk-3.0`,
     `gir1.2-ayatanaappindicator3-0.1` (bzw. `gir1.2-appindicator3-0.1`) und unter Debian mit GNOME
     zusätzlich `gnome-shell-extension-appindicator`,
   - legt einen Autostart-Eintrag (`~/.config/autostart/zeiterfassung.desktop`) und einen
     Startmenü-Eintrag an,
   - richtet unter GNOME die Tastenkürzel **Strg+Alt+Z** (Menü) und **Strg+Alt+A** (Task) ein.
3. Starten: `python3 zeiterfassung.py &` – danach startet das Programm bei jeder Anmeldung automatisch.

**GNOME unter Debian:** Nach der Installation der AppIndicator-Erweiterung einmal ab- und wieder
anmelden und die Erweiterung in der App *Erweiterungen* aktivieren. Ubuntu bringt sie bereits mit.

**Andere Desktops (KDE, Xfce …):** Tastenkürzel in den Systemeinstellungen anlegen:

| Kürzel | Befehl |
|---|---|
| Strg+Alt+Z | `/usr/bin/python3 /pfad/zum/ordner/zeiterfassung.py --menu` |
| Strg+Alt+A | `/usr/bin/python3 /pfad/zum/ordner/zeiterfassung.py --add-task` |

Globale Tastenkürzel direkt aus einem Programm sind unter Wayland nicht möglich, deshalb
laufen sie über die Tastenkürzel der Desktop-Umgebung.

### Kommandozeile

| Aufruf | Funktion |
|---|---|
| `zeiterfassung.py` | Tray-Symbol starten (läuft es schon, wird das Menü als Dialog gezeigt) |
| `--menu` | Menü als Tastatur-Dialog |
| `--add-task`, `--report`, `--add-todo`, `--todos`, `--todo-report`, `--export`, `--settings` | einzelne Funktion direkt |
| `--no-tray` | ohne Tray-Symbol, nur Menü-Dialog |
| `--data-dir <Ordner>` | anderer Datenordner (Standard: Ordner des Scripts; alternativ Umgebungsvariable `ZEITERFASSUNG_DIR`) |

Fehlersuche: `ZEITERFASSUNG_DEBUG=1 python3 zeiterfassung.py`

## Aktualisieren

Script-Dateien einfach ersetzen und das Programm neu starten (am besten auf allen Rechnern).
Die Datendateien bleiben unverändert; ältere Worklogs werden automatisch gelesen.

## Deinstallieren

- Windows: Programm über das Tray-Menü beenden, Verknüpfung aus `shell:startup` und die
  Script-Dateien löschen. Optional `%APPDATA%\Zeiterfassung` löschen.
- Linux: `~/.config/autostart/zeiterfassung.desktop`,
  `~/.local/share/applications/zeiterfassung.desktop` und `~/.config/zeiterfassung` löschen;
  unter GNOME die Tastenkürzel in den Einstellungen entfernen.

Die Daten (JSON/CSV) bleiben im Datenordner erhalten, bis sie selbst gelöscht werden.
