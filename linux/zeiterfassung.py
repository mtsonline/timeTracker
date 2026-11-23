#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
timeTracker - zeiterfassung.py (Linux, Python 3 + GTK 3)            Version 2.5.1

Arbeitszeit- und Todo-Verwaltung als Tray-Anwendung. Gleiche Datendateien und Formate
wie windows/zeiterfassung.ps1, damit beide Varianten parallel auf demselben
(Nextcloud-)Ordner arbeiten können:

  <Datenordner>/categories.json, tasks.json, todo.json, columns.json
  <Datenordner>/worklogs/<Montag yyyy-MM-dd>_worklog.csv   (UTF-8 mit BOM, CRLF, ';')
  <Datenordner>/backups, <Datenordner>/worklogs/backups     (rotierende Backups .0 .. .9)

Datenordner = Ordner dieses Scripts (änderbar: --data-dir oder ZEITERFASSUNG_DIR).
Einstellungen (lokal pro Rechner): ~/.config/zeiterfassung/settings.json

Abhängigkeiten (Debian/Ubuntu):
  sudo apt install python3 python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1

Lizenz: MIT (siehe LICENSE)
"""

import argparse
import datetime as dt
import json
import os
import random
import re
import shutil
import string
import sys
import time
import uuid

VERSION = "2.5.1"

# -----------------------------------------------------------------------------
# Pfade
# -----------------------------------------------------------------------------
DATA_DIR = os.path.dirname(os.path.abspath(__file__))
TASKS_DIR = CATS_FILE = TASK_CATALOG_FILE = TODOS_FILE = COLUMNS_FILE = ""
CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
SETTINGS_DIR = os.path.join(CONFIG_HOME, "zeiterfassung")
SETTINGS_FILE = os.path.join(SETTINGS_DIR, "settings.json")

BACKUP_KEEP = 10
DEBUG = bool(os.environ.get("ZEITERFASSUNG_DEBUG"))
SCOPES = ["Woche", "Monat", "Jahr", "Sonstiges"]   # gespeicherte Werte (unabhängig von der Sprache)
LANGUAGES = [("de", "Deutsch"), ("en", "English")]


def set_data_dir(path):
    global DATA_DIR, TASKS_DIR, CATS_FILE, TASK_CATALOG_FILE, TODOS_FILE, COLUMNS_FILE
    DATA_DIR = os.path.abspath(path)
    TASKS_DIR = os.path.join(DATA_DIR, "worklogs")
    CATS_FILE = os.path.join(DATA_DIR, "categories.json")
    TASK_CATALOG_FILE = os.path.join(DATA_DIR, "tasks.json")
    TODOS_FILE = os.path.join(DATA_DIR, "todo.json")
    COLUMNS_FILE = os.path.join(DATA_DIR, "columns.json")
    os.makedirs(TASKS_DIR, exist_ok=True)


def log(msg):
    if DEBUG:
        sys.stderr.write("[%s] %s\n" % (dt.datetime.now().strftime("%H:%M:%S.%f")[:-3], msg))


# -----------------------------------------------------------------------------
# Übersetzungen ({0}, {1} = Platzhalter; identische Schlüssel wie in der Windows-Variante)
# -----------------------------------------------------------------------------
STRINGS = {
    "de": {
        "app.title": "Arbeitszeit",
        "menu.report": "Report", "menu.addTask": "Task hinzufügen",
        "menu.addCat": "Kategorie/Unterkategorie hinzufügen", "menu.remCat": "Kategorie/Unterkategorie entfernen",
        "menu.addTodo": "Todo hinzufügen", "menu.todos": "Todos anzeigen", "menu.todoReport": "Todo-Report",
        "menu.export": "Reports exportieren", "menu.settings": "Einstellungen",
        "menu.recalc": "Heute neu berechnen", "menu.exit": "Beenden",
        "tray.today": "Heute {0} min ({1})",
        "sel.category": "Kategorie wählen", "sel.subcategory": "Unterkategorie wählen", "sel.task": "Task wählen",
        "sel.newTask": "[Neuen Task eingeben]",
        "dlg.newTask.title": "Neuer Task", "dlg.newTask.label": "Kurzbeschreibung:",
        "dlg.minutes.title": "Dauer", "dlg.minutes.label": "Aufwand/Dauer in Minuten:",
        "dlg.start.title": "Startzeit", "dlg.start.label": "Startzeit (HH:MM):",
        "btn.ok": "OK", "btn.cancel": "Abbrechen", "btn.save": "Speichern", "btn.select": "Auswählen",
        "msg.info": "Info", "msg.hint": "Hinweis", "msg.error": "Fehler", "msg.question": "Frage",
        "msg.needCats": "Bitte zuerst Kategorien/Unterkategorien anlegen.",
        "msg.noSubs": "Diese Kategorie hat noch keine Unterkategorie.",
        "msg.invalidEntry": "Bitte Kategorie, Unterkategorie und Minuten korrekt angeben.",
        "msg.invalidMinutes": "Bitte eine gültige Minutenanzahl eingeben.",
        "msg.invalidTime": "Bitte eine gültige Uhrzeit im Format HH:MM eingeben.",
        "msg.loadError": "Die Datei konnte nicht gelesen werden:\n{0}\n\nMöglicherweise wird sie gerade synchronisiert oder ist beschädigt.\nDie Änderung wurde NICHT gespeichert, damit keine Daten überschrieben werden.\nBitte später erneut versuchen (Backups liegen im Unterordner 'backups').",
        "msg.saveError": "Die Datei konnte nicht gespeichert werden:\n{0}\n\nBitte später erneut versuchen.",
        "cat.new": "[Neue Kategorie anlegen]", "cat.newTitle": "Neue Kategorie", "cat.newLabel": "Name der neuen Kategorie:",
        "cat.subTitle": "Unterkategorie hinzufügen", "cat.subLabel": "Name der Unterkategorie für '{0}':",
        "cat.remSelect": "Kategorie zum Entfernen wählen", "cat.remSub": "Unterkategorie entfernen",
        "cat.remAll": "[Kategorie vollständig entfernen]",
        "week.select": "Woche wählen", "week.label": "KW {0} / {1}   ({2} .. {3})",
        "report.title": "Report - KW {0}: {1}  ({2} .. {3})  F5 = aktualisieren",
        "report.noEntries": "Keine Einträge in dieser Woche.", "report.noData": "Keine Daten vorhanden.",
        "todoReport.title": "Todo-Report (Markdown)  F5 = aktualisieren",
        "todoReport.kw": "# KW {0}", "todoReport.week": "## Woche", "todoReport.month": "## Monat ({0})",
        "todoReport.year": "## Jahr ({0})",
        "todoReport.emptyWeek": "* Keine offenen Todos in laufender Woche.",
        "todoReport.emptyMonth": "* Keine offenen Todos im laufenden Monat.",
        "todoReport.emptyYear": "* Keine offenen Todos im laufenden Jahr.",
        "todoReport.loadError": "Fehler: todo.json konnte nicht gelesen werden (F5 = erneut versuchen).",
        "scope.Woche": "Woche", "scope.Monat": "Monat", "scope.Jahr": "Jahr", "scope.Sonstiges": "Sonstiges",
        "todo.scopeTitle": "Todo: Zielgruppe (Woche/Monat/Jahr/Sonstiges)", "todo.showScope": "Todos anzeigen: Zielgruppe",
        "todo.descTitle": "Todo-Beschreibung", "todo.descLabel": "Bitte Beschreibung eingeben:",
        "todo.saved": "Todo gespeichert.",
        "todos.title": "Todos - {0}", "todos.none": "Keine offenen Todos in: {0}",
        "todos.loadError": "Fehler: todo.json konnte nicht gelesen werden.",
        "detail.title": "Todo: {0}", "detail.info": "Ziel: {0}\nKategorie: {1} -> {2}\nTask: {3}\nAngelegt: {4}",
        "detail.move": "Verschieben", "detail.close": "Schließen", "detail.done": "Erledigt",
        "detail.moved": "Todo verschoben nach: {0}",
        "detail.gone": "Das Todo existiert nicht mehr (evtl. auf einem anderen Rechner entfernt).",
        "detail.alreadyDone": "Todo ist bereits erledigt.", "detail.booked": "Todo als erledigt verbucht.",
        "settings.title": "Einstellungen", "settings.user": "Name des Benutzers:",
        "settings.export": "Export-Pfad (Reports):", "settings.language": "Sprache:",
        "settings.browse": "Durchsuchen…", "settings.browseTitle": "Ordner für den Report-Export wählen",
        "settings.storedAt": "Lokal gespeichert in: {0}",
        "settings.columnsWorklog": "Spalten Worklog…", "settings.columnsTodo": "Spalten Todo-Report…",
        "settings.createDir": "Der Ordner existiert nicht:\n{0}\n\nAnlegen?",
        "settings.createDirFailed": "Ordner konnte nicht angelegt werden: {0}",
        "export.title": "Reports exportieren",
        "export.needSettings": "Bitte zuerst in den Einstellungen Name und einen vorhandenen Export-Pfad hinterlegen.",
        "export.selectWeek": "Reports exportieren: Woche wählen", "export.done": "Exportiert nach {0}:\n\n{1}",
        "export.failed": "Export fehlgeschlagen:\n{0}",
        "export.kw": "KW", "export.fileWork": "Arbeitszeit", "export.fileTodos": "Todos",
        "columns.titleWorklog": "Spalten Worklog (CSV und Report)", "columns.titleTodo": "Spalten Todo-Report (Markdown)",
        "columns.add": "Hinzufügen…", "columns.remove": "Entfernen", "columns.up": "Nach oben", "columns.down": "Nach unten",
        "columns.header": "Überschrift…", "columns.format": "Format…", "columns.reset": "Standard",
        "columns.selectField": "Spalte hinzufügen", "columns.custom": "[Eigenes Feld…]",
        "columns.customName": "Name des eigenen Feldes:", "columns.headerLabel": "Spaltenüberschrift:",
        "columns.formatLabel": "Format ({value} = Wert):",
        "columns.noteWorklog": "Angehakte Spalten werden geschrieben (gilt für alle Rechner: columns.json im Datenordner). Leertaste = an/abwählen.\nBestehende Dateien werden erst angepasst, wenn ein Eintrag in sie geschrieben wird: fehlende Spalten werden ergänzt, abgewählte entfernt (Backup vorhanden).",
        "columns.noteTodo": "Jede Zeile: * Spalte1 | Spalte2 | ...   Gilt für alle Rechner (columns.json im Datenordner).",
        "columns.needWorklog": "Datum und eine Dauer-Spalte (Minuten oder h:mm) sind erforderlich.",
        "columns.needOne": "Mindestens eine Spalte ist erforderlich.",
        "field.Date": "Datum", "field.Weekday": "Wochentag", "field.StartTime": "Uhrzeit", "field.EndTime": "Endzeit",
        "field.Project": "Kategorie (Projekt)", "field.Category": "Unterkategorie (Tätigkeitskategorie)",
        "field.Description": "Task (Beschreibung)", "field.Minutes": "Dauer in Minuten", "field.Hours": "Dauer h:mm",
        "field.User": "Benutzer", "field.Path": "Kategorie->Unterkategorie", "field.TodoCategory": "Kategorie",
        "field.Subcategory": "Unterkategorie", "field.Task": "Task", "field.TodoDescription": "Beschreibung (1. Zeile)",
        "field.Scope": "Zielgruppe", "field.Created": "Angelegt (Datum)", "field.Id": "Id", "field.Custom": "Eigenes Feld: {0}",
        "menu.remTask": "Task entfernen",
        "task.remSelect": "Task zum Entfernen wählen",
        "task.remConfirm": "Task „{0}“ aus {1} -> {2} entfernen?\n\nBereits gebuchte Einträge bleiben erhalten.",
        "task.none": "In dieser Unterkategorie gibt es keine gespeicherten Tasks.",
        "entry.title": "Dauer eintragen – {0}", "entry.minutes": "Dauer (Minuten):", "entry.week": "Woche:",
        "entry.day": "Tag:", "entry.time": "Uhrzeit (HH:MM):",
        "columns.addCustom": "Eigenes Feld…", "columns.removeCustom": "Feld löschen",
        "columns.onlyCustom": "Nur eigene Felder können gelöscht werden – Standardspalten bitte abwählen.",
        "columns.colActive": "Aktiv", "columns.colField": "Spalte", "columns.colHeader": "Überschrift in der CSV",
        "weekdays": "Montag,Dienstag,Mittwoch,Donnerstag,Freitag,Samstag,Sonntag",
    },
    "en": {
        "app.title": "Work time",
        "menu.report": "Report", "menu.addTask": "Add task",
        "menu.addCat": "Add category/subcategory", "menu.remCat": "Remove category/subcategory",
        "menu.addTodo": "Add todo", "menu.todos": "Show todos", "menu.todoReport": "Todo report",
        "menu.export": "Export reports", "menu.settings": "Settings",
        "menu.recalc": "Recalculate today", "menu.exit": "Exit",
        "tray.today": "Today {0} min ({1})",
        "sel.category": "Select category", "sel.subcategory": "Select subcategory", "sel.task": "Select task",
        "sel.newTask": "[Enter new task]",
        "dlg.newTask.title": "New task", "dlg.newTask.label": "Short description:",
        "dlg.minutes.title": "Duration", "dlg.minutes.label": "Effort/duration in minutes:",
        "dlg.start.title": "Start time", "dlg.start.label": "Start time (HH:MM):",
        "btn.ok": "OK", "btn.cancel": "Cancel", "btn.save": "Save", "btn.select": "Select",
        "msg.info": "Info", "msg.hint": "Note", "msg.error": "Error", "msg.question": "Question",
        "msg.needCats": "Please create categories/subcategories first.",
        "msg.noSubs": "This category has no subcategory yet.",
        "msg.invalidEntry": "Please specify category, subcategory and minutes correctly.",
        "msg.invalidMinutes": "Please enter a valid number of minutes.",
        "msg.invalidTime": "Please enter a valid time in the format HH:MM.",
        "msg.loadError": "The file could not be read:\n{0}\n\nIt may currently be synchronising or it is damaged.\nThe change was NOT saved, so that no data is overwritten.\nPlease try again later (backups are in the subfolder 'backups').",
        "msg.saveError": "The file could not be saved:\n{0}\n\nPlease try again later.",
        "cat.new": "[Create new category]", "cat.newTitle": "New category", "cat.newLabel": "Name of the new category:",
        "cat.subTitle": "Add subcategory", "cat.subLabel": "Name of the subcategory for '{0}':",
        "cat.remSelect": "Select category to remove", "cat.remSub": "Remove subcategory",
        "cat.remAll": "[Remove entire category]",
        "week.select": "Select week", "week.label": "CW {0} / {1}   ({2} .. {3})",
        "report.title": "Report - CW {0}: {1}  ({2} .. {3})  F5 = refresh",
        "report.noEntries": "No entries in this week.", "report.noData": "No data available.",
        "todoReport.title": "Todo report (Markdown)  F5 = refresh",
        "todoReport.kw": "# CW {0}", "todoReport.week": "## Week", "todoReport.month": "## Month ({0})",
        "todoReport.year": "## Year ({0})",
        "todoReport.emptyWeek": "* No open todos in the current week.",
        "todoReport.emptyMonth": "* No open todos in the current month.",
        "todoReport.emptyYear": "* No open todos in the current year.",
        "todoReport.loadError": "Error: todo.json could not be read (F5 = try again).",
        "scope.Woche": "Week", "scope.Monat": "Month", "scope.Jahr": "Year", "scope.Sonstiges": "Other",
        "todo.scopeTitle": "Todo: scope (week/month/year/other)", "todo.showScope": "Show todos: scope",
        "todo.descTitle": "Todo description", "todo.descLabel": "Please enter a description:",
        "todo.saved": "Todo saved.",
        "todos.title": "Todos - {0}", "todos.none": "No open todos in: {0}",
        "todos.loadError": "Error: todo.json could not be read.",
        "detail.title": "Todo: {0}", "detail.info": "Scope: {0}\nCategory: {1} -> {2}\nTask: {3}\nCreated: {4}",
        "detail.move": "Move", "detail.close": "Close", "detail.done": "Done",
        "detail.moved": "Todo moved to: {0}",
        "detail.gone": "This todo no longer exists (possibly removed on another computer).",
        "detail.alreadyDone": "This todo is already done.", "detail.booked": "Todo marked as done and booked.",
        "settings.title": "Settings", "settings.user": "User name:",
        "settings.export": "Export path (reports):", "settings.language": "Language:",
        "settings.browse": "Browse…", "settings.browseTitle": "Select folder for the report export",
        "settings.storedAt": "Stored locally in: {0}",
        "settings.columnsWorklog": "Worklog columns…", "settings.columnsTodo": "Todo report columns…",
        "settings.createDir": "The folder does not exist:\n{0}\n\nCreate it?",
        "settings.createDirFailed": "The folder could not be created: {0}",
        "export.title": "Export reports",
        "export.needSettings": "Please set a user name and an existing export path in the settings first.",
        "export.selectWeek": "Export reports: select week", "export.done": "Exported to {0}:\n\n{1}",
        "export.failed": "Export failed:\n{0}",
        "export.kw": "CW", "export.fileWork": "Worktime", "export.fileTodos": "Todos",
        "columns.titleWorklog": "Worklog columns (CSV and report)", "columns.titleTodo": "Todo report columns (Markdown)",
        "columns.add": "Add…", "columns.remove": "Remove", "columns.up": "Move up", "columns.down": "Move down",
        "columns.header": "Header…", "columns.format": "Format…", "columns.reset": "Default",
        "columns.selectField": "Add column", "columns.custom": "[Custom field…]",
        "columns.customName": "Name of the custom field:", "columns.headerLabel": "Column header:",
        "columns.formatLabel": "Format ({value} = value):",
        "columns.noteWorklog": "Checked columns are written (applies to all computers: columns.json in the data folder). Space = check/uncheck.\nExisting files are only adapted when an entry is written to them: missing columns are added, unchecked ones removed (backup available).",
        "columns.noteTodo": "Each line: * column1 | column2 | ...   Applies to all computers (columns.json in the data folder).",
        "columns.needWorklog": "Date and a duration column (minutes or h:mm) are required.",
        "columns.needOne": "At least one column is required.",
        "field.Date": "Date", "field.Weekday": "Weekday", "field.StartTime": "Time", "field.EndTime": "End time",
        "field.Project": "Category (project)", "field.Category": "Subcategory (activity category)",
        "field.Description": "Task (description)", "field.Minutes": "Duration in minutes", "field.Hours": "Duration h:mm",
        "field.User": "User", "field.Path": "Category->Subcategory", "field.TodoCategory": "Category",
        "field.Subcategory": "Subcategory", "field.Task": "Task", "field.TodoDescription": "Description (1st line)",
        "field.Scope": "Scope", "field.Created": "Created (date)", "field.Id": "Id", "field.Custom": "Custom field: {0}",
        "menu.remTask": "Remove task",
        "task.remSelect": "Select task to remove",
        "task.remConfirm": "Remove task “{0}” from {1} -> {2}?\n\nEntries already logged are kept.",
        "task.none": "There are no saved tasks in this subcategory.",
        "entry.title": "Enter duration – {0}", "entry.minutes": "Duration (minutes):", "entry.week": "Week:",
        "entry.day": "Day:", "entry.time": "Time (HH:MM):",
        "columns.addCustom": "Custom field…", "columns.removeCustom": "Delete field",
        "columns.onlyCustom": "Only custom fields can be deleted – please uncheck standard columns instead.",
        "columns.colActive": "Active", "columns.colField": "Column", "columns.colHeader": "Header in the CSV",
        "weekdays": "Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday",
    },
}
LANG = "de"


def t(key, *args):
    s = STRINGS.get(LANG, STRINGS["de"]).get(key)
    if s is None:
        s = STRINGS["de"].get(key, key)
    return s.format(*args) if args else s


def default_language():
    for var in ("LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"):
        v = os.environ.get(var, "")
        if v:
            return "de" if v.lower().startswith("de") else "en"
    return "de"


# -----------------------------------------------------------------------------
# Spalten (columns.json im Datenordner, gilt für alle Rechner)
# -----------------------------------------------------------------------------
WL_FIELDS = ["Date", "Weekday", "StartTime", "EndTime", "Project", "Category", "Description", "Minutes", "Hours", "User"]
WL_HEADERS = {
    "de": {"Date": "Datum", "Weekday": "Wochentag", "StartTime": "Uhrzeit", "EndTime": "Endzeit",
           "Project": "Projekt oder IT-Service", "Category": "Tätigkeitskategorie",
           "Description": "kurze Tätigkeitsbeschreibung", "Minutes": "Aufwand bzw. Dauer",
           "Hours": "Dauer (h:mm)", "User": "Benutzer"},
    "en": {"Date": "Date", "Weekday": "Weekday", "StartTime": "Time", "EndTime": "End time",
           "Project": "Project or IT service", "Category": "Activity category",
           "Description": "Short activity description", "Minutes": "Effort / duration",
           "Hours": "Duration (h:mm)", "User": "User"},
}
WL_DEFAULT = ["Date", "Project", "Category", "Description", "Minutes"]
TODO_FIELDS = ["Path", "TodoCategory", "Subcategory", "Task", "TodoDescription", "Scope", "Created", "Id"]
TODO_DEFAULT = [("Path", "{value}"), ("Task", "{value}"), ("Created", "({value})")]
SUM_FIELDS = ("Minutes", "Hours")


def default_columns(lang=None):
    """Standard: die 5 Spalten des Originalformats aktiv, alle übrigen Standardfelder abgewählt."""
    lang = lang or LANG
    h = WL_HEADERS.get(lang, WL_HEADERS["de"])
    wl = [{"Field": f, "Header": h[f], "Active": True} for f in WL_DEFAULT]
    wl += [{"Field": f, "Header": h[f], "Active": False} for f in WL_FIELDS if f not in WL_DEFAULT]
    return {"Worklog": wl, "Todo": [{"Field": f, "Format": fmt} for f, fmt in TODO_DEFAULT]}


def sort_key(s):
    """Alphabetisch, ohne Groß/Klein und mit Umlauten bei den Grundbuchstaben (Ä bei A)."""
    import unicodedata
    base = "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))
    return (base.casefold(), s)


def is_custom(field):
    return field.startswith("Custom:")


def custom_name(field):
    return field[7:]


def field_display(field):
    if is_custom(field):
        return t("field.Custom", custom_name(field))
    return t("field." + field)


def _valid_field(f, kind):
    if not isinstance(f, str) or not f:
        return False
    if is_custom(f):
        return bool(custom_name(f).strip())
    return f in (WL_FIELDS if kind == "Worklog" else TODO_FIELDS)


def load_columns_all():
    """Liest columns.json vollständig: Worklog inkl. abgewählter Spalten (Active=False).
    Fehlende Standardfelder werden abgewählt ergänzt; fehlt die Datei -> Standard."""
    d = default_columns()
    try:
        obj = read_json(COLUMNS_FILE) or {}
    except LoadError:
        obj = {}
    wl, seen = [], set()
    for c in obj.get("Worklog") or []:
        if isinstance(c, dict) and _valid_field(c.get("Field"), "Worklog") and c["Field"] not in seen:
            f = c["Field"]
            hdr = c.get("Header")
            if not hdr:
                hdr = custom_name(f) if is_custom(f) else WL_HEADERS.get(LANG, WL_HEADERS["de"])[f]
            wl.append({"Field": f, "Header": str(hdr), "Active": c.get("Active", True) is not False})
            seen.add(f)
    if not any(c["Active"] for c in wl):
        wl, seen = [], set()
    for c in d["Worklog"]:
        if c["Field"] not in seen:
            wl.append(dict(c, Active=c["Active"] if not seen else False))
    td = []
    for c in obj.get("Todo") or []:
        if isinstance(c, dict) and _valid_field(c.get("Field"), "Todo"):
            td.append({"Field": c["Field"], "Format": str(c.get("Format") or "{value}")})
    return {"Worklog": wl, "Todo": td or d["Todo"]}


def load_columns():
    """Aktive Spalten: Worklog [{Field, Header}] in Reihenfolge, Todo [{Field, Format}]."""
    a = load_columns_all()
    wl = [{"Field": c["Field"], "Header": c["Header"]} for c in a["Worklog"] if c["Active"]]
    return {"Worklog": wl, "Todo": a["Todo"]}


def save_columns_part(kind, cols):
    """Frisch laden, nur den Teil 'kind' ersetzen, speichern (Worklog inkl. Active-Flag)."""
    cur = load_columns_all()
    cur[kind] = cols
    write_json(COLUMNS_FILE, {"Worklog": cur["Worklog"], "Todo": cur["Todo"]})


class LoadError(Exception):
    """Datei existiert, konnte aber nicht gelesen/geparst werden -> nicht überschreiben!"""
    def __init__(self, path):
        Exception.__init__(self, path)
        self.path = path


class SaveError(Exception):
    def __init__(self, path):
        Exception.__init__(self, path)
        self.path = path


# -----------------------------------------------------------------------------
# Datei-IO (Retries, Backups, atomarer Austausch)
# -----------------------------------------------------------------------------
def new_backup_rotating(target):
    """Rotierendes Backup in <ordner>/backups: <name>.0 = Zustand vor dem Schreiben."""
    try:
        if not os.path.isfile(target):
            return
        bdir = os.path.join(os.path.dirname(target), "backups")
        os.makedirs(bdir, exist_ok=True)
        name = os.path.basename(target)
        keep = max(1, int(BACKUP_KEEP))
        oldest = os.path.join(bdir, "%s.%d" % (name, keep - 1))
        if os.path.exists(oldest):
            os.remove(oldest)
        for i in range(keep - 2, -1, -1):
            src = os.path.join(bdir, "%s.%d" % (name, i))
            if os.path.exists(src):
                os.replace(src, os.path.join(bdir, "%s.%d" % (name, i + 1)))
        shutil.copyfile(target, os.path.join(bdir, "%s.0" % name))
    except OSError as e:
        log("Backup FEHLER: %s" % e)


def safe_read_text(path, allow_empty=False, retries=10, delay=0.3):
    """Rückgabe: Inhalt (str) oder None, wenn Datei nicht existiert. Wirft LoadError."""
    for attempt in range(1, retries + 1):
        try:
            if not os.path.exists(path):
                return None
            with open(path, "r", encoding="utf-8-sig", newline="") as f:
                content = f.read()
            if not allow_empty and not content.strip():
                raise ValueError("Datei ist leer")
            return content
        except (OSError, ValueError, UnicodeDecodeError) as e:
            log("SafeRead %s Versuch %d: %s" % (path, attempt, e))
            time.sleep(delay)
    raise LoadError(path)


def safe_write_text(path, lines, retries=20, delay=0.3):
    """Schreibt alle Zeilen (CRLF, abschließender Umbruch, UTF-8 mit BOM). Wirft SaveError."""
    text = "\r\n".join(lines) + "\r\n"
    d = os.path.dirname(path)
    name = os.path.basename(path)
    os.makedirs(d, exist_ok=True)
    if os.path.exists(path):
        new_backup_rotating(path)   # genau einmal pro Schreibvorgang
    for attempt in range(1, retries + 1):
        rnd = "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(8))
        tmp = os.path.join(d, "~%s.%s.tmp" % (name, rnd))   # "~*.tmp" synchronisiert Nextcloud nicht
        try:
            with open(tmp, "w", encoding="utf-8-sig", newline="") as f:
                f.write(text)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, path)   # atomar
            log("SafeWrite OK %s" % path)
            return
        except OSError as e:
            log("SafeWrite %s Versuch %d: %s" % (path, attempt, e))
            time.sleep(delay)
        finally:
            if os.path.exists(tmp):
                try:
                    os.remove(tmp)
                except OSError:
                    pass
    raise SaveError(path)


def read_json(path):
    """None wenn Datei fehlt; wirft LoadError bei Lese-/Parsefehler."""
    raw = safe_read_text(path)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except ValueError as e:
        log("JSON-Fehler %s: %s" % (path, e))
        raise LoadError(path)


def write_json(path, obj):
    safe_write_text(path, [json.dumps(obj, ensure_ascii=False, indent=2)])


# -----------------------------------------------------------------------------
# Datum / Woche
# -----------------------------------------------------------------------------
_ISO_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2})?)(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$")


def parse_dt(v):
    """Robustes Parsen (auch .NET-Format mit 7 Nachkommastellen). Rückgabe: naive lokale Zeit oder None."""
    if v is None:
        return None
    if isinstance(v, dt.datetime):
        d = v
    else:
        s = str(v).strip()
        if not s:
            return None
        m = _ISO_RE.match(s)
        try:
            if m:
                datep, timep, frac, tz = m.groups()
                if len(timep) == 5:
                    timep += ":00"
                frac = (frac or ".0")[1:7].ljust(6, "0")
                d = dt.datetime.strptime("%s %s.%s" % (datep, timep, frac), "%Y-%m-%d %H:%M:%S.%f")
                if tz:
                    if tz == "Z":
                        off = dt.timedelta(0)
                    else:
                        sign = 1 if tz[0] == "+" else -1
                        tzs = tz[1:].replace(":", "")
                        off = sign * dt.timedelta(hours=int(tzs[:2]), minutes=int(tzs[2:]))
                    d = d.replace(tzinfo=dt.timezone(off))
            else:
                d = None
                for fmt in ("%Y-%m-%d", "%d.%m.%Y %H:%M:%S", "%d.%m.%Y", "%m/%d/%Y %H:%M:%S"):
                    try:
                        d = dt.datetime.strptime(s, fmt)
                        break
                    except ValueError:
                        pass
                if d is None:
                    return None
        except ValueError:
            return None
    if d.tzinfo is not None:
        d = d.astimezone().replace(tzinfo=None)
    return d


def to_iso(d):
    """Lokale Zeit mit Offset, wie .NET ToString("o")."""
    if d is None:
        return None
    return d.astimezone().isoformat(timespec="microseconds")


def week_monday(d=None):
    d = d or dt.date.today()
    if isinstance(d, dt.datetime):
        d = d.date()
    return d - dt.timedelta(days=d.weekday())


def iso_week(d):
    if isinstance(d, dt.datetime):
        d = d.date()
    return d.isocalendar()[1]


def iso_week_year(d):
    if isinstance(d, dt.datetime):
        d = d.date()
    return d.isocalendar()[0]


def week_file(d=None):
    return os.path.join(TASKS_DIR, "%s_worklog.csv" % week_monday(d).strftime("%Y-%m-%d"))


def week_label(monday):
    """Anzeige in Dialogen: zuerst KW, dann Zeitraum."""
    return t("week.label", "%02d" % iso_week(monday), iso_week_year(monday), monday.strftime("%Y-%m-%d"),
             (monday + dt.timedelta(days=6)).strftime("%Y-%m-%d"))


def to_hhmm(mins):
    return "%d:%02d" % (mins // 60, mins % 60)


def parse_hhmm(s):
    """'8:05' -> 485 Minuten, sonst None."""
    m = re.match(r"^\s*(\d{1,3}):(\d{2})\s*$", s or "")
    if not m or int(m.group(2)) > 59:
        return None
    return int(m.group(1)) * 60 + int(m.group(2))


def parse_clock(s):
    """'08:30' / '8:30' -> 'HH:MM', sonst None."""
    m = re.match(r"^\s*(\d{1,2}):(\d{2})\s*$", s or "")
    if not m or int(m.group(1)) > 23 or int(m.group(2)) > 59:
        return None
    return "%02d:%02d" % (int(m.group(1)), int(m.group(2)))


def fmt_date(d):
    return d.strftime("%Y-%m-%d") if d else ""


# -----------------------------------------------------------------------------
# Kategorien / Taskkatalog / Todos (immer frisch laden, sofort speichern)
# -----------------------------------------------------------------------------
def _as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return [str(x) for x in v if x is not None]
    return [str(v)]


def load_categories():
    obj = read_json(CATS_FILE) or {}
    cats = {k: _as_list(v) for k, v in (obj.get("Categories") or {}).items()}
    return cats, dict(obj.get("Focus") or {})


def save_categories(cats, focus):
    write_json(CATS_FILE, {"Categories": cats, "Focus": focus})


def load_task_catalog():
    obj = read_json(TASK_CATALOG_FILE) or {}
    return {k: _as_list(v) for k, v in (obj.get("Tasks") or {}).items()}


def save_task_catalog(cat):
    write_json(TASK_CATALOG_FILE, {"Tasks": cat})


def add_task_to_catalog(key, task):
    cat = load_task_catalog()
    lst = cat.get(key, [])
    if task not in lst:
        lst.append(task)
        cat[key] = lst
        save_task_catalog(cat)


def load_todos():
    obj = read_json(TODOS_FILE) or {}
    raw = obj.get("Todos") or []
    if isinstance(raw, dict):
        raw = [raw]
    todos = []
    for x in raw:
        try:
            dm = x.get("DoneMinutes")
            extra = x.get("Extra") or {}
            todos.append({
                "Id": str(x.get("Id") or ""), "Scope": str(x.get("Scope") or ""),
                "Category": str(x.get("Category") or ""), "Subcategory": str(x.get("Subcategory") or ""),
                "Task": str(x.get("Task") or ""), "Description": str(x.get("Description") or ""),
                "Created": parse_dt(x.get("Created")), "Done": bool(x.get("Done")),
                "DoneMinutes": int(dm) if dm is not None else None, "DoneDate": parse_dt(x.get("DoneDate")),
                "Extra": {str(k): ("" if v is None else str(v)) for k, v in extra.items()} if isinstance(extra, dict) else {},
            })
        except (AttributeError, TypeError, ValueError) as e:
            log("Todo-Eintrag fehlerhaft: %s" % e)
    return todos


def save_todos(todos):
    out = []
    for x in todos:
        out.append({
            "Id": x["Id"], "Scope": x["Scope"], "Category": x["Category"],
            "Subcategory": x["Subcategory"], "Task": x["Task"], "Description": x["Description"],
            "Created": to_iso(x["Created"]), "Done": bool(x["Done"]),
            "DoneMinutes": x["DoneMinutes"], "DoneDate": to_iso(x["DoneDate"]),
            "Extra": dict(x.get("Extra") or {}),
        })
    write_json(TODOS_FILE, {"Todos": out})


def update_todo(todo_id, change):
    """Frisch laden -> per Id ändern -> speichern. Rückgabe: True oder False (nicht gefunden)."""
    todos = load_todos()
    for x in todos:
        if x["Id"] == todo_id:
            change(x)
            save_todos(todos)
            return True
    return False


def open_todos(todos, scope):
    lst = [x for x in todos if x["Scope"] == scope and not x["Done"]]
    lst.sort(key=lambda x: (x["Created"] is not None, x["Created"] or dt.datetime.min))
    return lst


# -----------------------------------------------------------------------------
# Worklog-CSV (Spalten werden beim Lesen über die Kopfzeile erkannt)
# -----------------------------------------------------------------------------
_GLUE_RE = re.compile(r"(?<=\d|r)(?=\d{4}-\d{2}-\d{2};)")
_DATE_CELL = re.compile(r"^\s*\d{4}-\d{2}-\d{2}\s*$")


def split_glued_lines(lines):
    """Trennt Zeilen, die das alte Windows-Script (<= 2.1.21) zusammengeklebt hat."""
    out = []
    for ln in lines:
        pos = 0
        for m in _GLUE_RE.finditer(ln):
            if ln[m.start() - 1].isdigit() or ln[:m.start()].endswith("Dauer"):
                out.append(ln[pos:m.start()])
                pos = m.start()
        out.append(ln[pos:])
    return out


def read_worklog_lines(path):
    content = safe_read_text(path, allow_empty=True)
    if not content:
        return []
    return [l for l in split_glued_lines(re.split(r"\r?\n", content)) if l.strip()]


def header_field_map(cols):
    """Kopfzeilen-Text (klein) -> Feld; aus aktueller Konfiguration und den Standardtexten DE/EN."""
    m = {}
    for lang in ("en", "de"):
        for f, h in WL_HEADERS[lang].items():
            m[h.lower()] = f
    for f in WL_FIELDS:
        m[f.lower()] = f
    for alias in ("startzeit", "start time"):   # Überschriften aus Version 2.4
        m[alias] = "StartTime"
    for c in cols:
        m[c["Header"].strip().lower()] = c["Field"]
    return m


def parse_worklog(path, cols=None):
    """Liefert die Einträge einer Wochendatei als Dicts (Felder s. WL_FIELDS + Custom:*)."""
    cols = cols if cols is not None else load_columns()["Worklog"]
    lines = read_worklog_lines(path)
    if not lines:
        return []
    hmap = header_field_map(cols)
    first = lines[0].split(";")
    if _DATE_CELL.match(first[0]):
        fields = list(WL_DEFAULT)      # Datei ohne Kopfzeile -> Standardlayout
        data = lines
    else:
        fields = []
        for h in first:
            key = h.strip()
            fields.append(hmap.get(key.lower(), "Custom:" + key if key else ""))
        data = lines[1:]
    rows = []
    for ln in data:
        cells = ln.split(";")
        raw = {}
        for i, f in enumerate(fields):
            if f and i < len(cells):
                raw[f] = cells[i].strip()
        d = parse_dt(raw.get("Date", ""))
        if d is None:
            continue
        mins = None
        if raw.get("Minutes", "") != "":
            try:
                mins = int(raw["Minutes"])
            except ValueError:
                mins = None
        if mins is None and raw.get("Hours"):
            mins = parse_hhmm(raw["Hours"])
        row = {"Date": d.date(), "StartTime": parse_clock(raw.get("StartTime", "")) or "",
               "EndTime": parse_clock(raw.get("EndTime", "")) or "", "Project": raw.get("Project", ""),
               "Category": raw.get("Category", ""), "Description": raw.get("Description", ""),
               "Minutes": mins or 0, "User": raw.get("User", "")}
        for k, v in raw.items():
            if is_custom(k):
                row[k] = v
        rows.append(row)
    return rows


def end_time(row):
    if row.get("EndTime"):
        return row["EndTime"]
    if row.get("StartTime"):
        h, m = map(int, row["StartTime"].split(":"))
        tot = (h * 60 + m + int(row.get("Minutes") or 0)) % (24 * 60)
        return "%02d:%02d" % (tot // 60, tot % 60)
    return ""


def wl_value(row, field):
    if field == "Date":
        return row["Date"].strftime("%Y-%m-%d")
    if field == "Weekday":
        return t("weekdays").split(",")[row["Date"].weekday()]
    if field == "EndTime":
        return end_time(row)
    if field == "Minutes":
        return str(int(row.get("Minutes") or 0))
    if field == "Hours":
        return to_hhmm(int(row.get("Minutes") or 0))
    return str(row.get(field, "") or "")


def clean_field(s):
    return re.sub(r"[;\r\n]+", ",", s or "").strip()


def render_header(cols):
    return ";".join(clean_field(c["Header"]) for c in cols)


def render_row(row, cols):
    return ";".join(clean_field(wl_value(row, c["Field"])) for c in cols)


def write_task_entry(when, project, category, desc, minutes, extras=None):
    """Eintrag anhängen: frisch lesen -> Zeile ergänzen -> Datei im aktuellen Spaltenlayout schreiben."""
    cols = load_columns()["Worklog"]
    f = week_file(when)
    rows = parse_worklog(f, cols)
    row = {"Date": when.date() if isinstance(when, dt.datetime) else when, "StartTime": "", "EndTime": "",
           "Project": project, "Category": category, "Description": desc, "Minutes": int(minutes),
           "User": load_settings()["UserName"]}
    row.update(extras or {})
    rows.append(row)
    safe_write_text(f, [render_header(cols)] + [render_row(r, cols) for r in rows])


def repair_all_worklogs():
    fixed = 0
    if not os.path.isdir(TASKS_DIR):
        return 0
    for name in sorted(os.listdir(TASKS_DIR)):
        if not name.endswith("_worklog.csv"):
            continue
        p = os.path.join(TASKS_DIR, name)
        try:
            content = safe_read_text(p, allow_empty=True)
        except LoadError:
            continue
        if not content:
            continue
        raw = [l for l in re.split(r"\r?\n", content) if l.strip()]
        split = [l for l in split_glued_lines(raw) if l.strip()]
        if len(split) != len(raw):
            log("Repariere %s: %d -> %d Zeilen" % (name, len(raw), len(split)))
            safe_write_text(p, split)
            fixed += 1
    return fixed


def today_totals():
    today = dt.date.today()
    try:
        return sum(r["Minutes"] for r in parse_worklog(week_file(today)) if r["Date"] == today)
    except LoadError:
        return 0


def week_report(monday):
    """Report im konfigurierten Spaltenlayout: Zeilen mit gleichen Werten (außer Dauer) werden summiert."""
    cols = load_columns()["Worklog"]
    f = week_file(monday)
    rows = parse_worklog(f, cols)
    key_fields = [c["Field"] for c in cols if c["Field"] not in SUM_FIELDS]
    order = ["Date", "StartTime"] + [k for k in key_fields if k not in ("Date", "StartTime")]
    acc = {}
    total = 0
    for r in rows:
        k = tuple(wl_value(r, fld) for fld in key_fields)
        if k not in acc:
            acc[k] = (dict(r), 0)
        base, s = acc[k]
        acc[k] = (base, s + r["Minutes"])
        total += r["Minutes"]
    items = []
    for base, s in acc.values():
        base = dict(base)
        base["Minutes"] = s
        if "EndTime" not in key_fields:
            base["EndTime"] = ""
        sort_key = "\x1f".join(wl_value(base, fld) for fld in order if fld in key_fields or fld == "Date").upper()
        items.append((sort_key, render_row(base, cols)))
    items.sort(key=lambda x: x[0])
    return {"lines": [render_header(cols)] + [x[1] for x in items], "minutes": total,
            "has_entries": bool(rows), "file_exists": os.path.exists(f)}


def todo_value(x, field):
    if field == "Path":
        return "%s->%s" % (x["Category"], x["Subcategory"])
    if field == "TodoCategory":
        return x["Category"]
    if field == "TodoDescription":
        return (x["Description"].splitlines() or [""])[0]
    if field == "Scope":
        return t("scope." + x["Scope"]) if x["Scope"] in SCOPES else x["Scope"]
    if field == "Created":
        return fmt_date(x["Created"])
    if is_custom(field):
        return (x.get("Extra") or {}).get(custom_name(field), "")
    return str(x.get(field, "") or "")


def todo_line(x, cols):
    return "* " + " | ".join(c["Format"].replace("{value}", todo_value(x, c["Field"])) for c in cols)


def todo_report_lines(todos, ref=None):
    """Todo-Report (Markdown) - nur Woche/Monat/Jahr."""
    ref = ref or dt.datetime.now()
    cols = load_columns()["Todo"]
    lines = [t("todoReport.kw", iso_week(ref))]
    sections = [("Woche", t("todoReport.week"), t("todoReport.emptyWeek")),
                ("Monat", t("todoReport.month", ref.strftime("%Y-%m")), t("todoReport.emptyMonth")),
                ("Jahr", t("todoReport.year", ref.strftime("%Y")), t("todoReport.emptyYear"))]
    for scope, title, empty in sections:
        lines += ["", title]
        items = open_todos(todos, scope)
        if not items:
            lines.append(empty)
        lines += [todo_line(x, cols) for x in items]
    return lines


def list_weeks():
    """[(monday, label)] aufsteigend."""
    res = []
    if os.path.isdir(TASKS_DIR):
        for name in sorted(os.listdir(TASKS_DIR)):
            m = re.match(r"^(\d{4}-\d{2}-\d{2})_worklog\.csv$", name)
            if not m:
                continue
            try:
                mon = dt.datetime.strptime(m.group(1), "%Y-%m-%d").date()
            except ValueError:
                continue
            res.append((mon, week_label(mon)))
    return res


# -----------------------------------------------------------------------------
# Einstellungen + Export
# -----------------------------------------------------------------------------
def load_settings():
    s = {"UserName": os.environ.get("USER", ""), "ExportPath": "", "Language": default_language()}
    try:
        obj = read_json(SETTINGS_FILE) or {}
        for k in s:
            if obj.get(k) is not None:
                s[k] = str(obj[k])
    except LoadError:
        pass
    if s["Language"] not in STRINGS:
        s["Language"] = "de"
    return s


def save_settings(s):
    write_json(SETTINGS_FILE, {"UserName": s["UserName"], "ExportPath": s["ExportPath"], "Language": s["Language"]})


def apply_language():
    global LANG
    LANG = load_settings()["Language"]


def safe_filename(s):
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", s or "").strip()


def export_reports(monday, user, export_path):
    """<Name>_KW<nn>_<Jahr>_Arbeitszeit.csv und ..._Todos.md. Rückgabe: Liste der Dateinamen."""
    prefix = "%s_%s%02d_%d" % (safe_filename(user), t("export.kw"), iso_week(monday), iso_week_year(monday))
    rep = week_report(monday)
    csv_path = os.path.join(export_path, "%s_%s.csv" % (prefix, t("export.fileWork")))
    with open(csv_path, "w", encoding="utf-8-sig", newline="") as f:
        f.write("\r\n".join(rep["lines"]) + "\r\n")
    todos = load_todos()
    ref = dt.datetime.now() if week_monday() == monday else dt.datetime.combine(monday + dt.timedelta(days=3), dt.time())
    md_path = os.path.join(export_path, "%s_%s.md" % (prefix, t("export.fileTodos")))
    with open(md_path, "w", encoding="utf-8", newline="") as f:
        f.write("\r\n".join(todo_report_lines(todos, ref)) + "\r\n")
    return [os.path.basename(csv_path), os.path.basename(md_path)]


# =============================================================================
# GUI (GTK 3)
# =============================================================================
Gtk = Gdk = GLib = None
INDICATOR_MOD = None


def import_gtk():
    global Gtk, Gdk, GLib, INDICATOR_MOD
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk as _Gtk, Gdk as _Gdk, GLib as _GLib
    except (ImportError, ValueError) as e:
        sys.stderr.write("GTK 3 fehlt / missing: %s\nsudo apt install python3-gi gir1.2-gtk-3.0\n" % e)
        sys.exit(1)
    Gtk, Gdk, GLib = _Gtk, _Gdk, _GLib
    for name in ("AyatanaAppIndicator3", "AppIndicator3"):
        try:
            gi.require_version(name, "0.1")
            INDICATOR_MOD = __import__("gi.repository." + name, fromlist=[name])
            break
        except (ImportError, ValueError):
            continue


def _is_key(ev, *names):
    return any(ev.keyval == getattr(Gdk, "KEY_" + n) for n in names)


def _prepare(dlg, w=None, h=None):
    dlg.set_keep_above(True)
    dlg.set_position(Gtk.WindowPosition.CENTER)
    if w and h:
        dlg.set_default_size(w, h)


def _message(kind, buttons, text, title):
    d = Gtk.MessageDialog(message_type=kind, buttons=buttons, text=title)
    d.format_secondary_text(text)
    if buttons == Gtk.ButtonsType.YES_NO:
        d.set_default_response(Gtk.ResponseType.YES)
    _prepare(d)
    r = d.run()
    d.destroy()
    return r


def msg_info(text, title=None):
    _message(Gtk.MessageType.INFO, Gtk.ButtonsType.OK, text, title or t("msg.info"))


def msg_error(text, title=None):
    _message(Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, text, title or t("msg.error"))


def ask_yes_no(text, title=None):
    return _message(Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, text, title or t("msg.question")) == Gtk.ResponseType.YES


def guarded(fn):
    """Fängt Lade-/Speicherfehler ab und zeigt eine Meldung."""
    def wrapper(*a, **kw):
        try:
            return fn(*a, **kw)
        except LoadError as e:
            msg_error(t("msg.loadError", e.path))
        except SaveError as e:
            msg_error(t("msg.saveError", e.path))
        return None
    wrapper.__name__ = fn.__name__
    return wrapper


def _list_view(columns=1):
    store = Gtk.ListStore(*([str] * columns))
    tv = Gtk.TreeView(model=store)
    tv.set_headers_visible(False)
    tv.append_column(Gtk.TreeViewColumn("", Gtk.CellRendererText(), text=0))
    tv.set_search_column(0)
    sw = Gtk.ScrolledWindow()
    sw.set_hexpand(True)
    sw.set_vexpand(True)
    sw.add(tv)
    return store, tv, sw


def select_dialog(title, items, preselect=0):
    """Liste: Enter/Rechts/Doppelklick = Auswahl, Esc/Links = zurück. Tippen = Suchen."""
    items = list(items)
    d = Gtk.Dialog(title=title)
    _prepare(d, 480, 360)
    store, tv, sw = _list_view()
    for it in items:
        store.append([str(it)])
    d.get_content_area().pack_start(sw, True, True, 0)
    result = {"value": None}

    def accept():
        model, it = tv.get_selection().get_selected()
        if it is not None:
            result["value"] = model[it][0]
            d.response(Gtk.ResponseType.OK)

    def on_key(_w, ev):
        if _is_key(ev, "Return", "KP_Enter", "Right"):
            accept()
            return True
        if _is_key(ev, "Escape", "Left"):
            d.response(Gtk.ResponseType.CANCEL)
            return True
        return False

    tv.connect("key-press-event", on_key)
    tv.connect("row-activated", lambda *_: accept())
    if items:
        idx = max(0, min(preselect, len(items) - 1))
        tv.set_cursor(Gtk.TreePath(idx), None, False)
        GLib.idle_add(lambda: tv.scroll_to_cell(Gtk.TreePath(idx), None, True, 0.5, 0) and False)
    d.show_all()
    tv.grab_focus()
    d.present()
    d.run()
    d.destroy()
    return result["value"]


def input_dialog(title, label, initial=""):
    d = Gtk.Dialog(title=title)
    _prepare(d, 420, 120)
    d.add_button(t("btn.cancel"), Gtk.ResponseType.CANCEL)
    d.add_button(t("btn.ok"), Gtk.ResponseType.OK)
    d.set_default_response(Gtk.ResponseType.OK)
    box = d.get_content_area()
    box.set_spacing(8)
    box.set_border_width(12)
    box.pack_start(Gtk.Label(label=label, xalign=0), False, False, 0)
    entry = Gtk.Entry()
    entry.set_text(initial)
    entry.set_activates_default(True)
    box.pack_start(entry, False, False, 0)

    def on_key(_w, ev):
        if _is_key(ev, "Left") and not entry.get_text():   # zurück nur ohne Eingabe
            d.response(Gtk.ResponseType.CANCEL)
            return True
        return False

    entry.connect("key-press-event", on_key)
    d.show_all()
    entry.grab_focus()
    d.present()
    r = d.run()
    text = entry.get_text()
    d.destroy()
    return text if r == Gtk.ResponseType.OK else None


def _text_view(editable, mono=False, text=""):
    tv = Gtk.TextView()
    tv.set_editable(editable)
    tv.set_cursor_visible(editable)
    tv.set_wrap_mode(Gtk.WrapMode.NONE if mono else Gtk.WrapMode.WORD_CHAR)
    tv.set_monospace(mono)
    tv.get_buffer().set_text(text)
    sw = Gtk.ScrolledWindow()
    sw.set_hexpand(True)
    sw.set_vexpand(True)
    sw.add(tv)
    return tv, sw


def _get_text(tv):
    b = tv.get_buffer()
    return b.get_text(b.get_start_iter(), b.get_end_iter(), True)


def textarea_dialog(title, label):
    d = Gtk.Dialog(title=title)
    _prepare(d, 600, 460)
    d.add_button(t("btn.cancel"), Gtk.ResponseType.CANCEL)
    d.add_button(t("btn.ok"), Gtk.ResponseType.OK)
    box = d.get_content_area()
    box.set_spacing(6)
    box.set_border_width(12)
    box.pack_start(Gtk.Label(label=label, xalign=0), False, False, 0)
    tv, sw = _text_view(True)
    box.pack_start(sw, True, True, 0)
    d.show_all()
    tv.grab_focus()
    d.present()
    r = d.run()
    text = _get_text(tv)
    d.destroy()
    return text if r == Gtk.ResponseType.OK else None


def text_window(title_fn, text_fn):
    """Schreibgeschützte Textanzeige (Report). F5 = aktualisieren, Esc/Links = schließen."""
    d = Gtk.Dialog(title="Report")
    _prepare(d, 900, 520)
    tv, sw = _text_view(False, mono=True)
    d.get_content_area().pack_start(sw, True, True, 0)

    def refresh():
        tv.get_buffer().set_text(text_fn())
        d.set_title(title_fn())

    def on_key(_w, ev):
        if _is_key(ev, "F5"):
            refresh()
            return True
        if _is_key(ev, "Escape", "Left"):
            d.response(Gtk.ResponseType.CLOSE)
            return True
        return False

    d.connect("key-press-event", on_key)
    refresh()
    d.show_all()
    d.present()
    d.run()
    d.destroy()


def folder_dialog(title, initial=""):
    d = Gtk.FileChooserDialog(title=title, action=Gtk.FileChooserAction.SELECT_FOLDER)
    d.add_button(t("btn.cancel"), Gtk.ResponseType.CANCEL)
    d.add_button(t("btn.select"), Gtk.ResponseType.OK)
    _prepare(d)
    if initial and os.path.isdir(initial):
        d.set_current_folder(initial)
    r = d.run()
    path = d.get_filename()
    d.destroy()
    return path if r == Gtk.ResponseType.OK else None


# -----------------------------------------------------------------------------
# Aktionen
# -----------------------------------------------------------------------------
def select_task_triple():
    cats, _focus = load_categories()
    catalog = load_task_catalog()
    if not cats:
        msg_info(t("msg.needCats"), t("msg.hint"))
        return None
    cat = select_dialog(t("sel.category"), sorted(cats, key=sort_key))
    if not cat:
        return None
    subs = cats.get(cat, [])
    if not subs:
        msg_info(t("msg.noSubs"), t("msg.hint"))
        return None
    sub = select_dialog(t("sel.subcategory"), sorted(subs, key=sort_key))
    if not sub:
        return None
    key = "%s::%s" % (cat, sub)
    new_task = t("sel.newTask")
    sel = select_dialog(t("sel.task"), sorted(set(catalog.get(key, [])), key=sort_key) + [new_task])
    if not sel:
        return None
    if sel == new_task:
        desc = input_dialog(t("dlg.newTask.title"), t("dlg.newTask.label"))
        if not desc or not desc.strip():
            return None
        desc = desc.strip()
        add_task_to_catalog(key, desc)
    else:
        desc = sel
    return {"category": cat, "subcategory": sub, "desc": desc}


def ask_custom_values(fields):
    """Fragt eigene Felder ab. Rückgabe: dict oder None (abgebrochen)."""
    vals = {}
    for f in fields:
        if not is_custom(f):
            continue
        v = input_dialog(custom_name(f), custom_name(f) + ":")
        if v is None:
            return None
        vals[f] = v.strip()
    return vals


ENTRY_WEEKS_BACK = 52   # wie weit rückwirkend eingetragen werden kann (Wochen)


def entry_dialog(task_label):
    """Dauer eintragen: Fokus auf Minuten; per Tab Woche, Tag, ggf. Uhrzeit und eigene Felder
    (Standard: jetzt). Enter = speichern, Esc = abbrechen.
    Rückgabe: {"minutes", "date" (datetime), "extras"} oder None."""
    fields = [c["Field"] for c in load_columns()["Worklog"]]
    need_time = "StartTime" in fields or "EndTime" in fields
    customs = [f for f in fields if is_custom(f)]
    now = dt.datetime.now()
    cur_mon = week_monday(now)
    weeks = [cur_mon - dt.timedelta(weeks=i) for i in range(ENTRY_WEEKS_BACK + 1)]
    day_names = t("weekdays").split(",")

    d = Gtk.Dialog(title=t("entry.title", task_label))
    _prepare(d, 460, 0)
    d.add_button(t("btn.cancel"), Gtk.ResponseType.CANCEL)
    d.add_button(t("btn.ok"), Gtk.ResponseType.OK)
    d.set_default_response(Gtk.ResponseType.OK)
    grid = Gtk.Grid(column_spacing=10, row_spacing=8)
    grid.set_border_width(12)
    row = [0]

    def add_row(label, widget):
        grid.attach(Gtk.Label(label=label, xalign=0), 0, row[0], 1, 1)
        widget.set_hexpand(True)
        grid.attach(widget, 1, row[0], 1, 1)
        row[0] += 1
        if isinstance(widget, Gtk.Entry):
            widget.set_activates_default(True)
        return widget

    e_min = add_row(t("entry.minutes"), Gtk.Entry())
    c_week = add_row(t("entry.week"), Gtk.ComboBoxText())
    for m in weeks:
        c_week.append_text(week_label(m))
    c_week.set_active(0)
    c_day = add_row(t("entry.day"), Gtk.ComboBoxText())

    def fill_days(keep):
        mon = weeks[max(0, c_week.get_active())]
        c_day.remove_all()
        for i in range(7):
            c_day.append_text("%s, %s" % (day_names[i], (mon + dt.timedelta(days=i)).strftime("%Y-%m-%d")))
        c_day.set_active(keep)

    fill_days(now.weekday())
    c_week.connect("changed", lambda *_: fill_days(max(0, c_day.get_active())))
    e_time = None
    if need_time:
        e_time = add_row(t("entry.time"), Gtk.Entry())
        e_time.set_text(now.strftime("%H:%M"))
    e_custom = {}
    for f in customs:
        e_custom[f] = add_row(custom_name(f) + ":", Gtk.Entry())
    d.get_content_area().pack_start(grid, True, True, 0)
    d.show_all()
    e_min.grab_focus()
    d.present()
    result = None
    while True:
        if d.run() != Gtk.ResponseType.OK:
            break
        try:
            mins = int(e_min.get_text().strip())
        except ValueError:
            mins = 0
        if mins <= 0:
            msg_info(t("msg.invalidMinutes"), t("msg.hint"))
            e_min.grab_focus()
            continue
        extras = {}
        clock = None
        if e_time is not None:
            clock = parse_clock(e_time.get_text())
            if not clock:
                msg_info(t("msg.invalidTime"), t("msg.hint"))
                e_time.grab_focus()
                continue
            extras["StartTime"] = clock
        for f, e in e_custom.items():
            extras[f] = e.get_text().strip()
        day = weeks[max(0, c_week.get_active())] + dt.timedelta(days=max(0, c_day.get_active()))
        hh, mm = map(int, (clock or now.strftime("%H:%M")).split(":"))
        result = {"minutes": mins, "date": dt.datetime.combine(day, dt.time(hh, mm)), "extras": extras}
        break
    d.destroy()
    return result


@guarded
def action_add_task():
    sel = select_task_triple()
    if not sel:
        return
    r = entry_dialog(sel["desc"])
    if r is None:
        return
    write_task_entry(r["date"], sel["category"], sel["subcategory"], sel["desc"], r["minutes"], r["extras"])


@guarded
def action_remove_task():
    """Gespeicherte Tasks (Katalog) löschen: Kategorie -> Unterkategorie -> Task. Gebuchte Einträge bleiben."""
    cats, _ = load_categories()
    if not cats:
        msg_info(t("msg.needCats"), t("msg.hint"))
        return
    cat = select_dialog(t("sel.category"), sorted(cats, key=sort_key))
    if not cat:
        return
    subs = cats.get(cat, [])
    if not subs:
        msg_info(t("msg.noSubs"), t("msg.hint"))
        return
    sub = select_dialog(t("sel.subcategory"), sorted(subs, key=sort_key))
    if not sub:
        return
    key = "%s::%s" % (cat, sub)
    while True:   # nach dem Löschen wieder die (verbleibenden) Tasks zeigen
        tasks = sorted(set(load_task_catalog().get(key, [])), key=sort_key)
        if not tasks:
            msg_info(t("task.none"), t("msg.hint"))
            return
        sel = select_dialog(t("task.remSelect"), tasks)
        if not sel:
            return
        if not ask_yes_no(t("task.remConfirm", sel, cat, sub), t("menu.remTask")):
            continue
        catalog = load_task_catalog()   # unmittelbar vor der Änderung frisch laden
        remaining = [x for x in catalog.get(key, []) if x != sel]
        if remaining:
            catalog[key] = remaining
        else:
            catalog.pop(key, None)
        save_task_catalog(catalog)


@guarded
def action_add_category():
    cats, _ = load_categories()
    new_cat = t("cat.new")
    sel = select_dialog(t("sel.category"), sorted(cats, key=sort_key) + [new_cat])
    if not sel:
        return
    if sel == new_cat:
        cat = input_dialog(t("cat.newTitle"), t("cat.newLabel"))
        if not cat or not cat.strip():
            return
        cat = cat.strip()
    else:
        cat = sel
    sub = input_dialog(t("cat.subTitle"), t("cat.subLabel", cat))
    if not sub or not sub.strip():
        return
    sub = sub.strip()
    cats, focus = load_categories()   # unmittelbar vor der Änderung frisch laden
    lst = cats.get(cat, [])
    if sub not in lst:
        lst.append(sub)
        cats[cat] = lst
        save_categories(cats, focus)


@guarded
def action_remove_category():
    cats, _ = load_categories()
    if not cats:
        return
    cat = select_dialog(t("cat.remSelect"), sorted(cats, key=sort_key))
    if not cat:
        return
    full = t("cat.remAll")
    sel = select_dialog(t("cat.remSub"), sorted(cats.get(cat, []), key=sort_key) + [full])
    if not sel:
        return
    cats, focus = load_categories()
    catalog = load_task_catalog()
    if sel == full:
        cats.pop(cat, None)
        for k in [k for k in catalog if k.startswith(cat + "::")]:
            catalog.pop(k, None)
    else:
        if cat in cats:
            cats[cat] = [s for s in cats[cat] if s != sel]
        catalog.pop("%s::%s" % (cat, sel), None)
    save_categories(cats, focus)
    save_task_catalog(catalog)


def select_week(title=None):
    weeks = list_weeks()
    if not weeks:
        return None
    cur = week_monday()
    pre = next((i for i, (m, _) in enumerate(weeks) if m == cur), len(weeks) - 1)
    sel = select_dialog(title or t("week.select"), [l for _, l in weeks], pre)
    for m, l in weeks:
        if l == sel:
            return m
    return None


@guarded
def action_report():
    mon = select_week()
    if mon is None:
        return
    state = {}

    def text():
        rep = week_report(mon)
        state["rep"] = rep
        lines = list(rep["lines"])
        if not rep["has_entries"]:
            lines.append(t("report.noEntries") if rep["file_exists"] else t("report.noData"))
        return "\n".join(lines)

    def title():
        return t("report.title", iso_week(mon), to_hhmm(state["rep"]["minutes"]), mon.strftime("%Y-%m-%d"),
                 (mon + dt.timedelta(days=6)).strftime("%Y-%m-%d"))

    text_window(title, text)


@guarded
def action_todo_report():
    def text():
        try:
            return "\n".join(todo_report_lines(load_todos()))
        except LoadError:
            return t("todoReport.loadError")
    text_window(lambda: t("todoReport.title"), text)


def select_scope(title):
    labels = [t("scope." + s) for s in SCOPES]
    sel = select_dialog(title, labels)
    return SCOPES[labels.index(sel)] if sel in labels else None


@guarded
def action_add_todo():
    scope = select_scope(t("todo.scopeTitle"))
    if not scope:
        return
    sel = select_task_triple()
    if not sel:
        return
    desc = textarea_dialog(t("todo.descTitle"), t("todo.descLabel"))
    if desc is None:
        return
    custom = ask_custom_values([c["Field"] for c in load_columns()["Todo"]])
    if custom is None:
        return
    todos = load_todos()   # frisch laden -> anhängen -> speichern
    todos.append({"Id": str(uuid.uuid4()), "Scope": scope, "Category": sel["category"],
                  "Subcategory": sel["subcategory"], "Task": sel["desc"], "Description": desc,
                  "Created": dt.datetime.now(), "Done": False, "DoneMinutes": None, "DoneDate": None,
                  "Extra": {custom_name(k): v for k, v in custom.items()}})
    save_todos(todos)
    msg_info(t("todo.saved"))


@guarded
def action_show_todos():
    scope = select_scope(t("todo.showScope"))
    if not scope:
        return
    d = Gtk.Dialog(title=t("todos.title", t("scope." + scope)))
    _prepare(d, 900, 520)
    store, tv, sw = _list_view(2)   # label, id
    d.get_content_area().pack_start(sw, True, True, 0)

    def refresh():
        store.clear()
        try:
            items = open_todos(load_todos(), scope)
        except LoadError:
            store.append([t("todos.loadError"), ""])
            return
        if not items:
            store.append([t("todos.none", t("scope." + scope)), ""])
        for x in items:
            first = (x["Description"].splitlines() or [""])[0]
            store.append(["%s -> %s | %s | %s (%s)" % (x["Category"], x["Subcategory"], x["Task"], first,
                                                       fmt_date(x["Created"])), x["Id"]])
        tv.set_cursor(Gtk.TreePath(0), None, False)

    def open_selected():
        model, it = tv.get_selection().get_selected()
        if it is not None and model[it][1]:
            todo_detail(model[it][1])
            refresh()

    def on_key(_w, ev):
        if _is_key(ev, "Return", "KP_Enter", "Right"):
            open_selected()
            return True
        if _is_key(ev, "F5"):
            refresh()
            return True
        if _is_key(ev, "Escape", "Left"):
            d.response(Gtk.ResponseType.CLOSE)
            return True
        return False

    tv.connect("key-press-event", on_key)
    tv.connect("row-activated", lambda *_: open_selected())
    refresh()
    d.show_all()
    tv.grab_focus()
    d.present()
    d.run()
    d.destroy()


RESP_MOVE, RESP_DONE, RESP_CLOSE = 1, 2, 3


@guarded
def todo_detail(todo_id):
    todo = next((x for x in load_todos() if x["Id"] == todo_id), None)
    if not todo:
        return
    orig = {"desc": todo["Description"]}
    d = Gtk.Dialog(title=t("detail.title", todo["Task"]))
    _prepare(d, 700, 560)
    box = d.get_content_area()
    box.set_spacing(8)
    box.set_border_width(12)
    info = Gtk.Label(xalign=0)
    box.pack_start(info, False, False, 0)

    def set_info():
        info.set_text(t("detail.info", t("scope." + todo["Scope"]) if todo["Scope"] in SCOPES else todo["Scope"],
                        todo["Category"], todo["Subcategory"], todo["Task"],
                        todo["Created"].strftime("%Y-%m-%d %H:%M") if todo["Created"] else ""))

    set_info()
    tv, sw = _text_view(True, text=todo["Description"])
    box.pack_start(sw, True, True, 0)
    combo = Gtk.ComboBoxText()
    for s in SCOPES:
        combo.append(s, t("scope." + s))
    if todo["Scope"] in SCOPES:
        combo.set_active_id(todo["Scope"])
    hb = Gtk.Box(spacing=8)
    hb.pack_start(combo, False, False, 0)
    for label, resp, end in ((t("detail.move"), RESP_MOVE, False), (t("detail.done"), RESP_DONE, True),
                             (t("detail.close"), RESP_CLOSE, True)):
        b = Gtk.Button(label=label)
        b.connect("clicked", lambda _b, r=resp: d.response(r))
        (hb.pack_end if end else hb.pack_start)(b, False, False, 0)
    box.pack_start(hb, False, False, 0)

    def on_key(_w, ev):
        if _is_key(ev, "Left") and not tv.has_focus() and not combo.has_focus():
            d.response(RESP_CLOSE)
            return True
        return False

    d.connect("key-press-event", on_key)
    d.show_all()
    tv.grab_focus()
    d.present()

    def save_desc_if_changed():
        new = _get_text(tv)
        if new != orig["desc"] and update_todo(todo_id, lambda x: x.update(Description=new)):
            orig["desc"] = new

    while True:
        r = d.run()
        if r == RESP_MOVE:
            new_scope = combo.get_active_id()
            if new_scope and new_scope != todo["Scope"]:
                new = _get_text(tv)
                if update_todo(todo_id, lambda x: x.update(Scope=new_scope, Description=new)):
                    todo["Scope"] = new_scope
                    orig["desc"] = new
                    set_info()
                    msg_info(t("detail.moved", t("scope." + new_scope)))
                else:
                    msg_info(t("detail.gone"), t("msg.hint"))
            continue
        if r == RESP_DONE:
            cur = next((x for x in load_todos() if x["Id"] == todo_id), None)
            if not cur:
                msg_info(t("detail.gone"), t("msg.hint"))
                continue
            if cur["Done"]:
                msg_info(t("detail.alreadyDone"))
                continue
            er = entry_dialog(todo["Task"])
            if er is None:
                continue
            mins = er["minutes"]
            write_task_entry(er["date"], todo["Category"], todo["Subcategory"], todo["Task"], mins, er["extras"])
            new = _get_text(tv)
            update_todo(todo_id, lambda x: x.update(Description=new, Done=True, DoneMinutes=mins,
                                                    DoneDate=dt.datetime.now()))
            msg_info(t("detail.booked"))
            break
        save_desc_if_changed()   # Schließen / Esc / Fenster zu
        break
    d.destroy()


# -----------------------------------------------------------------------------
# Spalten-Dialog Worklog (Checkliste)
# -----------------------------------------------------------------------------
@guarded
def worklog_columns_dialog():
    """Alle Worklog-Spalten als Liste mit Haken: an/abwählen, Reihenfolge, Überschrift, eigene Felder."""
    cols = [dict(c) for c in load_columns_all()["Worklog"]]
    d = Gtk.Dialog(title=t("columns.titleWorklog"))
    _prepare(d, 820, 480)
    d.add_button(t("btn.cancel"), Gtk.ResponseType.CANCEL)
    d.add_button(t("btn.save"), Gtk.ResponseType.OK)
    store = Gtk.ListStore(bool, str, str)
    tv = Gtk.TreeView(model=store)
    toggle = Gtk.CellRendererToggle()
    toggle.set_activatable(True)
    tv.append_column(Gtk.TreeViewColumn(t("columns.colActive"), toggle, active=0))
    tv.append_column(Gtk.TreeViewColumn(t("columns.colField"), Gtk.CellRendererText(), text=1))
    tv.append_column(Gtk.TreeViewColumn(t("columns.colHeader"), Gtk.CellRendererText(), text=2))
    sw = Gtk.ScrolledWindow()
    sw.set_hexpand(True)
    sw.set_vexpand(True)
    sw.add(tv)
    hb = Gtk.Box(spacing=8)
    hb.set_border_width(10)
    hb.pack_start(sw, True, True, 0)
    vb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    hb.pack_start(vb, False, False, 0)
    box = d.get_content_area()
    box.pack_start(hb, True, True, 0)
    note = Gtk.Label(label=t("columns.noteWorklog"), xalign=0)
    note.set_line_wrap(True)
    note.get_style_context().add_class("dim-label")
    note.set_margin_start(10)
    note.set_margin_end(10)
    box.pack_start(note, False, False, 6)

    def cur_index():
        _m, it = tv.get_selection().get_selected()
        return store.get_path(it).get_indices()[0] if it is not None else -1

    def refresh(sel=0):
        store.clear()
        for c in cols:
            store.append([c["Active"], field_display(c["Field"]), c["Header"]])
        if cols:
            tv.set_cursor(Gtk.TreePath(max(0, min(sel, len(cols) - 1))), None, False)

    def toggle_row(i):
        if 0 <= i < len(cols):
            cols[i]["Active"] = not cols[i]["Active"]
            store[i][0] = cols[i]["Active"]

    toggle.connect("toggled", lambda _r, path: toggle_row(int(path)))

    def on_key(_w, ev):
        if _is_key(ev, "space"):
            toggle_row(cur_index())
            return True
        return False

    tv.connect("key-press-event", on_key)

    def do_move(delta):
        i = cur_index()
        j = i + delta
        if i >= 0 and 0 <= j < len(cols):
            cols[i], cols[j] = cols[j], cols[i]
            refresh(j)

    def do_header(*_):
        i = cur_index()
        if i < 0:
            return
        v = input_dialog(field_display(cols[i]["Field"]), t("columns.headerLabel"), cols[i]["Header"])
        if v is not None and clean_field(v):
            cols[i]["Header"] = clean_field(v)
            refresh(i)

    def do_add_custom(*_):
        name = clean_field(input_dialog(t("columns.addCustom"), t("columns.customName")) or "").replace(":", "")
        if not name or any(c["Field"] == "Custom:" + name for c in cols):
            return
        i = cur_index()
        pos = i + 1 if i >= 0 else len(cols)
        cols.insert(pos, {"Field": "Custom:" + name, "Header": name, "Active": True})
        refresh(pos)

    def do_remove_custom(*_):
        i = cur_index()
        if i < 0:
            return
        if not is_custom(cols[i]["Field"]):
            msg_info(t("columns.onlyCustom"), t("msg.hint"))
            return
        cols.pop(i)
        refresh(i)

    def do_reset(*_):
        cols[:] = [dict(c) for c in default_columns()["Worklog"]]
        refresh()

    for label, cb in ((t("columns.up"), lambda *_: do_move(-1)), (t("columns.down"), lambda *_: do_move(1)),
                      (t("columns.header"), do_header), (t("columns.addCustom"), do_add_custom),
                      (t("columns.removeCustom"), do_remove_custom), (t("columns.reset"), do_reset)):
        b = Gtk.Button(label=label)
        b.connect("clicked", cb)
        vb.pack_start(b, False, False, 0)
    tv.connect("row-activated", lambda *_: do_header())
    refresh()
    d.show_all()
    tv.grab_focus()
    while True:
        if d.run() != Gtk.ResponseType.OK:
            break
        active = [c["Field"] for c in cols if c["Active"]]
        if "Date" not in active or not ("Minutes" in active or "Hours" in active):
            msg_info(t("columns.needWorklog"), t("msg.hint"))
            continue
        save_columns_part("Worklog", cols)
        break
    d.destroy()


# -----------------------------------------------------------------------------
# Spalten-Dialog (Todo-Report)
# -----------------------------------------------------------------------------
@guarded
def columns_dialog(kind):
    """kind = 'Worklog' (Header bearbeitbar) oder 'Todo' (Format bearbeitbar). Speichert bei OK."""
    cols = [dict(c) for c in load_columns()[kind]]
    prop = "Header" if kind == "Worklog" else "Format"
    d = Gtk.Dialog(title=t("columns.titleWorklog") if kind == "Worklog" else t("columns.titleTodo"))
    _prepare(d, 720, 420)
    d.add_button(t("btn.cancel"), Gtk.ResponseType.CANCEL)
    d.add_button(t("btn.save"), Gtk.ResponseType.OK)
    store, tv, sw = _list_view()
    hb = Gtk.Box(spacing=8)
    hb.set_border_width(10)
    hb.pack_start(sw, True, True, 0)
    vb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    hb.pack_start(vb, False, False, 0)
    box = d.get_content_area()
    box.pack_start(hb, True, True, 0)
    note = Gtk.Label(label=t("columns.noteWorklog") if kind == "Worklog" else t("columns.noteTodo"), xalign=0)
    note.set_line_wrap(True)
    note.get_style_context().add_class("dim-label")
    note.set_margin_start(10)
    note.set_margin_end(10)
    box.pack_start(note, False, False, 6)

    def cur_index():
        _m, it = tv.get_selection().get_selected()
        return store.get_path(it).get_indices()[0] if it is not None else -1

    def refresh(sel=0):
        store.clear()
        for c in cols:
            store.append(["%s   →   %s" % (field_display(c["Field"]), c[prop])])
        if cols:
            tv.set_cursor(Gtk.TreePath(max(0, min(sel, len(cols) - 1))), None, False)

    def default_prop(field):
        if kind == "Todo":
            return "{value}"
        return custom_name(field) if is_custom(field) else WL_HEADERS.get(LANG, WL_HEADERS["de"])[field]

    def do_add(*_):
        present = {c["Field"] for c in cols}
        avail = [f for f in (WL_FIELDS if kind == "Worklog" else TODO_FIELDS) if f not in present]
        labels = [field_display(f) for f in avail] + [t("columns.custom")]
        sel = select_dialog(t("columns.selectField"), labels)
        if not sel:
            return
        if sel == t("columns.custom"):
            name = input_dialog(t("columns.selectField"), t("columns.customName"))
            name = clean_field(name or "").replace(":", "")
            if not name or ("Custom:" + name) in present:
                return
            field = "Custom:" + name
        else:
            field = avail[labels.index(sel)]
        i = cur_index()
        pos = i + 1 if i >= 0 else len(cols)
        cols.insert(pos, {"Field": field, prop: default_prop(field)})
        refresh(pos)

    def do_remove(*_):
        i = cur_index()
        if i >= 0:
            cols.pop(i)
            refresh(i)

    def do_move(delta):
        i = cur_index()
        j = i + delta
        if i >= 0 and 0 <= j < len(cols):
            cols[i], cols[j] = cols[j], cols[i]
            refresh(j)

    def do_edit(*_):
        i = cur_index()
        if i < 0:
            return
        v = input_dialog(field_display(cols[i]["Field"]),
                         t("columns.headerLabel") if kind == "Worklog" else t("columns.formatLabel"), cols[i][prop])
        if v is not None and v.strip():
            cols[i][prop] = clean_field(v) if kind == "Worklog" else v.strip()
            refresh(i)

    def do_reset(*_):
        cols[:] = [dict(c) for c in default_columns()[kind]]
        refresh()

    for label, cb in ((t("columns.add"), do_add), (t("columns.remove"), do_remove),
                      (t("columns.up"), lambda *_: do_move(-1)), (t("columns.down"), lambda *_: do_move(1)),
                      (t("columns.header") if kind == "Worklog" else t("columns.format"), do_edit),
                      (t("columns.reset"), do_reset)):
        b = Gtk.Button(label=label)
        b.connect("clicked", cb)
        vb.pack_start(b, False, False, 0)
    tv.connect("row-activated", lambda *_: do_edit())
    refresh()
    d.show_all()
    tv.grab_focus()
    while True:
        r = d.run()
        if r != Gtk.ResponseType.OK:
            break
        fields = [c["Field"] for c in cols]
        if kind == "Worklog" and ("Date" not in fields or not ("Minutes" in fields or "Hours" in fields)):
            msg_info(t("columns.needWorklog"), t("msg.hint"))
            continue
        if not cols:
            msg_info(t("columns.needOne"), t("msg.hint"))
            continue
        save_columns_part(kind, cols)
        break
    d.destroy()


def settings_dialog():
    """Rückgabe: True wenn gespeichert."""
    global LANG
    s = load_settings()
    d = Gtk.Dialog(title=t("settings.title"))
    _prepare(d, 600, 220)
    d.add_button(t("btn.cancel"), Gtk.ResponseType.CANCEL)
    d.add_button(t("btn.save"), Gtk.ResponseType.OK)
    d.set_default_response(Gtk.ResponseType.OK)
    grid = Gtk.Grid(column_spacing=8, row_spacing=8)
    grid.set_border_width(12)
    grid.attach(Gtk.Label(label=t("settings.user"), xalign=0), 0, 0, 1, 1)
    e_name = Gtk.Entry(hexpand=True)
    e_name.set_text(s["UserName"])
    e_name.set_activates_default(True)
    grid.attach(e_name, 1, 0, 2, 1)
    grid.attach(Gtk.Label(label=t("settings.export"), xalign=0), 0, 1, 1, 1)
    e_path = Gtk.Entry(hexpand=True)
    e_path.set_text(s["ExportPath"])
    e_path.set_activates_default(True)
    grid.attach(e_path, 1, 1, 1, 1)
    btn = Gtk.Button(label=t("settings.browse"))

    def browse(*_):
        p = folder_dialog(t("settings.browseTitle"), e_path.get_text())
        if p:
            e_path.set_text(p)

    btn.connect("clicked", browse)
    grid.attach(btn, 2, 1, 1, 1)
    grid.attach(Gtk.Label(label=t("settings.language"), xalign=0), 0, 2, 1, 1)
    combo = Gtk.ComboBoxText()
    for code, name in LANGUAGES:
        combo.append(code, name)
    combo.set_active_id(s["Language"])
    grid.attach(combo, 1, 2, 1, 1)
    bcols = Gtk.Box(spacing=8)
    b1 = Gtk.Button(label=t("settings.columnsWorklog"))
    b1.connect("clicked", lambda *_: worklog_columns_dialog())
    b2 = Gtk.Button(label=t("settings.columnsTodo"))
    b2.connect("clicked", lambda *_: columns_dialog("Todo"))
    bcols.pack_start(b1, False, False, 0)
    bcols.pack_start(b2, False, False, 0)
    grid.attach(bcols, 1, 3, 2, 1)
    hint = Gtk.Label(label=t("settings.storedAt", SETTINGS_FILE), xalign=0)
    hint.get_style_context().add_class("dim-label")
    grid.attach(hint, 0, 4, 3, 1)
    d.get_content_area().pack_start(grid, True, True, 0)
    d.show_all()
    e_name.grab_focus()
    d.present()
    r = d.run()
    name, path = e_name.get_text().strip(), os.path.expanduser(e_path.get_text().strip())
    lang = combo.get_active_id() or "de"
    d.destroy()
    if r != Gtk.ResponseType.OK:
        return False
    if path and not os.path.isdir(path):
        if ask_yes_no(t("settings.createDir", path), t("settings.title")):
            try:
                os.makedirs(path, exist_ok=True)
            except OSError as e:
                msg_error(t("settings.createDirFailed", e))
                return False
    try:
        save_settings({"UserName": name, "ExportPath": path, "Language": lang})
    except SaveError as e:
        msg_error(t("msg.saveError", e.path))
        return False
    LANG = lang
    return True


def action_settings():
    settings_dialog()


def _settings_complete(s):
    return s["UserName"].strip() and s["ExportPath"].strip() and os.path.isdir(s["ExportPath"])


@guarded
def action_export():
    s = load_settings()
    if not _settings_complete(s):
        msg_info(t("export.needSettings"), t("export.title"))
        if not settings_dialog():
            return
        s = load_settings()
        if not _settings_complete(s):
            return
    mon = select_week(t("export.selectWeek"))
    if mon is None:
        if list_weeks():
            return
        mon = week_monday()   # noch gar keine Worklogs
    try:
        files = export_reports(mon, s["UserName"], s["ExportPath"])
    except OSError as e:
        msg_error(t("export.failed", e))
        return
    msg_info(t("export.done", s["ExportPath"], "\n".join(files)), t("export.title"))


# -----------------------------------------------------------------------------
# Menü (Tray und Tastatur-Dialog)
# -----------------------------------------------------------------------------
MENU = [
    ("menu.report", action_report),
    ("menu.addTask", action_add_task),
    ("menu.remTask", action_remove_task),
    ("menu.addCat", action_add_category),
    ("menu.remCat", action_remove_category),
    None,
    ("menu.addTodo", action_add_todo),
    ("menu.todos", action_show_todos),
    ("menu.todoReport", action_todo_report),
    None,
    ("menu.export", action_export),
    ("menu.settings", action_settings),
]


def menu_dialog_loop():
    """Menü als Liste (für Tastenkürzel / ohne Tray). Nach jeder Aktion wieder ins Menü, Esc = Ende."""
    entries = [m for m in MENU if m]
    last = 0
    while True:
        labels = [t(k) for k, _ in entries]   # nach Sprachwechsel neu
        mins = today_totals()
        sel = select_dialog("%s - %s" % (t("app.title"), t("tray.today", mins, to_hhmm(mins))), labels, last)
        if not sel:
            return
        last = labels.index(sel)
        entries[last][1]()


class TrayApp:
    def __init__(self):
        self.indicator = None
        self.status_icon = None
        self.items = []   # (MenuItem, key)
        self.menu = Gtk.Menu()
        self._build_menu()

    def _add(self, key, cb):
        it = Gtk.MenuItem(label=t(key))
        it.connect("activate", cb)
        self.items.append((it, key))
        self.menu.append(it)

    def _build_menu(self):
        self.mi_today = Gtk.MenuItem(label="-")
        self.mi_today.set_sensitive(False)
        self.menu.append(self.mi_today)
        self.menu.append(Gtk.SeparatorMenuItem())
        for m in MENU:
            if m is None:
                self.menu.append(Gtk.SeparatorMenuItem())
            else:
                self._add(m[0], lambda _i, fn=m[1]: self._run_action(fn))
        self.menu.append(Gtk.SeparatorMenuItem())
        self._add("menu.exit", lambda *_: Gtk.main_quit())   # nichts speichern: alles ist schon geschrieben
        self.menu.connect("show", lambda *_: self.update_text())   # Tagessumme beim Öffnen neu berechnen
        self.menu.show_all()

    def _run_action(self, fn):
        def go():
            apply_language()   # Sprache ggf. von --settings-Aufruf geändert
            fn()
            self.update_text()
            return False
        GLib.idle_add(go)

    def start(self):
        icon = "x-office-calendar"
        if INDICATOR_MOD is not None:
            ind = INDICATOR_MOD.Indicator.new("zeiterfassung", icon,
                                              INDICATOR_MOD.IndicatorCategory.APPLICATION_STATUS)
            ind.set_status(INDICATOR_MOD.IndicatorStatus.ACTIVE)
            ind.set_title(t("app.title"))
            ind.set_menu(self.menu)
            self.indicator = ind
        else:
            si = Gtk.StatusIcon.new_from_icon_name(icon)
            si.connect("activate", lambda *_: self.menu.popup(None, None, None, None, 0, Gtk.get_current_event_time()))
            si.connect("popup-menu", lambda _i, b, tm: self.menu.popup(None, None, None, None, b, tm))
            self.status_icon = si
        self.update_text()
        GLib.timeout_add_seconds(60, self._tick)   # auch Buchungen anderer Rechner/Aufrufe erfassen

    def _tick(self):
        apply_language()
        self.update_text()
        return True

    def update_text(self):
        for it, key in self.items:
            it.set_label(t(key))
        mins = today_totals()
        text = t("tray.today", mins, to_hhmm(mins))
        self.mi_today.set_label(text)
        if self.indicator is not None:
            self.indicator.set_label(to_hhmm(mins), "88:88")
        if self.status_icon is not None:
            self.status_icon.set_tooltip_text("%s: %s" % (t("app.title"), text))


def acquire_single_instance_lock():
    import fcntl
    rundir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    fh = open(os.path.join(rundir, "zeiterfassung-%d.lock" % os.getuid()), "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return None
    return fh


# -----------------------------------------------------------------------------
# Einstieg
# -----------------------------------------------------------------------------
def main(argv=None):
    p = argparse.ArgumentParser(description="timeTracker - Arbeitszeit- und Todo-Verwaltung / time and todo tracker")
    p.add_argument("--data-dir", default=os.environ.get("ZEITERFASSUNG_DIR") or DATA_DIR,
                   help="Datenordner / data folder (default: folder of this script)")
    g = p.add_mutually_exclusive_group()
    for opt in ("menu", "add-task", "report", "add-todo", "todos", "todo-report", "export", "settings", "no-tray"):
        g.add_argument("--" + opt, action="store_true")
    p.add_argument("--version", action="version", version=VERSION)
    a = p.parse_args(argv)
    set_data_dir(a.data_dir)
    apply_language()

    try:
        n = repair_all_worklogs()
        if n:
            log("%d Worklog-Datei(en) repariert" % n)
    except (LoadError, SaveError) as e:
        log("Reparatur fehlgeschlagen: %s" % e)

    import_gtk()
    single = {"add_task": action_add_task, "report": action_report, "add_todo": action_add_todo,
              "todos": action_show_todos, "todo_report": action_todo_report, "export": action_export,
              "settings": action_settings}
    for key, fn in single.items():
        if getattr(a, key):
            fn()
            return 0
    if a.menu or a.no_tray:
        menu_dialog_loop()
        return 0

    lock = acquire_single_instance_lock()
    if lock is None:
        menu_dialog_loop()   # Tray läuft schon -> Menü als Dialog
        return 0
    app = TrayApp()
    app.start()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
