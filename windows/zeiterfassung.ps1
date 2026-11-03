# timeTracker - zeiterfassung.ps1 (Windows, PowerShell 5.1+)        Version 2.4.0
#
# Arbeitszeit- und Todo-Verwaltung als Tray-Anwendung. Gleiche Datendateien und Formate wie
# linux/zeiterfassung.py, damit beide Varianten parallel auf demselben (Nextcloud-)Ordner arbeiten.
#
#   <Datenordner>\categories.json, tasks.json, todo.json, columns.json
#   <Datenordner>\worklogs\<Montag yyyy-MM-dd>_worklog.csv   (UTF-8 mit BOM, CRLF, ';')
#   <Datenordner>\backups, <Datenordner>\worklogs\backups     (rotierende Backups .0 .. .9)
#   Datenordner = Ordner dieses Scripts. Einstellungen lokal: %APPDATA%\Zeiterfassung\settings.json
#
# Lizenz: MIT (siehe LICENSE)
#
# 2.4.0  Sprache Deutsch/Englisch; Spalten von Worklog-CSV/Report und Todo-Report frei konfigurierbar
#        (Startzeit, Endzeit, Wochentag, Dauer h:mm, Benutzer, eigene Felder); columns.json
# 2.3.0  Einstellungen (Name, Export-Pfad), Reports exportieren, KW zuerst in der Wochenauswahl
# 2.2.0  Fehlerbehebungen: Zeilenumbruch im Worklog, Überschreiben durch alte Daten (Sync), u.a.

# UTF-8 und grundlegende Assemblies
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Win32 API für globale Hotkeys und ein unsichtbares Message-Fenster
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class HotkeyWindow : Form {
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int WM_HOTKEY = 0x0312;
    public event Action<int> HotkeyPressed;

    public HotkeyWindow() {
        this.ShowInTaskbar = false;
        this.WindowState = FormWindowState.Minimized;
        this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        this.Load += (s, e) => { this.Hide(); };
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY) {
            if (HotkeyPressed != null) {
                HotkeyPressed(m.WParam.ToInt32());
            }
        }
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms.dll", "System.Drawing.dll"

# Verzeichnisse/Dateien
$configDir   = $PSScriptRoot
$tasksDir    = Join-Path $configDir "worklogs"
if (-not (Test-Path $tasksDir)) { New-Item -ItemType Directory -Path $tasksDir | Out-Null }
$catsFile        = Join-Path $configDir "categories.json"
$taskCatalogFile = Join-Path $configDir "tasks.json"
$todosFile       = Join-Path $configDir "todo.json"
$columnsFile     = Join-Path $configDir "columns.json"
# Einstellungen lokal pro Rechner (nicht synchronisiert)
$settingsDir     = Join-Path $env:APPDATA "Zeiterfassung"
$settingsFile    = Join-Path $settingsDir "settings.json"

# Globale Variablen (categories/taskCatalog/todos sind nur Momentaufnahmen; vor jeder Aktion wird neu geladen)
$global:trayIcon = $null
$global:refreshTimer = $null
$global:categories   = @{}
$global:taskCatalog  = @{}
$global:lastSelectedIndices = @{}
$global:todos = @()
$global:lastTrayMenuIndex = 0
$global:menuItems = @()
$global:BackupKeep = 10
$global:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$global:Scopes = @("Woche", "Monat", "Jahr", "Sonstiges")   # gespeicherte Werte (sprachunabhängig)
$global:Languages = @(@("de", "Deutsch"), @("en", "English"))

# Debug-Logging in Konsole
$global:EnableConsoleLog = $true
function Log([string]$msg) {
    if ($global:EnableConsoleLog) { Write-Host ("[{0:HH:mm:ss.fff}] {1}" -f (Get-Date), $msg) }
}

# -----------------------------------------------------------------------------
# Übersetzungen (identische Schlüssel/Texte wie linux/zeiterfassung.py)
# -----------------------------------------------------------------------------
$global:Strings = @{
    'de' = @{
        'app.title' = 'Arbeitszeit'
        'menu.report' = 'Report'
        'menu.addTask' = 'Task hinzufügen'
        'menu.addCat' = 'Kategorie/Unterkategorie hinzufügen'
        'menu.remCat' = 'Kategorie/Unterkategorie entfernen'
        'menu.addTodo' = 'Todo hinzufügen'
        'menu.todos' = 'Todos anzeigen'
        'menu.todoReport' = 'Todo-Report'
        'menu.export' = 'Reports exportieren'
        'menu.settings' = 'Einstellungen'
        'menu.recalc' = 'Heute neu berechnen'
        'menu.exit' = 'Beenden'
        'tray.today' = 'Heute {0} min ({1})'
        'sel.category' = 'Kategorie wählen'
        'sel.subcategory' = 'Unterkategorie wählen'
        'sel.task' = 'Task wählen'
        'sel.newTask' = '[Neuen Task eingeben]'
        'dlg.newTask.title' = 'Neuer Task'
        'dlg.newTask.label' = 'Kurzbeschreibung:'
        'dlg.minutes.title' = 'Dauer'
        'dlg.minutes.label' = 'Aufwand/Dauer in Minuten:'
        'dlg.start.title' = 'Startzeit'
        'dlg.start.label' = 'Startzeit (HH:MM):'
        'btn.ok' = 'OK'
        'btn.cancel' = 'Abbrechen'
        'btn.save' = 'Speichern'
        'btn.select' = 'Auswählen'
        'msg.info' = 'Info'
        'msg.hint' = 'Hinweis'
        'msg.error' = 'Fehler'
        'msg.question' = 'Frage'
        'msg.needCats' = 'Bitte zuerst Kategorien/Unterkategorien anlegen.'
        'msg.noSubs' = 'Diese Kategorie hat noch keine Unterkategorie.'
        'msg.invalidEntry' = 'Bitte Kategorie, Unterkategorie und Minuten korrekt angeben.'
        'msg.invalidMinutes' = 'Bitte eine gültige Minutenanzahl eingeben.'
        'msg.invalidTime' = 'Bitte eine gültige Uhrzeit im Format HH:MM eingeben.'
        'msg.loadError' = "Die Datei konnte nicht gelesen werden:`r`n{0}`r`n`r`nMöglicherweise wird sie gerade synchronisiert oder ist beschädigt.`r`nDie Änderung wurde NICHT gespeichert, damit keine Daten überschrieben werden.`r`nBitte später erneut versuchen (Backups liegen im Unterordner 'backups')."
        'msg.saveError' = "Die Datei konnte nicht gespeichert werden:`r`n{0}`r`n`r`nBitte später erneut versuchen."
        'cat.new' = '[Neue Kategorie anlegen]'
        'cat.newTitle' = 'Neue Kategorie'
        'cat.newLabel' = 'Name der neuen Kategorie:'
        'cat.subTitle' = 'Unterkategorie hinzufügen'
        'cat.subLabel' = 'Name der Unterkategorie für ''{0}'':'
        'cat.remSelect' = 'Kategorie zum Entfernen wählen'
        'cat.remSub' = 'Unterkategorie entfernen'
        'cat.remAll' = '[Kategorie vollständig entfernen]'
        'week.select' = 'Woche wählen'
        'week.label' = 'KW {0} / {1}   ({2} .. {3})'
        'report.title' = 'Report - KW {0}: {1}  ({2} .. {3})  F5 = aktualisieren'
        'report.noEntries' = 'Keine Einträge in dieser Woche.'
        'report.noData' = 'Keine Daten vorhanden.'
        'todoReport.title' = 'Todo-Report (Markdown)  F5 = aktualisieren'
        'todoReport.kw' = '# KW {0}'
        'todoReport.week' = '## Woche'
        'todoReport.month' = '## Monat ({0})'
        'todoReport.year' = '## Jahr ({0})'
        'todoReport.emptyWeek' = '* Keine offenen Todos in laufender Woche.'
        'todoReport.emptyMonth' = '* Keine offenen Todos im laufenden Monat.'
        'todoReport.emptyYear' = '* Keine offenen Todos im laufenden Jahr.'
        'todoReport.loadError' = 'Fehler: todo.json konnte nicht gelesen werden (F5 = erneut versuchen).'
        'scope.Woche' = 'Woche'
        'scope.Monat' = 'Monat'
        'scope.Jahr' = 'Jahr'
        'scope.Sonstiges' = 'Sonstiges'
        'todo.scopeTitle' = 'Todo: Zielgruppe (Woche/Monat/Jahr/Sonstiges)'
        'todo.showScope' = 'Todos anzeigen: Zielgruppe'
        'todo.descTitle' = 'Todo-Beschreibung'
        'todo.descLabel' = 'Bitte Beschreibung eingeben:'
        'todo.saved' = 'Todo gespeichert.'
        'todos.title' = 'Todos - {0}'
        'todos.none' = 'Keine offenen Todos in: {0}'
        'todos.loadError' = 'Fehler: todo.json konnte nicht gelesen werden.'
        'detail.title' = 'Todo: {0}'
        'detail.info' = "Ziel: {0}`r`nKategorie: {1} -> {2}`r`nTask: {3}`r`nAngelegt: {4}"
        'detail.move' = 'Verschieben'
        'detail.close' = 'Schließen'
        'detail.done' = 'Erledigt'
        'detail.moved' = 'Todo verschoben nach: {0}'
        'detail.gone' = 'Das Todo existiert nicht mehr (evtl. auf einem anderen Rechner entfernt).'
        'detail.alreadyDone' = 'Todo ist bereits erledigt.'
        'detail.booked' = 'Todo als erledigt verbucht.'
        'settings.title' = 'Einstellungen'
        'settings.user' = 'Name des Benutzers:'
        'settings.export' = 'Export-Pfad (Reports):'
        'settings.language' = 'Sprache:'
        'settings.browse' = 'Durchsuchen…'
        'settings.browseTitle' = 'Ordner für den Report-Export wählen'
        'settings.storedAt' = 'Lokal gespeichert in: {0}'
        'settings.columnsWorklog' = 'Spalten Worklog…'
        'settings.columnsTodo' = 'Spalten Todo-Report…'
        'settings.createDir' = "Der Ordner existiert nicht:`r`n{0}`r`n`r`nAnlegen?"
        'settings.createDirFailed' = 'Ordner konnte nicht angelegt werden: {0}'
        'export.title' = 'Reports exportieren'
        'export.needSettings' = 'Bitte zuerst in den Einstellungen Name und einen vorhandenen Export-Pfad hinterlegen.'
        'export.selectWeek' = 'Reports exportieren: Woche wählen'
        'export.done' = "Exportiert nach {0}:`r`n`r`n{1}"
        'export.failed' = "Export fehlgeschlagen:`r`n{0}"
        'export.kw' = 'KW'
        'export.fileWork' = 'Arbeitszeit'
        'export.fileTodos' = 'Todos'
        'columns.titleWorklog' = 'Spalten Worklog (CSV und Report)'
        'columns.titleTodo' = 'Spalten Todo-Report (Markdown)'
        'columns.add' = 'Hinzufügen…'
        'columns.remove' = 'Entfernen'
        'columns.up' = 'Nach oben'
        'columns.down' = 'Nach unten'
        'columns.header' = 'Überschrift…'
        'columns.format' = 'Format…'
        'columns.reset' = 'Standard'
        'columns.selectField' = 'Spalte hinzufügen'
        'columns.custom' = '[Eigenes Feld…]'
        'columns.customName' = 'Name des eigenen Feldes:'
        'columns.headerLabel' = 'Spaltenüberschrift:'
        'columns.formatLabel' = 'Format ({value} = Wert):'
        'columns.noteWorklog' = "Gilt für alle Rechner (columns.json im Datenordner). Neue Spalten werden ab dem nächsten Eintrag befüllt.`r`nEntfernte Spalten verschwinden beim nächsten Eintrag aus der aktuellen Wochendatei (Backup vorhanden)."
        'columns.noteTodo' = 'Jede Zeile: * Spalte1 | Spalte2 | ...   Gilt für alle Rechner (columns.json im Datenordner).'
        'columns.needWorklog' = 'Datum und eine Dauer-Spalte (Minuten oder h:mm) sind erforderlich.'
        'columns.needOne' = 'Mindestens eine Spalte ist erforderlich.'
        'field.Date' = 'Datum'
        'field.Weekday' = 'Wochentag'
        'field.StartTime' = 'Startzeit'
        'field.EndTime' = 'Endzeit'
        'field.Project' = 'Kategorie (Projekt)'
        'field.Category' = 'Unterkategorie (Tätigkeitskategorie)'
        'field.Description' = 'Task (Beschreibung)'
        'field.Minutes' = 'Dauer in Minuten'
        'field.Hours' = 'Dauer h:mm'
        'field.User' = 'Benutzer'
        'field.Path' = 'Kategorie->Unterkategorie'
        'field.TodoCategory' = 'Kategorie'
        'field.Subcategory' = 'Unterkategorie'
        'field.Task' = 'Task'
        'field.TodoDescription' = 'Beschreibung (1. Zeile)'
        'field.Scope' = 'Zielgruppe'
        'field.Created' = 'Angelegt (Datum)'
        'field.Id' = 'Id'
        'field.Custom' = 'Eigenes Feld: {0}'
        'weekdays' = 'Montag,Dienstag,Mittwoch,Donnerstag,Freitag,Samstag,Sonntag'
    }
    'en' = @{
        'app.title' = 'Work time'
        'menu.report' = 'Report'
        'menu.addTask' = 'Add task'
        'menu.addCat' = 'Add category/subcategory'
        'menu.remCat' = 'Remove category/subcategory'
        'menu.addTodo' = 'Add todo'
        'menu.todos' = 'Show todos'
        'menu.todoReport' = 'Todo report'
        'menu.export' = 'Export reports'
        'menu.settings' = 'Settings'
        'menu.recalc' = 'Recalculate today'
        'menu.exit' = 'Exit'
        'tray.today' = 'Today {0} min ({1})'
        'sel.category' = 'Select category'
        'sel.subcategory' = 'Select subcategory'
        'sel.task' = 'Select task'
        'sel.newTask' = '[Enter new task]'
        'dlg.newTask.title' = 'New task'
        'dlg.newTask.label' = 'Short description:'
        'dlg.minutes.title' = 'Duration'
        'dlg.minutes.label' = 'Effort/duration in minutes:'
        'dlg.start.title' = 'Start time'
        'dlg.start.label' = 'Start time (HH:MM):'
        'btn.ok' = 'OK'
        'btn.cancel' = 'Cancel'
        'btn.save' = 'Save'
        'btn.select' = 'Select'
        'msg.info' = 'Info'
        'msg.hint' = 'Note'
        'msg.error' = 'Error'
        'msg.question' = 'Question'
        'msg.needCats' = 'Please create categories/subcategories first.'
        'msg.noSubs' = 'This category has no subcategory yet.'
        'msg.invalidEntry' = 'Please specify category, subcategory and minutes correctly.'
        'msg.invalidMinutes' = 'Please enter a valid number of minutes.'
        'msg.invalidTime' = 'Please enter a valid time in the format HH:MM.'
        'msg.loadError' = "The file could not be read:`r`n{0}`r`n`r`nIt may currently be synchronising or it is damaged.`r`nThe change was NOT saved, so that no data is overwritten.`r`nPlease try again later (backups are in the subfolder 'backups')."
        'msg.saveError' = "The file could not be saved:`r`n{0}`r`n`r`nPlease try again later."
        'cat.new' = '[Create new category]'
        'cat.newTitle' = 'New category'
        'cat.newLabel' = 'Name of the new category:'
        'cat.subTitle' = 'Add subcategory'
        'cat.subLabel' = 'Name of the subcategory for ''{0}'':'
        'cat.remSelect' = 'Select category to remove'
        'cat.remSub' = 'Remove subcategory'
        'cat.remAll' = '[Remove entire category]'
        'week.select' = 'Select week'
        'week.label' = 'CW {0} / {1}   ({2} .. {3})'
        'report.title' = 'Report - CW {0}: {1}  ({2} .. {3})  F5 = refresh'
        'report.noEntries' = 'No entries in this week.'
        'report.noData' = 'No data available.'
        'todoReport.title' = 'Todo report (Markdown)  F5 = refresh'
        'todoReport.kw' = '# CW {0}'
        'todoReport.week' = '## Week'
        'todoReport.month' = '## Month ({0})'
        'todoReport.year' = '## Year ({0})'
        'todoReport.emptyWeek' = '* No open todos in the current week.'
        'todoReport.emptyMonth' = '* No open todos in the current month.'
        'todoReport.emptyYear' = '* No open todos in the current year.'
        'todoReport.loadError' = 'Error: todo.json could not be read (F5 = try again).'
        'scope.Woche' = 'Week'
        'scope.Monat' = 'Month'
        'scope.Jahr' = 'Year'
        'scope.Sonstiges' = 'Other'
        'todo.scopeTitle' = 'Todo: scope (week/month/year/other)'
        'todo.showScope' = 'Show todos: scope'
        'todo.descTitle' = 'Todo description'
        'todo.descLabel' = 'Please enter a description:'
        'todo.saved' = 'Todo saved.'
        'todos.title' = 'Todos - {0}'
        'todos.none' = 'No open todos in: {0}'
        'todos.loadError' = 'Error: todo.json could not be read.'
        'detail.title' = 'Todo: {0}'
        'detail.info' = "Scope: {0}`r`nCategory: {1} -> {2}`r`nTask: {3}`r`nCreated: {4}"
        'detail.move' = 'Move'
        'detail.close' = 'Close'
        'detail.done' = 'Done'
        'detail.moved' = 'Todo moved to: {0}'
        'detail.gone' = 'This todo no longer exists (possibly removed on another computer).'
        'detail.alreadyDone' = 'This todo is already done.'
        'detail.booked' = 'Todo marked as done and booked.'
        'settings.title' = 'Settings'
        'settings.user' = 'User name:'
        'settings.export' = 'Export path (reports):'
        'settings.language' = 'Language:'
        'settings.browse' = 'Browse…'
        'settings.browseTitle' = 'Select folder for the report export'
        'settings.storedAt' = 'Stored locally in: {0}'
        'settings.columnsWorklog' = 'Worklog columns…'
        'settings.columnsTodo' = 'Todo report columns…'
        'settings.createDir' = "The folder does not exist:`r`n{0}`r`n`r`nCreate it?"
        'settings.createDirFailed' = 'The folder could not be created: {0}'
        'export.title' = 'Export reports'
        'export.needSettings' = 'Please set a user name and an existing export path in the settings first.'
        'export.selectWeek' = 'Export reports: select week'
        'export.done' = "Exported to {0}:`r`n`r`n{1}"
        'export.failed' = "Export failed:`r`n{0}"
        'export.kw' = 'CW'
        'export.fileWork' = 'Worktime'
        'export.fileTodos' = 'Todos'
        'columns.titleWorklog' = 'Worklog columns (CSV and report)'
        'columns.titleTodo' = 'Todo report columns (Markdown)'
        'columns.add' = 'Add…'
        'columns.remove' = 'Remove'
        'columns.up' = 'Move up'
        'columns.down' = 'Move down'
        'columns.header' = 'Header…'
        'columns.format' = 'Format…'
        'columns.reset' = 'Default'
        'columns.selectField' = 'Add column'
        'columns.custom' = '[Custom field…]'
        'columns.customName' = 'Name of the custom field:'
        'columns.headerLabel' = 'Column header:'
        'columns.formatLabel' = 'Format ({value} = value):'
        'columns.noteWorklog' = "Applies to all computers (columns.json in the data folder). New columns are filled from the next entry on.`r`nRemoved columns disappear from the current week file with the next entry (backup available)."
        'columns.noteTodo' = 'Each line: * column1 | column2 | ...   Applies to all computers (columns.json in the data folder).'
        'columns.needWorklog' = 'Date and a duration column (minutes or h:mm) are required.'
        'columns.needOne' = 'At least one column is required.'
        'field.Date' = 'Date'
        'field.Weekday' = 'Weekday'
        'field.StartTime' = 'Start time'
        'field.EndTime' = 'End time'
        'field.Project' = 'Category (project)'
        'field.Category' = 'Subcategory (activity category)'
        'field.Description' = 'Task (description)'
        'field.Minutes' = 'Duration in minutes'
        'field.Hours' = 'Duration h:mm'
        'field.User' = 'User'
        'field.Path' = 'Category->Subcategory'
        'field.TodoCategory' = 'Category'
        'field.Subcategory' = 'Subcategory'
        'field.Task' = 'Task'
        'field.TodoDescription' = 'Description (1st line)'
        'field.Scope' = 'Scope'
        'field.Created' = 'Created (date)'
        'field.Id' = 'Id'
        'field.Custom' = 'Custom field: {0}'
        'weekdays' = 'Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday'
    }
}

function Get-DefaultLanguage {
    try { if ((Get-Culture).TwoLetterISOLanguageName -eq "de") { return "de" } else { return "en" } } catch { return "de" }
}
$global:settings = @{ UserName = [string]$env:USERNAME; ExportPath = ""; Language = (Get-DefaultLanguage) }

function T([string]$key) {
    $lang = [string]$global:settings.Language
    if (-not $global:Strings.ContainsKey($lang)) { $lang = "de" }
    $s = $global:Strings[$lang][$key]
    if ($null -eq $s) { $s = $global:Strings["de"][$key] }
    if ($null -eq $s) { $s = $key }
    if ($args.Count -gt 0) { return ($s -f $args) }
    return $s
}
function Get-ScopeLabel([string]$scope) {
    if ($global:Scopes -contains $scope) { return (T ("scope." + $scope)) }
    return $scope
}

# -----------------------------------------------------------------------------
# Tray-Status / Meldungen
# -----------------------------------------------------------------------------
function Set-TrayStatus([string]$msg) {
    try {
        if ($global:trayIcon) {
            $t = ("{0}: {1}" -f (T "app.title"), $msg)
            if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }   # NotifyIcon.Text max. 63 Zeichen
            $global:trayIcon.Text = $t
        }
    } catch {}
}
function Show-Info([string]$text, [string]$title) {
    if (-not $title) { $title = T "msg.info" }
    [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
function Show-Error([string]$text, [string]$title) {
    if (-not $title) { $title = T "msg.error" }
    [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
function Show-LoadError([string]$path) { Show-Error (T "msg.loadError" $path) }
function Show-SaveError([string]$path) { Show-Error (T "msg.saveError" $path) }

# ---------------------------------------------
# Datei-IO-Hilfsfunktionen (Temp/Backups/Retries)
# ---------------------------------------------
function New-BackupRotating([string]$targetPath) {
    try {
        if (-not [System.IO.File]::Exists($targetPath)) { return }
        $backupDir = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($targetPath), "backups")
        if (-not [System.IO.Directory]::Exists($backupDir)) { [System.IO.Directory]::CreateDirectory($backupDir) | Out-Null }
        $name = [System.IO.Path]::GetFileName($targetPath)
        $keep = 10
        try { if ($null -ne $global:BackupKeep) { $keep = [int]$global:BackupKeep } } catch {}
        if ($keep -lt 1) { $keep = 1 }
        $oldest = [System.IO.Path]::Combine($backupDir, ("{0}.{1}" -f $name, ($keep - 1)))
        if ([System.IO.File]::Exists($oldest)) { [System.IO.File]::Delete($oldest) }
        for ($i = $keep - 2; $i -ge 0; $i--) {
            $src = [System.IO.Path]::Combine($backupDir, ("{0}.{1}" -f $name, $i))
            $dst = [System.IO.Path]::Combine($backupDir, ("{0}.{1}" -f $name, ($i + 1)))
            try {
                if ([System.IO.File]::Exists($src)) {
                    if ([System.IO.File]::Exists($dst)) { [System.IO.File]::Delete($dst) }
                    [System.IO.File]::Move($src, $dst)
                }
            } catch { Log ("Backup Rotation FEHLER: {0}" -f $_.Exception.Message) }
        }
        [System.IO.File]::Copy($targetPath, [System.IO.Path]::Combine($backupDir, ("{0}.0" -f $name)), $true)
    } catch {
        Log ("New-BackupRotating FEHLER: {0}" -f $_.Exception.Message)
    }
}

# Rückgabe: @{ Ok; Exists; Content }  -  Ok=$false: Datei existiert, nicht lesbar -> NICHT überschreiben!
function SafeRead-TextFile([string]$path, [int]$MaxRetries = 10, [int]$DelayMs = 300, [switch]$AllowEmpty) {
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $fs = $null; $sr = $null
        try {
            if (-not [System.IO.File]::Exists($path)) { return @{ Ok = $true; Exists = $false; Content = $null } }
            $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
            $content = $sr.ReadToEnd()
            if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($content)) { throw "Datei ist leer." }
            return @{ Ok = $true; Exists = $true; Content = $content }
        } catch {
            Log ("SafeRead: {0} Versuch {1} FEHLER {2}" -f $path, $attempt, $_.Exception.Message)
            Start-Sleep -Milliseconds $DelayMs
        } finally {
            if ($sr) { $sr.Dispose() }
            if ($fs) { $fs.Dispose() }
        }
    }
    Set-TrayStatus ("! {0}" -f [IO.Path]::GetFileName($path))
    return @{ Ok = $false; Exists = $true; Content = $null }
}

# Schreibt alle Zeilen (CRLF, UTF-8 mit BOM). Temp "~*.tmp" im Zielordner (Nextcloud ignoriert das), dann atomarer Austausch.
function SafeWrite-TextFile([string]$targetPath, [string[]]$lines, [int]$MaxRetries = 20, [int]$DelayMs = 300) {
    $text = ([string]::Join("`r`n", $lines)) + "`r`n"
    $dir  = [System.IO.Path]::GetDirectoryName($targetPath)
    $name = [System.IO.Path]::GetFileName($targetPath)
    if (-not [System.IO.Directory]::Exists($dir)) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }
    if ([System.IO.File]::Exists($targetPath)) { New-BackupRotating $targetPath }   # einmal pro Schreibvorgang
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $tempPath = [System.IO.Path]::Combine($dir, ("~{0}.{1}.tmp" -f $name, [IO.Path]::GetRandomFileName()))
        try {
            [System.IO.File]::WriteAllText($tempPath, $text, $global:Utf8Bom)
            if ([System.IO.File]::Exists($targetPath)) {
                [System.IO.File]::Replace($tempPath, $targetPath, [NullString]::Value)
            } else {
                [System.IO.File]::Move($tempPath, $targetPath)
            }
            return $true
        } catch {
            Log ("SafeWrite: {0} Versuch {1} FEHLER {2}" -f $targetPath, $attempt, $_.Exception.Message)
            Set-TrayStatus ("Speichern blockiert {0} ({1})" -f $name, $attempt)
            Start-Sleep -Milliseconds $DelayMs
        } finally {
            try { if ([System.IO.File]::Exists($tempPath)) { [System.IO.File]::Delete($tempPath) } } catch {}
        }
    }
    return $false
}

function SafeWrite-Json([string]$targetPath, $obj, [int]$Depth = 6) {
    try { $json = ConvertTo-Json $obj -Depth $Depth }
    catch { Log ("SafeWrite-Json: FEHLER {0}" -f $_.Exception.Message); return $false }
    return (SafeWrite-TextFile -targetPath $targetPath -lines @($json))
}
# Rückgabe: @{ Ok; Obj }  (Obj = $null wenn Datei fehlt)
function SafeRead-Json([string]$path) {
    $r = SafeRead-TextFile -path $path
    if (-not $r.Ok) { return @{ Ok = $false; Obj = $null } }
    if (-not $r.Exists) { return @{ Ok = $true; Obj = $null } }
    try { return @{ Ok = $true; Obj = (ConvertFrom-Json $r.Content) } }
    catch { Log ("SafeRead-Json: Parse FEHLER {0}" -f $path); return @{ Ok = $false; Obj = $null } }
}

# -----------------------------------------------------------------------------
# Einstellungen (lokal pro Rechner)
# -----------------------------------------------------------------------------
function Load-Settings {
    $s = @{ UserName = [string]$env:USERNAME; ExportPath = ""; Language = (Get-DefaultLanguage) }
    $r = SafeRead-Json -path $settingsFile
    if ($r.Ok -and $r.Obj) {
        foreach ($k in @("UserName", "ExportPath", "Language")) {
            if ($null -ne $r.Obj.$k) { $s[$k] = [string]$r.Obj.$k }
        }
    }
    if (-not $global:Strings.ContainsKey($s.Language)) { $s.Language = "de" }
    $global:settings = $s
    return $s
}
function Save-Settings($s) {
    $ok = SafeWrite-Json -targetPath $settingsFile -obj ([ordered]@{ UserName = $s.UserName; ExportPath = $s.ExportPath; Language = $s.Language }) -Depth 3
    if (-not $ok) { Show-SaveError $settingsFile } else { $global:settings = $s }
    return $ok
}

# -----------------------------------------------------------------------------
# Spalten (columns.json im Datenordner, gilt für alle Rechner)
# -----------------------------------------------------------------------------
$global:WlFields   = @("Date", "Weekday", "StartTime", "EndTime", "Project", "Category", "Description", "Minutes", "Hours", "User")
$global:WlHeaders  = @{
    de = @{ Date = "Datum"; Weekday = "Wochentag"; StartTime = "Startzeit"; EndTime = "Endzeit"; Project = "Projekt oder IT-Service"; Category = "Tätigkeitskategorie"; Description = "kurze Tätigkeitsbeschreibung"; Minutes = "Aufwand bzw. Dauer"; Hours = "Dauer (h:mm)"; User = "Benutzer" }
    en = @{ Date = "Date"; Weekday = "Weekday"; StartTime = "Start time"; EndTime = "End time"; Project = "Project or IT service"; Category = "Activity category"; Description = "Short activity description"; Minutes = "Effort / duration"; Hours = "Duration (h:mm)"; User = "User" }
}
$global:WlDefault   = @("Date", "Project", "Category", "Description", "Minutes")
$global:TodoFields  = @("Path", "TodoCategory", "Subcategory", "Task", "TodoDescription", "Scope", "Created", "Id")
$global:TodoDefault = @(@("Path", "{value}"), @("Task", "{value}"), @("Created", "({value})"))
$global:SumFields   = @("Minutes", "Hours")

function Get-WlHeaderTable { $l = [string]$global:settings.Language; if (-not $global:WlHeaders.ContainsKey($l)) { $l = "de" }; return $global:WlHeaders[$l] }
function Test-CustomField([string]$f) { return $f.StartsWith("Custom:") }
function Get-CustomName([string]$f) { return $f.Substring(7) }
function Get-FieldDisplay([string]$f) {
    if (Test-CustomField $f) { return (T "field.Custom" (Get-CustomName $f)) }
    return (T ("field." + $f))
}
function Get-DefaultColumns {
    $h = Get-WlHeaderTable
    $wl = @(); foreach ($f in $global:WlDefault) { $wl += [ordered]@{ Field = $f; Header = $h[$f] } }
    $td = @(); foreach ($p in $global:TodoDefault) { $td += [ordered]@{ Field = $p[0]; Format = $p[1] } }
    return @{ Worklog = $wl; Todo = $td }
}
function Test-ValidField([string]$f, [string]$kind) {
    if ([string]::IsNullOrEmpty($f)) { return $false }
    if (Test-CustomField $f) { return -not [string]::IsNullOrWhiteSpace((Get-CustomName $f)) }
    if ($kind -eq "Worklog") { return ($global:WlFields -ccontains $f) }
    return ($global:TodoFields -ccontains $f)
}
# Rückgabe: @{ Worklog = @(ordered{Field;Header}); Todo = @(ordered{Field;Format}) }
function Load-Columns {
    $d = Get-DefaultColumns
    $r = SafeRead-Json -path $columnsFile
    $obj = if ($r.Ok) { $r.Obj } else { $null }
    $wl = @(); $td = @()
    if ($obj) {
        foreach ($c in @($obj.Worklog)) {
            if ($null -eq $c) { continue }
            $f = [string]$c.Field
            if (-not (Test-ValidField $f "Worklog")) { continue }
            $hdr = [string]$c.Header
            if (-not $hdr) { if (Test-CustomField $f) { $hdr = Get-CustomName $f } else { $hdr = (Get-WlHeaderTable)[$f] } }
            $wl += [ordered]@{ Field = $f; Header = $hdr }
        }
        foreach ($c in @($obj.Todo)) {
            if ($null -eq $c) { continue }
            $f = [string]$c.Field
            if (-not (Test-ValidField $f "Todo")) { continue }
            $fmt = [string]$c.Format
            if (-not $fmt) { $fmt = "{value}" }
            $td += [ordered]@{ Field = $f; Format = $fmt }
        }
    }
    if ($wl.Count -eq 0) { $wl = $d.Worklog }
    if ($td.Count -eq 0) { $td = $d.Todo }
    return @{ Worklog = $wl; Todo = $td }
}
function Save-ColumnsPart([string]$kind, $cols) {
    $cur = Load-Columns
    $cur[$kind] = @($cols)
    $ok = SafeWrite-Json -targetPath $columnsFile -obj ([ordered]@{ Worklog = @($cur.Worklog); Todo = @($cur.Todo) }) -Depth 5
    if (-not $ok) { Show-SaveError $columnsFile }
    return $ok
}

# -----------------------------------------------------------------------------
# Laden/Speichern: Kategorien und Taskkatalog (Load-* gibt $true/$false zurück)
# -----------------------------------------------------------------------------
function Save-Categories {
    $ok = SafeWrite-Json -targetPath $catsFile -obj @{ "Categories" = $global:categories; "Focus" = $global:lastSelectedIndices } -Depth 5
    if (-not $ok) { Show-SaveError $catsFile }
    return $ok
}
function Load-Categories {
    $r = SafeRead-Json -path $catsFile
    if (-not $r.Ok) { return $false }
    $cats = @{}; $focus = @{}
    $obj = $r.Obj
    if ($obj -and $obj.Categories) {
        foreach ($prop in $obj.Categories.psobject.Properties) {
            $subs = @()
            foreach ($s in @($prop.Value)) { if ($null -ne $s) { $subs += [string]$s } }
            $cats[$prop.Name] = $subs
        }
    }
    if ($obj -and $obj.Focus) { foreach ($prop in $obj.Focus.psobject.Properties) { $focus[$prop.Name] = $prop.Value } }
    $global:categories = $cats
    $global:lastSelectedIndices = $focus
    return $true
}
function Save-TaskCatalog {
    $ok = SafeWrite-Json -targetPath $taskCatalogFile -obj @{ "Tasks" = $global:taskCatalog } -Depth 5
    if (-not $ok) { Show-SaveError $taskCatalogFile }
    return $ok
}
function Load-TaskCatalog {
    $r = SafeRead-Json -path $taskCatalogFile
    if (-not $r.Ok) { return $false }
    $cat = @{}
    if ($r.Obj -and $r.Obj.Tasks) {
        foreach ($prop in $r.Obj.Tasks.psobject.Properties) {
            $vals = @()
            foreach ($x in @($prop.Value)) { if ($null -ne $x) { $vals += [string]$x } }
            $cat[$prop.Name] = $vals
        }
    }
    $global:taskCatalog = $cat
    return $true
}
function Add-TaskToCatalog([string]$key, [string]$taskDesc) {
    if (-not (Load-TaskCatalog)) { Show-LoadError $taskCatalogFile; return $false }
    $existing = @()
    if ($global:taskCatalog.ContainsKey($key)) { $existing = @($global:taskCatalog[$key]) }
    if ($existing -contains $taskDesc) { return $true }
    $global:taskCatalog[$key] = $existing + $taskDesc
    return (Save-TaskCatalog)
}

# -----------------------------------------------------------------------------
# Todos Laden/Speichern (JSON)
# -----------------------------------------------------------------------------
function ConvertTo-DateOrNull($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) { return $v }
    $s = [string]$v
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try { return [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
    try { return [datetime]$s } catch {}
    return $null
}
function Save-Todos {
    $norm = @()
    foreach ($x in $global:todos) {
        $created = ConvertTo-DateOrNull $x.Created
        $doneDt  = ConvertTo-DateOrNull $x.DoneDate
        $extra = [ordered]@{}
        if ($x.Extra) { foreach ($k in $x.Extra.Keys) { $extra[[string]$k] = [string]$x.Extra[$k] } }
        $norm += [pscustomobject][ordered]@{
            Id = [string]$x.Id; Scope = [string]$x.Scope; Category = [string]$x.Category; Subcategory = [string]$x.Subcategory
            Task = [string]$x.Task; Description = [string]$x.Description
            Created = if ($created) { $created.ToString("o") } else { $null }
            Done = [bool]$x.Done
            DoneMinutes = if ($null -ne $x.DoneMinutes) { [int]$x.DoneMinutes } else { $null }
            DoneDate = if ($doneDt) { $doneDt.ToString("o") } else { $null }
            Extra = $extra
        }
    }
    $ok = SafeWrite-Json -targetPath $todosFile -obj @{ "Todos" = $norm } -Depth 6
    if (-not $ok) { Show-SaveError $todosFile }
    return $ok
}
function Load-Todos {
    $r = SafeRead-Json -path $todosFile
    if (-not $r.Ok) { return $false }
    $list = @()
    if ($r.Obj -and $r.Obj.Todos) {
        foreach ($x in @($r.Obj.Todos)) {
            try {
                $extra = @{}
                if ($x.Extra) { foreach ($p in $x.Extra.psobject.Properties) { $extra[$p.Name] = [string]$p.Value } }
                $list += @{
                    Id = [string]$x.Id; Scope = [string]$x.Scope; Category = [string]$x.Category; Subcategory = [string]$x.Subcategory
                    Task = [string]$x.Task; Description = [string]$x.Description
                    Created = ConvertTo-DateOrNull $x.Created; Done = [bool]$x.Done
                    DoneMinutes = if ($null -ne $x.DoneMinutes) { [int]$x.DoneMinutes } else { $null }
                    DoneDate = ConvertTo-DateOrNull $x.DoneDate
                    Extra = $extra
                }
            } catch { Log ("Load-Todos: Eintrag fehlerhaft: {0}" -f $_.Exception.Message) }
        }
    }
    $global:todos = $list
    return $true
}
# Frisch laden -> per Id ändern -> speichern. Rückgabe: $true / $false / "notfound"
function Update-TodoById([string]$todoId, [scriptblock]$Change) {
    if (-not (Load-Todos)) { Show-LoadError $todosFile; return $false }
    $x = $global:todos | Where-Object { $_.Id -eq $todoId } | Select-Object -First 1
    if (-not $x) { return "notfound" }
    $res = & $Change $x
    if ($res -eq $false) { return $false }
    return (Save-Todos)
}

# -----------------------------------------------------------------------------
# Woche (Montag..Sonntag) und Wochen-Datei
# -----------------------------------------------------------------------------
function Get-WeekMonday([datetime]$baseDate = (Get-Date)) {
    $dow = [int]$baseDate.DayOfWeek
    $offset = if ($dow -eq 0) { -6 } else { 1 - $dow }
    return $baseDate.Date.AddDays($offset)
}
function Get-WeekFile([datetime]$baseDate = (Get-Date)) {
    return (Join-Path $tasksDir ("{0:yyyy-MM-dd}_worklog.csv" -f (Get-WeekMonday $baseDate)))
}
# ISO-8601-Kalenderwoche: maßgeblich ist der Donnerstag der Woche
function Get-IsoWeekNumber([datetime]$dt) {
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    return $cal.GetWeekOfYear((Get-WeekMonday $dt).AddDays(3), [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
}
function Get-IsoWeekYear([datetime]$dt) { return (Get-WeekMonday $dt).AddDays(3).Year }
# Anzeige in Dialogen: zuerst KW, dann Zeitraum
function Format-WeekLabel([datetime]$monday) {
    return (T "week.label" ("{0:00}" -f (Get-IsoWeekNumber $monday)) (Get-IsoWeekYear $monday) $monday.ToString("yyyy-MM-dd") $monday.AddDays(6).ToString("yyyy-MM-dd"))
}
function To-HhMm([int]$mins) { return ("{0}:{1:00}" -f [int][math]::Floor($mins / 60), ($mins % 60)) }
function Parse-HhMm([string]$s) {
    if ($s -match '^\s*(\d{1,3}):(\d{2})\s*$' -and [int]$Matches[2] -le 59) { return ([int]$Matches[1] * 60 + [int]$Matches[2]) }
    return $null
}
function Parse-Clock([string]$s) {
    if ($s -match '^\s*(\d{1,2}):(\d{2})\s*$' -and [int]$Matches[1] -le 23 -and [int]$Matches[2] -le 59) { return ("{0:00}:{1:00}" -f [int]$Matches[1], [int]$Matches[2]) }
    return $null
}

# -----------------------------------------------------------------------------
# Worklog-CSV (Spalten werden beim Lesen über die Kopfzeile erkannt)
# -----------------------------------------------------------------------------
# Trennt Zeilen, die das alte Script (<= 2.1.21) zusammengeklebt hat
function Split-GluedWorklogLines([string[]]$lines) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $lines) {
        if ($null -eq $ln) { continue }
        foreach ($p in [regex]::Split($ln, '(?<=\d|Dauer)(?=\d{4}-\d{2}-\d{2};)')) { $out.Add($p) }
    }
    return $out.ToArray()
}
# Rückgabe: @{ Ok; Lines }
function Read-WorklogLines([string]$f) {
    $r = SafeRead-TextFile -path $f -AllowEmpty
    if (-not $r.Ok) { return @{ Ok = $false; Lines = @() } }
    if (-not $r.Exists -or [string]::IsNullOrEmpty($r.Content)) { return @{ Ok = $true; Lines = @() } }
    $lines = @(Split-GluedWorklogLines ($r.Content -split "\r?\n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return @{ Ok = $true; Lines = $lines }
}
function Get-HeaderFieldMap($cols) {
    $m = @{}
    foreach ($lang in @("en", "de")) { foreach ($k in $global:WlHeaders[$lang].Keys) { $m[$global:WlHeaders[$lang][$k].ToLowerInvariant()] = $k } }
    foreach ($f in $global:WlFields) { $m[$f.ToLowerInvariant()] = $f }
    foreach ($c in $cols) { $m[([string]$c.Header).Trim().ToLowerInvariant()] = $c.Field }
    return $m
}
# Rückgabe: @{ Ok; Rows = @(hashtable) }
function Read-WorklogRows([string]$f, $cols) {
    $r = Read-WorklogLines $f
    if (-not $r.Ok) { return @{ Ok = $false; Rows = @() } }
    $rows = @()
    if ($r.Lines.Count -eq 0) { return @{ Ok = $true; Rows = $rows } }
    $first = $r.Lines[0].Split(';')
    if ($first[0] -match '^\s*\d{4}-\d{2}-\d{2}\s*$') {
        $fields = $global:WlDefault; $data = $r.Lines          # ohne Kopfzeile -> Standardlayout
    } else {
        $hmap = Get-HeaderFieldMap $cols
        $fields = @()
        foreach ($h in $first) {
            $key = $h.Trim()
            if ($hmap.ContainsKey($key.ToLowerInvariant())) { $fields += $hmap[$key.ToLowerInvariant()] }
            elseif ($key) { $fields += ("Custom:" + $key) } else { $fields += "" }
        }
        $data = @($r.Lines | Select-Object -Skip 1)
    }
    foreach ($ln in $data) {
        $cells = $ln.Split(';')
        $raw = @{}
        for ($i = 0; $i -lt $fields.Count; $i++) { if ($fields[$i] -and $i -lt $cells.Count) { $raw[$fields[$i]] = $cells[$i].Trim() } }
        $dval = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$raw["Date"], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dval)) {
            if (-not [datetime]::TryParse([string]$raw["Date"], [ref]$dval)) { continue }
        }
        $mins = $null
        $mi = 0
        if ($raw["Minutes"] -and [int]::TryParse($raw["Minutes"], [ref]$mi)) { $mins = $mi }
        if ($null -eq $mins -and $raw["Hours"]) { $mins = Parse-HhMm $raw["Hours"] }
        if ($null -eq $mins) { $mins = 0 }
        $st = Parse-Clock ([string]$raw["StartTime"]); if (-not $st) { $st = "" }
        $et = Parse-Clock ([string]$raw["EndTime"]);   if (-not $et) { $et = "" }
        $row = @{ Date = $dval.Date; StartTime = $st; EndTime = $et; Project = [string]$raw["Project"]; Category = [string]$raw["Category"]
                  Description = [string]$raw["Description"]; Minutes = [int]$mins; User = [string]$raw["User"] }
        foreach ($k in $raw.Keys) { if (Test-CustomField $k) { $row[$k] = $raw[$k] } }
        $rows += $row
    }
    return @{ Ok = $true; Rows = $rows }
}
function Get-EndTime($row) {
    if ($row.EndTime) { return $row.EndTime }
    if ($row.StartTime) {
        $p = $row.StartTime.Split(':')
        $tot = ([int]$p[0] * 60 + [int]$p[1] + [int]$row.Minutes) % 1440
        return ("{0:00}:{1:00}" -f [int][math]::Floor($tot / 60), ($tot % 60))
    }
    return ""
}
function Get-WlValue($row, [string]$field) {
    switch -CaseSensitive ($field) {
        "Date"    { return $row.Date.ToString("yyyy-MM-dd") }
        "Weekday" { return (T "weekdays").Split(',')[(([int]$row.Date.DayOfWeek) + 6) % 7] }
        "EndTime" { return (Get-EndTime $row) }
        "Minutes" { return ([string][int]$row.Minutes) }
        "Hours"   { return (To-HhMm ([int]$row.Minutes)) }
    }
    $v = $row[$field]
    if ($null -eq $v) { return "" }
    return [string]$v
}
function Clean-CsvField([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace '[;\r\n]+', ',').Trim()
}
function Format-WlHeader($cols) { return (($cols | ForEach-Object { Clean-CsvField $_.Header }) -join ";") }
function Format-WlRow($row, $cols) { return (($cols | ForEach-Object { Clean-CsvField (Get-WlValue $row $_.Field) }) -join ";") }

# Eintrag anhängen: frisch lesen -> Zeile ergänzen -> Datei im aktuellen Spaltenlayout schreiben
function Write-TaskEntry([datetime]$date, [string]$project, [string]$category, [string]$desc, [int]$minutes, $extras = $null) {
    $cols = @((Load-Columns).Worklog)
    $f = Get-WeekFile $date
    $r = Read-WorklogRows $f $cols
    if (-not $r.Ok) { Show-LoadError $f; return $false }
    $row = @{ Date = $date.Date; StartTime = ""; EndTime = ""; Project = $project; Category = $category; Description = $desc; Minutes = $minutes; User = [string](Load-Settings).UserName }
    if ($extras) { foreach ($k in $extras.Keys) { $row[$k] = $extras[$k] } }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((Format-WlHeader $cols))
    foreach ($x in (@($r.Rows) + $row)) { $lines.Add((Format-WlRow $x $cols)) }
    $ok = SafeWrite-TextFile -targetPath $f -lines $lines.ToArray()
    if (-not $ok) { Show-SaveError $f }
    return $ok
}
function Repair-AllWorklogs {
    if (-not (Test-Path $tasksDir)) { return 0 }
    $fixed = 0
    foreach ($fi in Get-ChildItem -Path $tasksDir -Filter "*_worklog.csv" -File) {
        $r = SafeRead-TextFile -path $fi.FullName -AllowEmpty
        if (-not $r.Ok -or -not $r.Exists -or [string]::IsNullOrEmpty($r.Content)) { continue }
        $raw   = @($r.Content -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $split = @(Split-GluedWorklogLines $raw | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($split.Count -ne $raw.Count) {
            Log ("Repariere {0}: {1} -> {2} Zeilen" -f $fi.Name, $raw.Count, $split.Count)
            if (SafeWrite-TextFile -targetPath $fi.FullName -lines $split) { $fixed++ }
        }
    }
    return $fixed
}

# -----------------------------------------------------------------------------
# Summen, Reports
# -----------------------------------------------------------------------------
function Get-TodayTotals() {
    $today = (Get-Date).Date
    $sum = 0
    foreach ($x in (Read-WorklogRows (Get-WeekFile $today) @((Load-Columns).Worklog)).Rows) { if ($x.Date -eq $today) { $sum += $x.Minutes } }
    return $sum
}
function Update-TrayText() {
    if ($global:trayIcon) {
        $mins = Get-TodayTotals
        Set-TrayStatus (T "tray.today" $mins (To-HhMm $mins))
    }
}

# Report im konfigurierten Spaltenlayout: Zeilen mit gleichen Werten (außer Dauer) werden summiert.
# Rückgabe: @{ Lines; Minutes; HasEntries; FileExists }
function Get-WeekReport([datetime]$WeekMonday) {
    $cols = @((Load-Columns).Worklog)
    $f = Get-WeekFile $WeekMonday
    $rows = @((Read-WorklogRows $f $cols).Rows)
    $keyFields = @($cols | ForEach-Object { $_.Field } | Where-Object { $global:SumFields -notcontains $_ })
    $order = @("Date", "StartTime") + @($keyFields | Where-Object { $_ -ne "Date" -and $_ -ne "StartTime" })
    $sortFields = @($order | Where-Object { $keyFields -contains $_ -or $_ -eq "Date" })
    $acc = [ordered]@{}
    $total = 0
    foreach ($x in $rows) {
        $k = (($keyFields | ForEach-Object { Get-WlValue $x $_ }) -join [char]0x1f)
        if (-not $acc.Contains($k)) { $b = @{}; foreach ($kk in $x.Keys) { $b[$kk] = $x[$kk] }; $b.Minutes = 0; $acc[$k] = $b }
        $acc[$k].Minutes += $x.Minutes
        $total += $x.Minutes
    }
    $sortKeys = New-Object System.Collections.Generic.List[string]
    $lineByKey = @{}
    $i = 0
    foreach ($b in $acc.Values) {
        if ($keyFields -notcontains "EndTime") { $b.EndTime = "" }
        $sk = ((($sortFields | ForEach-Object { Get-WlValue $b $_ }) -join [char]0x1f).ToUpperInvariant()) + [char]0x1e + $i
        $sortKeys.Add($sk); $lineByKey[$sk] = (Format-WlRow $b $cols); $i++
    }
    $arr = $sortKeys.ToArray()
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    $lines = @(Format-WlHeader $cols)
    foreach ($sk in $arr) { $lines += $lineByKey[$sk] }
    return @{ Lines = $lines; Minutes = $total; HasEntries = ($rows.Count -gt 0); FileExists = (Test-Path $f) }
}

function Get-OpenTodos([string]$scope) {
    return @($global:todos | Where-Object { $_.Scope -eq $scope -and -not $_.Done } | Sort-Object { $null -ne $_.Created }, { $_.Created })
}
function Get-TodoValue($x, [string]$field) {
    switch -CaseSensitive ($field) {
        "Path"            { return ("{0}->{1}" -f $x.Category, $x.Subcategory) }
        "TodoCategory"    { return [string]$x.Category }
        "TodoDescription" { return ([string]$x.Description -split "\r?\n")[0] }
        "Scope"           { return (Get-ScopeLabel $x.Scope) }
        "Created"         { if ($x.Created) { return $x.Created.ToString("yyyy-MM-dd") } else { return "" } }
    }
    if (Test-CustomField $field) {
        $n = Get-CustomName $field
        if ($x.Extra -and $x.Extra.ContainsKey($n)) { return [string]$x.Extra[$n] }
        return ""
    }
    return [string]$x[$field]
}
function Format-TodoLine($x, $cols) {
    return ("* " + (($cols | ForEach-Object { ([string]$_.Format).Replace("{value}", (Get-TodoValue $x $_.Field)) }) -join " | "))
}
# Todo-Report (Markdown) - nur Woche/Monat/Jahr; vorher Load-Todos aufrufen
function Get-TodoReportLines([datetime]$refDate = (Get-Date)) {
    $cols = @((Load-Columns).Todo)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((T "todoReport.kw" (Get-IsoWeekNumber $refDate)))
    $sections = @(
        @("Woche", (T "todoReport.week"), (T "todoReport.emptyWeek")),
        @("Monat", (T "todoReport.month" $refDate.ToString("yyyy-MM")), (T "todoReport.emptyMonth")),
        @("Jahr",  (T "todoReport.year" $refDate.ToString("yyyy")), (T "todoReport.emptyYear"))
    )
    foreach ($s in $sections) {
        $lines.Add(""); $lines.Add($s[1])
        $items = Get-OpenTodos $s[0]
        if ($items.Count -eq 0) { $lines.Add($s[2]) }
        foreach ($x in $items) { $lines.Add((Format-TodoLine $x $cols)) }
    }
    return $lines.ToArray()
}

# -----------------------------------------------------------------------------
# Dialoge: Auswahl/Eingabe
# -----------------------------------------------------------------------------
function Show-SelectionDialog($Title, $Items, [int]$SelectedIndex = 0) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(480, 360)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.KeyPreview = $true
    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Dock = "Fill"
    foreach ($i in @($Items)) { if ($null -ne $i) { [void]$listBox.Items.Add($i) } }
    $form.Controls.Add($listBox)
    $form.Add_Shown({ $form.Activate(); $listBox.Focus(); if ($listBox.Items.Count -gt 0) { $listBox.SelectedIndex = [Math]::Max(0, [Math]::Min($SelectedIndex, $listBox.Items.Count - 1)) } })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter -or $_.KeyCode -eq [System.Windows.Forms.Keys]::Right) {
            if ($listBox.SelectedItem) { $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() }
            $_.Handled = $true
        }
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape -or $_.KeyCode -eq [System.Windows.Forms.Keys]::Left) { $form.Close() }
    })
    $listBox.Add_DoubleClick({ if ($listBox.SelectedItem) { $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() } })
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $listBox.SelectedItem }
    return $null
}
function Show-InputDialog($Title, $LabelText, [string]$Initial = "") {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(420, 160)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.KeyPreview = $true
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $LabelText
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.Size = New-Object System.Drawing.Size(360, 20)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(20, 50)
    $txt.Size = New-Object System.Drawing.Size(360, 24)
    $txt.Text = $Initial
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T "btn.ok"
    $ok.Location = New-Object System.Drawing.Point(20, 80)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = T "btn.cancel"
    $cancel.Location = New-Object System.Drawing.Point(100, 80)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.AddRange(@($lbl, $txt, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Add_Shown({ $form.Activate(); $txt.Focus(); $txt.SelectAll() })
    # Pfeil links = zurück nur, solange nichts eingegeben ist
    $form.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Left -and $txt.TextLength -eq 0) { $form.Close() } })
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $txt.Text }
    return $null
}
function Show-TextAreaDialog($Title, $LabelText) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(600, 460)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $LabelText
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Size = New-Object System.Drawing.Size(560, 20)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(12, 36)
    $txt.Size = New-Object System.Drawing.Size(560, 340)
    $txt.Multiline = $true
    $txt.AcceptsReturn = $true
    $txt.ScrollBars = "Both"
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T "btn.ok"
    $ok.Location = New-Object System.Drawing.Point(12, 386)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = T "btn.cancel"
    $cancel.Location = New-Object System.Drawing.Point(100, 386)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.AddRange(@($lbl, $txt, $ok, $cancel))
    $form.CancelButton = $cancel
    $form.Add_Shown({ $form.Activate(); $txt.Focus() })
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $txt.Text }
    return $null
}
function Show-TextWindow([scriptblock]$GetTitle, [scriptblock]$GetText) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Report"
    $form.Size = New-Object System.Drawing.Size(900, 520)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.KeyPreview = $true
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Dock = "Fill"
    $txt.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txt.Multiline = $true
    $txt.ScrollBars = "Both"
    $txt.WordWrap = $false
    $txt.ReadOnly = $true
    $form.Controls.Add($txt)
    $Refresh = { $txt.Text = (& $GetText); $form.Text = (& $GetTitle); $txt.SelectionStart = 0 }
    $form.Add_Shown({ & $Refresh })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::F5) { & $Refresh }
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape -or $_.KeyCode -eq [System.Windows.Forms.Keys]::Left) {
            $form.Hide()
            $form.BeginInvoke([Action]{ Show-TrayContextMenu; $form.Close() }) | Out-Null
        }
    })
    $form.ShowDialog() | Out-Null
}

# -----------------------------------------------------------------------------
# Kategorie/Unterkategorie/Task wählen (für Tasks und Todos)
# -----------------------------------------------------------------------------
function Show-SelectTaskTriple() {
    if (-not (Load-Categories))  { Show-LoadError $catsFile; return $null }
    if (-not (Load-TaskCatalog)) { Show-LoadError $taskCatalogFile; return $null }
    $cats = @($global:categories.Keys | Sort-Object)
    if ($cats.Count -eq 0) { Show-Info (T "msg.needCats") (T "msg.hint"); return $null }
    $cat = Show-SelectionDialog (T "sel.category") $cats
    if (-not $cat) { return $null }
    $subs = @()
    if ($global:categories.ContainsKey($cat)) { $subs = @($global:categories[$cat]) }
    if ($subs.Count -eq 0) { Show-Info (T "msg.noSubs") (T "msg.hint"); return $null }
    $sub = Show-SelectionDialog (T "sel.subcategory") ($subs | Sort-Object)
    if (-not $sub) { return $null }
    $key = "${cat}::${sub}"
    $taskList = @()
    if ($global:taskCatalog.ContainsKey($key)) { $taskList = @($global:taskCatalog[$key]) }
    $newTask = T "sel.newTask"
    $taskSel = Show-SelectionDialog (T "sel.task") (@($newTask) + @($taskList | Sort-Object -Unique))
    if (-not $taskSel) { return $null }
    if ($taskSel -eq $newTask) {
        $taskDesc = Show-InputDialog (T "dlg.newTask.title") (T "dlg.newTask.label")
        if ([string]::IsNullOrWhiteSpace($taskDesc)) { return $null }
        $taskDesc = $taskDesc.Trim()
        [void](Add-TaskToCatalog $key $taskDesc)
    } else { $taskDesc = $taskSel }
    return @{ "category" = $cat; "subcategory" = $sub; "desc" = $taskDesc }
}
# Rückgabe: Minuten (int), 0 = ungültig, $null = abgebrochen
function Read-Minutes {
    $minStr = Show-InputDialog (T "dlg.minutes.title") (T "dlg.minutes.label")
    if ($null -eq $minStr) { return $null }
    [int]$mins = 0
    if (-not [int]::TryParse($minStr.Trim(), [ref]$mins)) { $mins = 0 }
    return $mins
}
# Eigene Felder abfragen. Rückgabe: Hashtable (Field -> Wert) oder $null (abgebrochen)
function Read-CustomValues($fields) {
    $vals = @{}
    foreach ($f in $fields) {
        if (-not (Test-CustomField $f)) { continue }
        $n = Get-CustomName $f
        $v = Show-InputDialog $n ($n + ":")
        if ($null -eq $v) { return $null }
        $vals[$f] = $v.Trim()
    }
    return $vals
}
# Zusatzangaben für Worklog-Einträge je nach Spalten (Startzeit, eigene Felder). $null = abgebrochen
function Read-EntryExtras([int]$minutes) {
    $fields = @((Load-Columns).Worklog | ForEach-Object { $_.Field })
    $extras = @{}
    if ($fields -contains "StartTime" -or $fields -contains "EndTime") {
        $proposal = (Get-Date).AddMinutes(-$minutes).ToString("HH:mm")
        while ($true) {
            $s = Show-InputDialog (T "dlg.start.title") (T "dlg.start.label") $proposal
            if ($null -eq $s) { return $null }
            $clock = Parse-Clock $s
            if ($clock) { $extras["StartTime"] = $clock; break }
            Show-Info (T "msg.invalidTime") (T "msg.hint")
        }
    }
    $custom = Read-CustomValues $fields
    if ($null -eq $custom) { return $null }
    foreach ($k in $custom.Keys) { $extras[$k] = $custom[$k] }
    return $extras
}

function Add-Task() {
    $sel = Show-SelectTaskTriple
    if ($null -eq $sel) { Show-TrayContextMenu; return }
    $mins = Read-Minutes
    if ($null -eq $mins) { Show-TrayContextMenu; return }
    if ($mins -le 0) { Show-Info (T "msg.invalidEntry") (T "msg.hint"); Show-TrayContextMenu; return }
    $extras = Read-EntryExtras $mins
    if ($null -eq $extras) { Show-TrayContextMenu; return }
    [void](Write-TaskEntry -date (Get-Date) -project $sel.category -category $sel.subcategory -desc $sel.desc -minutes $mins -extras $extras)
    Update-TrayText
    Show-TrayContextMenu
}

# -----------------------------------------------------------------------------
# Kategorie/Unterkategorie verwalten
# -----------------------------------------------------------------------------
function Add-CategoryOrSubcategory() {
    [void](Load-Categories)
    $newCat = T "cat.new"
    $sel = Show-SelectionDialog (T "sel.category") (@($newCat) + @($global:categories.Keys | Sort-Object))
    if (-not $sel) { Show-TrayContextMenu; return }
    if ($sel -eq $newCat) {
        $cat = Show-InputDialog (T "cat.newTitle") (T "cat.newLabel")
        if ([string]::IsNullOrWhiteSpace($cat)) { Show-TrayContextMenu; return }
        $cat = $cat.Trim()
    } else { $cat = $sel }
    $sub = Show-InputDialog (T "cat.subTitle") (T "cat.subLabel" $cat)
    if ([string]::IsNullOrWhiteSpace($sub)) { Show-TrayContextMenu; return }
    $sub = $sub.Trim()
    if (-not (Load-Categories)) { Show-LoadError $catsFile; Show-TrayContextMenu; return }   # frisch laden
    $list = @()
    if ($global:categories.ContainsKey($cat)) { $list = @($global:categories[$cat]) }
    if (-not ($list -contains $sub)) { $global:categories[$cat] = $list + $sub; [void](Save-Categories) }
    Show-TrayContextMenu
}
function Remove-CategoryOrSubcategory() {
    [void](Load-Categories)
    if ($global:categories.Keys.Count -eq 0) { Show-TrayContextMenu; return }
    $cat = Show-SelectionDialog (T "cat.remSelect") ($global:categories.Keys | Sort-Object)
    if (-not $cat) { Show-TrayContextMenu; return }
    $subs = @()
    if ($global:categories.ContainsKey($cat)) { $subs = @($global:categories[$cat]) }
    $all = T "cat.remAll"
    $sel = Show-SelectionDialog (T "cat.remSub") (@($all) + @($subs | Sort-Object))
    if (-not $sel) { Show-TrayContextMenu; return }
    if (-not (Load-Categories))  { Show-LoadError $catsFile; Show-TrayContextMenu; return }
    if (-not (Load-TaskCatalog)) { Show-LoadError $taskCatalogFile; Show-TrayContextMenu; return }
    if ($sel -eq $all) {
        $global:categories.Remove($cat) | Out-Null
        foreach ($rk in @($global:taskCatalog.Keys | Where-Object { $_.StartsWith("${cat}::") })) { $global:taskCatalog.Remove($rk) | Out-Null }
    } else {
        if ($global:categories.ContainsKey($cat)) { $global:categories[$cat] = @($global:categories[$cat] | Where-Object { $_ -ne $sel }) }
        $key = "${cat}::${sel}"
        if ($global:taskCatalog.ContainsKey($key)) { $global:taskCatalog.Remove($key) | Out-Null }
    }
    [void](Save-Categories)
    [void](Save-TaskCatalog)
    Show-TrayContextMenu
}

# -----------------------------------------------------------------------------
# Reports
# -----------------------------------------------------------------------------
function Show-WeekSelectionDialog([string]$Title) {
    if (-not $Title) { $Title = T "week.select" }
    $files = @()
    if (Test-Path $tasksDir) { $files = @(Get-ChildItem -Path $tasksDir -Filter "*_worklog.csv" -File | Sort-Object Name) }
    $currentMonday = Get-WeekMonday (Get-Date)
    $items = @(); $map = @{}; $preselect = -1
    foreach ($f in $files) {
        $monday = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($f.Name.Split("_")[0], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$monday)) { continue }
        $label = Format-WeekLabel $monday
        if ($monday -eq $currentMonday) { $preselect = $items.Count }
        $items += $label
        $map[$label] = $monday
    }
    if ($items.Count -eq 0) { return $null }
    if ($preselect -lt 0) { $preselect = $items.Count - 1 }
    $sel = Show-SelectionDialog $Title $items $preselect
    if ($sel -and $map.ContainsKey($sel)) { return $map[$sel] }
    return $null
}
function Start-Report() {
    $mon = Show-WeekSelectionDialog
    if ($null -eq $mon) { Show-TrayContextMenu; return }
    $state = @{ Rep = $null }
    Show-TextWindow -GetTitle {
        T "report.title" (Get-IsoWeekNumber $mon) (To-HhMm $state.Rep.Minutes) $mon.ToString("yyyy-MM-dd") $mon.AddDays(6).ToString("yyyy-MM-dd")
    } -GetText {
        $state.Rep = Get-WeekReport $mon
        $lines = @($state.Rep.Lines)
        if (-not $state.Rep.HasEntries) { if ($state.Rep.FileExists) { $lines += (T "report.noEntries") } else { $lines += (T "report.noData") } }
        Update-TrayText
        [string]::Join([Environment]::NewLine, $lines)
    }
}
function Start-TodoReport() {
    Show-TextWindow -GetTitle { T "todoReport.title" } -GetText {
        if (-not (Load-Todos)) { T "todoReport.loadError" }
        else { [string]::Join([Environment]::NewLine, (Get-TodoReportLines (Get-Date))) }
    }
}

# -----------------------------------------------------------------------------
# Kontextmenü erneut anzeigen (Rücksprung) + Fokus
# -----------------------------------------------------------------------------
function Show-TrayContextMenu {
    if ($global:trayIcon -and $global:trayIcon.ContextMenuStrip) {
        $cm = $global:trayIcon.ContextMenuStrip
        $cm.Show([System.Windows.Forms.Cursor]::Position)
        try {
            if ($global:lastTrayMenuIndex -ge 0 -and $global:lastTrayMenuIndex -lt $cm.Items.Count) { $cm.Items[$global:lastTrayMenuIndex].Select() }
            else { $cm.Items[1].Select() }
        } catch {}
        $cm.Focus()
    }
}

# -----------------------------------------------------------------------------
# Todos
# -----------------------------------------------------------------------------
function Select-TodoScope([string]$title) {
    $labels = @($global:Scopes | ForEach-Object { T ("scope." + $_) })
    $sel = Show-SelectionDialog $title $labels
    if (-not $sel) { return $null }
    return $global:Scopes[[array]::IndexOf($labels, [string]$sel)]
}
function Add-Todo() {
    $scope = Select-TodoScope (T "todo.scopeTitle")
    if (-not $scope) { Show-TrayContextMenu; return }
    $sel = Show-SelectTaskTriple
    if ($null -eq $sel) { Show-TrayContextMenu; return }
    $desc = Show-TextAreaDialog (T "todo.descTitle") (T "todo.descLabel")
    if ($null -eq $desc) { Show-TrayContextMenu; return }
    $custom = Read-CustomValues @((Load-Columns).Todo | ForEach-Object { $_.Field })
    if ($null -eq $custom) { Show-TrayContextMenu; return }
    $extra = @{}
    foreach ($k in $custom.Keys) { $extra[(Get-CustomName $k)] = $custom[$k] }
    $todo = @{ Id = [guid]::NewGuid().ToString(); Scope = $scope; Category = $sel.category; Subcategory = $sel.subcategory
               Task = $sel.desc; Description = $desc; Created = Get-Date; Done = $false; DoneMinutes = $null; DoneDate = $null; Extra = $extra }
    if (-not (Load-Todos)) { Show-LoadError $todosFile; Show-TrayContextMenu; return }   # frisch laden -> anhängen -> speichern
    $global:todos += $todo
    if (Save-Todos) { Show-Info (T "todo.saved") }
    Show-TrayContextMenu
}
function Show-Todos() {
    $scope = Select-TodoScope (T "todo.showScope")
    if (-not $scope) { Show-TrayContextMenu; return }
    $form = New-Object System.Windows.Forms.Form
    $form.Text = T "todos.title" (Get-ScopeLabel $scope)
    $form.Size = New-Object System.Drawing.Size(900, 520)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.KeyPreview = $true
    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Dock = "Fill"
    $listBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($listBox)
    $ids = New-Object System.Collections.Generic.List[string]   # Index-basiert (gleiche Texte bleiben eindeutig)
    $Refresh = {
        $listBox.Items.Clear(); $ids.Clear()
        if (-not (Load-Todos)) { [void]$listBox.Items.Add((T "todos.loadError")); return }
        $items = Get-OpenTodos $scope
        if ($items.Count -eq 0) { [void]$listBox.Items.Add((T "todos.none" (Get-ScopeLabel $scope))) }
        foreach ($x in $items) {
            $firstLine = ([string]$x.Description -split "\r?\n")[0]
            $created = if ($x.Created) { $x.Created.ToString("yyyy-MM-dd") } else { "" }
            [void]$listBox.Items.Add(("{0} -> {1} | {2} | {3} ({4})" -f $x.Category, $x.Subcategory, $x.Task, $firstLine, $created))
            $ids.Add([string]$x.Id)
        }
        if ($listBox.Items.Count -gt 0) { $listBox.SelectedIndex = 0 }
    }
    $OpenSelected = {
        $idx = $listBox.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $ids.Count) { Open-TodoDetailWindow $ids[$idx]; & $Refresh }
    }
    $form.Add_Shown({ & $Refresh })
    $listBox.Add_DoubleClick({ & $OpenSelected })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::F5) { & $Refresh }
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape -or $_.KeyCode -eq [System.Windows.Forms.Keys]::Left) {
            $form.Hide()
            $form.BeginInvoke([Action]{ Show-TrayContextMenu; $form.Close() }) | Out-Null
        }
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter -or $_.KeyCode -eq [System.Windows.Forms.Keys]::Right) { & $OpenSelected }
    })
    $form.ShowDialog() | Out-Null
}
function Open-TodoDetailWindow([string]$todoId) {
    if (-not (Load-Todos)) { Show-LoadError $todosFile; return }
    $todo = $global:todos | Where-Object { $_.Id -eq $todoId } | Select-Object -First 1
    if (-not $todo) { return }
    $state = @{ OrigDescription = [string]$todo.Description }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T "detail.title" ([string]$todo.Task)
    $form.Size = New-Object System.Drawing.Size(700, 560)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.KeyPreview = $true
    $lblTop = New-Object System.Windows.Forms.Label
    $lblTop.Location = New-Object System.Drawing.Point(12, 12)
    $lblTop.Size = New-Object System.Drawing.Size(660, 80)
    $SetInfo = {
        $created = if ($todo.Created) { $todo.Created.ToString("yyyy-MM-dd HH:mm") } else { "" }
        $lblTop.Text = T "detail.info" (Get-ScopeLabel $todo.Scope) $todo.Category $todo.Subcategory $todo.Task $created
    }
    & $SetInfo
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(12, 100)
    $txt.Size = New-Object System.Drawing.Size(660, 320)
    $txt.Multiline = $true
    $txt.AcceptsReturn = $true
    $txt.ScrollBars = "Both"
    $txt.Text = $state.OrigDescription
    $cmbMove = New-Object System.Windows.Forms.ComboBox
    $cmbMove.Location = New-Object System.Drawing.Point(12, 430)
    $cmbMove.Size = New-Object System.Drawing.Size(160, 24)
    $cmbMove.DropDownStyle = "DropDownList"
    foreach ($s in $global:Scopes) { [void]$cmbMove.Items.Add((T ("scope." + $s))) }
    $cmbMove.SelectedIndex = [Math]::Max(0, [array]::IndexOf($global:Scopes, [string]$todo.Scope))
    $btnMove = New-Object System.Windows.Forms.Button
    $btnMove.Text = T "detail.move"
    $btnMove.Location = New-Object System.Drawing.Point(180, 428)
    $btnMove.AutoSize = $true
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = T "detail.close"
    $btnClose.Location = New-Object System.Drawing.Point(468, 428)
    $btnDone = New-Object System.Windows.Forms.Button
    $btnDone.Text = T "detail.done"
    $btnDone.Location = New-Object System.Drawing.Point(560, 428)

    $SaveDescriptionIfChanged = {
        $newText = $txt.Text
        if ($newText -ne $state.OrigDescription) {
            $res = Update-TodoById $todoId { param($x) $x.Description = $newText }
            if ($res -eq $true) { $state.OrigDescription = $newText }
        }
    }
    $btnMove.Add_Click({
        $newScope = $global:Scopes[$cmbMove.SelectedIndex]
        if ($newScope -and $newScope -ne $todo.Scope) {
            $newText = $txt.Text
            $res = Update-TodoById $todoId { param($x) $x.Scope = $newScope; $x.Description = $newText }
            if ($res -eq $true) {
                $todo.Scope = $newScope; $state.OrigDescription = $newText; & $SetInfo
                Show-Info (T "detail.moved" (Get-ScopeLabel $newScope))
            } elseif ($res -eq "notfound") { Show-Info (T "detail.gone") (T "msg.hint") }
        }
    })
    $btnDone.Add_Click({
        [void](Load-Todos)   # evtl. schon auf einem anderen Rechner erledigt
        $cur = $global:todos | Where-Object { $_.Id -eq $todoId } | Select-Object -First 1
        if (-not $cur) { Show-Info (T "detail.gone") (T "msg.hint"); return }
        if ($cur.Done) { Show-Info (T "detail.alreadyDone"); return }
        $mins = Read-Minutes
        if ($null -eq $mins) { return }
        if ($mins -le 0) { Show-Info (T "msg.invalidMinutes") (T "msg.hint"); return }
        $extras = Read-EntryExtras $mins
        if ($null -eq $extras) { return }
        if (-not (Write-TaskEntry -date (Get-Date) -project $todo.Category -category $todo.Subcategory -desc $todo.Task -minutes $mins -extras $extras)) { return }
        $newText = $txt.Text
        $res = Update-TodoById $todoId { param($x) $x.Description = $newText; $x.Done = $true; $x.DoneMinutes = $mins; $x.DoneDate = Get-Date }
        Update-TrayText
        if ($res -eq $true) { Show-Info (T "detail.booked"); $form.Close() }
    })
    $btnClose.Add_Click({ & $SaveDescriptionIfChanged; $form.Close() })
    $form.Controls.AddRange(@($lblTop, $txt, $cmbMove, $btnMove, $btnClose, $btnDone))
    $form.Add_KeyDown({
        $isEsc  = $_.KeyCode -eq [System.Windows.Forms.Keys]::Escape
        $isLeft = ($_.KeyCode -eq [System.Windows.Forms.Keys]::Left) -and -not $txt.Focused -and -not $cmbMove.Focused
        if ($isEsc -or $isLeft) { & $SaveDescriptionIfChanged; $form.Close() }
    })
    $form.ShowDialog() | Out-Null
}

# -----------------------------------------------------------------------------
# Spalten-Dialog ($kind = "Worklog": Überschrift bearbeitbar; "Todo": Format bearbeitbar)
# -----------------------------------------------------------------------------
function Show-ColumnsDialog([string]$kind) {
    $cols = New-Object System.Collections.ArrayList
    foreach ($c in @((Load-Columns)[$kind])) { $h = [ordered]@{}; foreach ($k in $c.Keys) { $h[$k] = $c[$k] }; [void]$cols.Add($h) }
    $prop = if ($kind -eq "Worklog") { "Header" } else { "Format" }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = if ($kind -eq "Worklog") { T "columns.titleWorklog" } else { T "columns.titleTodo" }
    $form.Size = New-Object System.Drawing.Size(760, 440)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(12, 12)
    $list.Size = New-Object System.Drawing.Size(560, 280)
    $list.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $note = New-Object System.Windows.Forms.Label
    $note.Location = New-Object System.Drawing.Point(12, 300)
    $note.Size = New-Object System.Drawing.Size(720, 50)
    $note.ForeColor = [System.Drawing.Color]::Gray
    $note.Text = if ($kind -eq "Worklog") { T "columns.noteWorklog" } else { T "columns.noteTodo" }
    $form.Controls.AddRange(@($list, $note))

    $Refresh = {
        param([int]$sel = 0)
        $list.Items.Clear()
        foreach ($c in $cols) { [void]$list.Items.Add(("{0}   ->   {1}" -f (Get-FieldDisplay $c.Field), $c[$prop])) }
        if ($cols.Count -gt 0) { $list.SelectedIndex = [Math]::Max(0, [Math]::Min($sel, $cols.Count - 1)) }
    }
    $DefaultProp = {
        param([string]$field)
        if ($kind -eq "Todo") { return "{value}" }
        if (Test-CustomField $field) { return (Get-CustomName $field) }
        return (Get-WlHeaderTable)[$field]
    }
    $buttons = @(
        @((T "columns.add"), {
            $present = @($cols | ForEach-Object { $_.Field })
            $all = if ($kind -eq "Worklog") { $global:WlFields } else { $global:TodoFields }
            $avail = @($all | Where-Object { $present -cnotcontains $_ })
            $labels = @($avail | ForEach-Object { Get-FieldDisplay $_ }) + @(T "columns.custom")
            $sel = Show-SelectionDialog (T "columns.selectField") $labels
            if (-not $sel) { return }
            if ($sel -eq (T "columns.custom")) {
                $name = (Clean-CsvField (Show-InputDialog (T "columns.selectField") (T "columns.customName"))).Replace(":", "")
                if (-not $name -or $present -ccontains ("Custom:" + $name)) { return }
                $field = "Custom:" + $name
            } else { $field = $avail[[array]::IndexOf($labels, [string]$sel)] }
            $pos = if ($list.SelectedIndex -ge 0) { $list.SelectedIndex + 1 } else { $cols.Count }
            $cols.Insert($pos, [ordered]@{ Field = $field; $prop = (& $DefaultProp $field) })
            & $Refresh $pos
        }),
        @((T "columns.remove"), { $i = $list.SelectedIndex; if ($i -ge 0) { $cols.RemoveAt($i); & $Refresh $i } }),
        @((T "columns.up"),   { $i = $list.SelectedIndex; if ($i -gt 0) { $c = $cols[$i]; $cols.RemoveAt($i); $cols.Insert($i - 1, $c); & $Refresh ($i - 1) } }),
        @((T "columns.down"), { $i = $list.SelectedIndex; if ($i -ge 0 -and $i -lt $cols.Count - 1) { $c = $cols[$i]; $cols.RemoveAt($i); $cols.Insert($i + 1, $c); & $Refresh ($i + 1) } }),
        @($(if ($kind -eq "Worklog") { T "columns.header" } else { T "columns.format" }), {
            $i = $list.SelectedIndex
            if ($i -lt 0) { return }
            $lbl = if ($kind -eq "Worklog") { T "columns.headerLabel" } else { T "columns.formatLabel" }
            $v = Show-InputDialog (Get-FieldDisplay $cols[$i].Field) $lbl ([string]$cols[$i][$prop])
            if ($null -ne $v -and $v.Trim()) {
                if ($kind -eq "Worklog") { $cols[$i][$prop] = Clean-CsvField $v } else { $cols[$i][$prop] = $v.Trim() }
                & $Refresh $i
            }
        }),
        @((T "columns.reset"), { $cols.Clear(); foreach ($c in @((Get-DefaultColumns)[$kind])) { [void]$cols.Add($c) }; & $Refresh 0 })
    )
    $y = 12
    foreach ($b in $buttons) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $b[0]
        $btn.Location = New-Object System.Drawing.Point(584, $y)
        $btn.Size = New-Object System.Drawing.Size(150, 28)
        $btn.Add_Click($b[1])
        $form.Controls.Add($btn)
        $y += 36
    }
    $list.Add_DoubleClick($buttons[4][1])
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T "btn.save"
    $ok.Location = New-Object System.Drawing.Point(12, 356)
    $ok.Size = New-Object System.Drawing.Size(100, 28)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = T "btn.cancel"
    $cancel.Location = New-Object System.Drawing.Point(120, 356)
    $cancel.Size = New-Object System.Drawing.Size(100, 28)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $ok.Add_Click({
        $fields = @($cols | ForEach-Object { $_.Field })
        if ($kind -eq "Worklog" -and (($fields -cnotcontains "Date") -or (($fields -cnotcontains "Minutes") -and ($fields -cnotcontains "Hours")))) {
            Show-Info (T "columns.needWorklog") (T "msg.hint"); return
        }
        if ($cols.Count -eq 0) { Show-Info (T "columns.needOne") (T "msg.hint"); return }
        if (Save-ColumnsPart $kind @($cols.ToArray())) { $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() }
    })
    $form.Controls.AddRange(@($ok, $cancel))
    $form.CancelButton = $cancel
    $form.Add_Shown({ & $Refresh 0; $form.Activate(); $list.Focus() })
    $form.ShowDialog() | Out-Null
}

# -----------------------------------------------------------------------------
# Einstellungen-Dialog
# -----------------------------------------------------------------------------
function Show-SettingsDialog() {
    $s = Load-Settings
    $form = New-Object System.Windows.Forms.Form
    $form.Text = T "settings.title"
    $form.Size = New-Object System.Drawing.Size(600, 290)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $mk = { param($text, $x, $y, $w) $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, 20); $l }
    $lblName = & $mk (T "settings.user") 12 18 170
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(190, 15)
    $txtName.Size = New-Object System.Drawing.Size(380, 24)
    $txtName.Text = $s.UserName
    $lblPath = & $mk (T "settings.export") 12 58 170
    $txtPath = New-Object System.Windows.Forms.TextBox
    $txtPath.Location = New-Object System.Drawing.Point(190, 55)
    $txtPath.Size = New-Object System.Drawing.Size(280, 24)
    $txtPath.Text = $s.ExportPath
    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = T "settings.browse"
    $btnBrowse.Location = New-Object System.Drawing.Point(476, 53)
    $btnBrowse.Size = New-Object System.Drawing.Size(94, 26)
    $btnBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = T "settings.browseTitle"
        if ($txtPath.Text -and (Test-Path -LiteralPath $txtPath.Text)) { $dlg.SelectedPath = $txtPath.Text }
        if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $txtPath.Text = $dlg.SelectedPath }
    })
    $lblLang = & $mk (T "settings.language") 12 98 170
    $cmbLang = New-Object System.Windows.Forms.ComboBox
    $cmbLang.Location = New-Object System.Drawing.Point(190, 95)
    $cmbLang.Size = New-Object System.Drawing.Size(160, 24)
    $cmbLang.DropDownStyle = "DropDownList"
    foreach ($l in $global:Languages) { [void]$cmbLang.Items.Add($l[1]) }
    $cmbLang.SelectedIndex = 0
    for ($i = 0; $i -lt $global:Languages.Count; $i++) { if ($global:Languages[$i][0] -eq $s.Language) { $cmbLang.SelectedIndex = $i } }
    $btnColWl = New-Object System.Windows.Forms.Button
    $btnColWl.Text = T "settings.columnsWorklog"
    $btnColWl.Location = New-Object System.Drawing.Point(190, 135)
    $btnColWl.Size = New-Object System.Drawing.Size(185, 28)
    $btnColWl.Add_Click({ Show-ColumnsDialog "Worklog" })
    $btnColTd = New-Object System.Windows.Forms.Button
    $btnColTd.Text = T "settings.columnsTodo"
    $btnColTd.Location = New-Object System.Drawing.Point(385, 135)
    $btnColTd.Size = New-Object System.Drawing.Size(185, 28)
    $btnColTd.Add_Click({ Show-ColumnsDialog "Todo" })
    $lblInfo = & $mk (T "settings.storedAt" $settingsFile) 12 175 560
    $lblInfo.ForeColor = [System.Drawing.Color]::Gray
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T "btn.save"
    $ok.Location = New-Object System.Drawing.Point(12, 210)
    $ok.Size = New-Object System.Drawing.Size(100, 28)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = T "btn.cancel"
    $cancel.Location = New-Object System.Drawing.Point(120, 210)
    $cancel.Size = New-Object System.Drawing.Size(100, 28)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.AddRange(@($lblName, $txtName, $lblPath, $txtPath, $btnBrowse, $lblLang, $cmbLang, $btnColWl, $btnColTd, $lblInfo, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Add_Shown({ $form.Activate(); $txtName.Focus() })
    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

    $path = $txtPath.Text.Trim()
    if ($path -and -not (Test-Path -LiteralPath $path)) {
        $ans = [System.Windows.Forms.MessageBox]::Show((T "settings.createDir" $path), (T "settings.title"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
            try { New-Item -ItemType Directory -Path $path -Force | Out-Null } catch { Show-Error (T "settings.createDirFailed" $_.Exception.Message); return $false }
        }
    }
    $ok = Save-Settings @{ UserName = $txtName.Text.Trim(); ExportPath = $path; Language = $global:Languages[$cmbLang.SelectedIndex][0] }
    Update-MenuTexts
    return $ok
}
function Start-Settings() { [void](Show-SettingsDialog); Show-TrayContextMenu }

# -----------------------------------------------------------------------------
# Reports exportieren: <Name>_KW<nn>_<Jahr>_Arbeitszeit.csv und ..._Todos.md
# -----------------------------------------------------------------------------
function ConvertTo-SafeFileName([string]$s) {
    if ($null -eq $s) { return "" }
    $invalid = [regex]::Escape((-join [System.IO.Path]::GetInvalidFileNameChars()) + '<>:"/\|?*')
    return (($s -replace "[$invalid]", "_").Trim())
}
function Test-SettingsComplete($s) {
    return -not ([string]::IsNullOrWhiteSpace($s.UserName) -or [string]::IsNullOrWhiteSpace($s.ExportPath) -or -not (Test-Path -LiteralPath $s.ExportPath))
}
function Export-Reports() {
    $s = Load-Settings
    if (-not (Test-SettingsComplete $s)) {
        Show-Info (T "export.needSettings") (T "export.title")
        if (-not (Show-SettingsDialog)) { Show-TrayContextMenu; return }
        $s = Load-Settings
        if (-not (Test-SettingsComplete $s)) { Show-TrayContextMenu; return }
    }
    $mon = Show-WeekSelectionDialog (T "export.selectWeek")
    if ($null -eq $mon) {
        if (@(Get-ChildItem -Path $tasksDir -Filter "*_worklog.csv" -File).Count -eq 0) { $mon = Get-WeekMonday (Get-Date) }
        else { Show-TrayContextMenu; return }
    }
    $res = Export-ReportsToFolder -WeekMonday $mon -UserName $s.UserName -ExportPath $s.ExportPath
    if ($res.Ok) { Show-Info (T "export.done" $s.ExportPath ($res.Files -join "`r`n")) (T "export.title") }
    Show-TrayContextMenu
}
# Ohne Dialoge (testbar). Rückgabe: @{ Ok; Files }
function Export-ReportsToFolder([datetime]$WeekMonday, [string]$UserName, [string]$ExportPath) {
    $prefix = ("{0}_{1}{2:00}_{3}" -f (ConvertTo-SafeFileName $UserName), (T "export.kw"), (Get-IsoWeekNumber $WeekMonday), (Get-IsoWeekYear $WeekMonday))
    $files = @()
    $rep = Get-WeekReport $WeekMonday
    $csvPath = Join-Path $ExportPath ("{0}_{1}.csv" -f $prefix, (T "export.fileWork"))
    try {
        [System.IO.File]::WriteAllText($csvPath, ([string]::Join("`r`n", $rep.Lines) + "`r`n"), $global:Utf8Bom)
        $files += [System.IO.Path]::GetFileName($csvPath)
    } catch { Show-Error (T "export.failed" ($csvPath + "`r`n" + $_.Exception.Message)); return @{ Ok = $false; Files = $files } }
    if (-not (Load-Todos)) { Show-LoadError $todosFile; return @{ Ok = $false; Files = $files } }
    $refDate = if ((Get-WeekMonday (Get-Date)) -eq $WeekMonday) { Get-Date } else { $WeekMonday.AddDays(3) }
    $mdPath = Join-Path $ExportPath ("{0}_{1}.md" -f $prefix, (T "export.fileTodos"))
    try {
        [System.IO.File]::WriteAllText($mdPath, ([string]::Join("`r`n", (Get-TodoReportLines $refDate)) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        $files += [System.IO.Path]::GetFileName($mdPath)
    } catch { Show-Error (T "export.failed" ($mdPath + "`r`n" + $_.Exception.Message)); return @{ Ok = $false; Files = $files } }
    return @{ Ok = $true; Files = $files }
}

# -----------------------------------------------------------------------------
# Tray-App starten (NotifyIcon, ContextMenuStrip, Timer, Hotkeys)
# -----------------------------------------------------------------------------
function Update-MenuTexts {
    foreach ($m in $global:menuItems) { $m[0].Text = T $m[1] }
    Update-TrayText
}
function Start-TrayApp {
    [void](Load-Settings)
    try {
        $n = Repair-AllWorklogs
        if ($n -gt 0) { Log ("{0} Worklog-Datei(en) repariert." -f $n) }
    } catch { Log ("Repair-AllWorklogs FEHLER: {0}" -f $_.Exception.Message) }

    $appContext = New-Object System.Windows.Forms.ApplicationContext
    $global:trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $global:trayIcon.Icon = [System.Drawing.SystemIcons]::Application
    $global:trayIcon.Text = T "app.title"
    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

    $def = @(
        @("menu.report", { Start-Report }), @("menu.addTask", { Add-Task }),
        @("menu.addCat", { Add-CategoryOrSubcategory }), @("menu.remCat", { Remove-CategoryOrSubcategory }), $null,
        @("menu.addTodo", { Add-Todo }), @("menu.todos", { Show-Todos }), @("menu.todoReport", { Start-TodoReport }), $null,
        @("menu.export", { Export-Reports }), @("menu.settings", { Start-Settings }), $null,
        @("menu.recalc", { Update-TrayText }), $null, @("menu.exit", $null)
    )
    $global:menuItems = @()
    $miExit = $null
    foreach ($d in $def) {
        if ($null -eq $d) { [void]$contextMenu.Items.Add("-"); continue }
        $mi = $contextMenu.Items.Add((T $d[0]))
        $global:menuItems += ,@($mi, $d[0])
        if ($d[1]) { $mi.Add_Click($d[1]) | Out-Null } else { $miExit = $mi }
    }
    $miExit.Add_Click({
        # beim Beenden NICHTS speichern: alle Änderungen wurden bereits sofort geschrieben
        if ($hotkeyWnd) {
            [HotkeyWindow]::UnregisterHotKey($hotkeyWnd.Handle, 1) | Out-Null
            [HotkeyWindow]::UnregisterHotKey($hotkeyWnd.Handle, 2) | Out-Null
            $hotkeyWnd.Close()
        }
        if ($global:refreshTimer) { $global:refreshTimer.Stop(); $global:refreshTimer.Dispose() }
        if ($global:trayIcon) { $global:trayIcon.Visible = $false; $global:trayIcon.Dispose() }
        $appContext.ExitThread()
    }) | Out-Null

    $contextMenu.add_Opened({
        try { if ($global:lastTrayMenuIndex -ge 0 -and $global:lastTrayMenuIndex -lt $contextMenu.Items.Count) { $contextMenu.Items[$global:lastTrayMenuIndex].Select() } } catch {}
        $contextMenu.Focus()
    })
    $contextMenu.add_ItemClicked({ param($sender, $e); try { $global:lastTrayMenuIndex = $contextMenu.Items.IndexOf($e.ClickedItem) } catch {} })
    # KeyMap: Links = ESC, Rechts = ENTER
    $contextMenu.add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Left) { [System.Windows.Forms.SendKeys]::Send("{ESC}") }
        elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Right) { [System.Windows.Forms.SendKeys]::Send("{ENTER}") }
    })
    $global:trayIcon.ContextMenuStrip = $contextMenu
    $global:trayIcon.Visible = $true

    # Periodische Aktualisierung (auch Buchungen anderer Rechner)
    $global:refreshTimer = New-Object System.Windows.Forms.Timer
    $global:refreshTimer.Interval = 60000
    $global:refreshTimer.add_Tick({ Update-TrayText })
    $global:refreshTimer.Start()

    # Hotkeys: Strg+Alt+Z = Menü, Strg+Alt+A = Task
    $hotkeyWnd = New-Object HotkeyWindow
    if (-not [HotkeyWindow]::RegisterHotKey($hotkeyWnd.Handle, 1, 3, 0x5A)) { Log "Hotkey Strg+Alt+Z bereits belegt?" }
    if (-not [HotkeyWindow]::RegisterHotKey($hotkeyWnd.Handle, 2, 3, 0x41)) { Log "Hotkey Strg+Alt+A bereits belegt?" }
    $hotkeyWnd.add_HotkeyPressed({ param($id); if ($id -eq 1) { Show-TrayContextMenu } elseif ($id -eq 2) { Add-Task } })
    $appContext.MainForm = $hotkeyWnd

    # Linksklick auf das Tray-Icon -> Kontextmenü
    $global:trayIcon.add_Click({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            try {
                if ($hotkeyWnd -and $hotkeyWnd.IsHandleCreated) { $null = $hotkeyWnd.BeginInvoke([Action]{ Show-TrayContextMenu }) }
                else { Show-TrayContextMenu }
            } catch { Show-TrayContextMenu }
        }
    })
    Update-TrayText
    [System.Windows.Forms.Application]::Run($appContext)
}

# -----------------------------------------------------------------------------
# Einstieg
# -----------------------------------------------------------------------------
if ($env:ZEITERFASSUNG_NO_START -ne "1") { Start-TrayApp }
