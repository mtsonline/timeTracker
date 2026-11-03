# Installation guide

timeTracker consists of a single script per operating system. The data is stored **in the same
folder as the script**. If you use several computers, put that folder into a synchronised folder
(Nextcloud, Syncthing, OneDrive, network share …) and copy both scripts into it.

```
Nextcloud/TimeTracking/
├── zeiterfassung.ps1          (Windows)
├── start-zeiterfassung.cmd    (Windows)
├── zeiterfassung.py           (Linux)
└── install.sh                 (Linux)
```

## Windows

**Requirements:** Windows 10 or 11. PowerShell 5.1 is built in; PowerShell 7 works as well.

1. Copy `windows/zeiterfassung.ps1` and `windows/start-zeiterfassung.cmd` into the data folder.
2. If the files were downloaded from the internet: right-click → *Properties* → tick *Unblock* →
   *OK* – or in PowerShell:
   ```powershell
   Unblock-File .\zeiterfassung.ps1
   ```
3. Start: double-click `start-zeiterfassung.cmd`. The icon appears in the notification area of the
   taskbar (possibly hidden behind the `^` arrow).
4. **Autostart:** `Win+R` → `shell:startup` → create a shortcut to `start-zeiterfassung.cmd`.

System-wide hotkeys: **Ctrl+Alt+Z** opens the menu, **Ctrl+Alt+A** starts “Add task”.

For troubleshooting, run the script directly in a PowerShell console – it then shows a log:

```powershell
powershell -ExecutionPolicy Bypass -File .\zeiterfassung.ps1
```

## Linux (Debian / Ubuntu)

**Requirements:** a desktop environment with a system tray (GNOME with the AppIndicator extension,
KDE Plasma, Xfce, Cinnamon, MATE …). All packages come from the standard repositories.

1. Copy `linux/zeiterfassung.py` and `linux/install.sh` into the data folder.
2. In a terminal in the data folder:
   ```sh
   sh install.sh
   ```
   The script
   - installs via `apt`: `python3`, `python3-gi`, `gir1.2-gtk-3.0`,
     `gir1.2-ayatanaappindicator3-0.1` (or `gir1.2-appindicator3-0.1`) and, on Debian with GNOME,
     `gnome-shell-extension-appindicator`,
   - creates an autostart entry (`~/.config/autostart/zeiterfassung.desktop`) and an application
     menu entry,
   - sets up the GNOME shortcuts **Ctrl+Alt+Z** (menu) and **Ctrl+Alt+A** (add task).
3. Start: `python3 zeiterfassung.py &` – from then on it starts automatically at every login.

**GNOME on Debian:** after installing the AppIndicator extension, log out and back in once and
enable the extension in the *Extensions* app. Ubuntu ships it already.

**Other desktops (KDE, Xfce …):** create the shortcuts in the system settings:

| Shortcut | Command |
|---|---|
| Ctrl+Alt+Z | `/usr/bin/python3 /path/to/folder/zeiterfassung.py --menu` |
| Ctrl+Alt+A | `/usr/bin/python3 /path/to/folder/zeiterfassung.py --add-task` |

Programs cannot register global hotkeys themselves under Wayland, so the desktop's shortcut
settings are used.

### Command line

| Call | Function |
|---|---|
| `zeiterfassung.py` | start the tray icon (if already running, the menu is shown as a dialog) |
| `--menu` | menu as a keyboard dialog |
| `--add-task`, `--report`, `--add-todo`, `--todos`, `--todo-report`, `--export`, `--settings` | run a single function |
| `--no-tray` | no tray icon, menu dialog only |
| `--data-dir <folder>` | other data folder (default: folder of the script; or environment variable `ZEITERFASSUNG_DIR`) |

Troubleshooting: `ZEITERFASSUNG_DEBUG=1 python3 zeiterfassung.py`

## Updating

Replace the script files and restart the program (ideally on all computers). Data files are kept;
older worklogs are read automatically.

## Uninstalling

- Windows: exit via the tray menu, delete the shortcut from `shell:startup` and the script files.
  Optionally delete `%APPDATA%\Zeiterfassung`.
- Linux: delete `~/.config/autostart/zeiterfassung.desktop`,
  `~/.local/share/applications/zeiterfassung.desktop` and `~/.config/zeiterfassung`; remove the
  GNOME shortcuts in the settings.

Your data (JSON/CSV) stays in the data folder until you delete it.
