# Changelog

## 2.5.2 – 2026-11-23
- Menu reordered like the todo group: Add task, Remove task, Task report (renamed from “Report”);
  groups separated by lines; “Add task” is preselected when the menu opens

## 2.5.1 – 2026-11-23
- Windows: today's total in the tray tooltip was not always refreshed. It is now also recalculated
  when the menu opens (shown as the first, greyed-out menu item) and when hovering over the icon;
  errors in event handlers are logged to `%APPDATA%\Zeiterfassung\zeiterfassung.log`
- Linux: today's total is recalculated when the menu opens

## 2.5.0 – 2026-11-23
- Duration dialog: focus on minutes; via Tab week, day, time (default: now) and custom fields –
  allows retroactive entries (up to 52 weeks back); also used when completing a todo
- Worklog columns as a checklist in the settings (check/uncheck, order, header, custom fields);
  unchecked columns and custom fields are remembered (`"Active": false` in `columns.json`)
- Column “Startzeit/Start time” is now “Uhrzeit/Time” (old headers are still recognised)
- Files are converted to the current column layout only when an entry is written to them
- New menu item “Remove task” (delete saved tasks from the catalogue)
- Categories, subcategories and tasks sorted alphabetically; “[Enter new task]”,
  “[Create new category]” and “[Remove entire category]” are always the last item
- “Recalculate today” removed (total is updated after every entry and every minute)

## 2.4.0 – 2026-11-03
- Language setting: German / English (UI, report headings, weekdays, export file names)
- Configurable columns for worklog CSV/report and todo report (`columns.json`, shared):
  reorder, remove, add – start time, end time, weekday, duration h:mm, user, custom fields
- Worklog files are parsed by their header line (old and new layouts remain readable)
- Linux variant (Python 3 + GTK 3, AppIndicator) with identical file formats
- Public repository, documentation, MIT license

## 2.3.0
- Settings (user name, export path; stored locally per computer)
- “Export reports”: `<Name>_KW<nn>_<Jahr>_Arbeitszeit.csv` and `…_Todos.md`
- Week selection shows the calendar week first, current week preselected

## 2.2.0
- Fix: new worklog entries were appended without a line break (CSV corrupted); damaged files are
  repaired automatically on start
- Fix: JSON files were overwritten with stale in-memory data when used on several synced computers
  (now read-modify-write on every change, nothing written on exit)
- Fix: read errors no longer lead to empty data being saved; per-entry robust todo loading
- Fix: ISO calendar week at year boundaries, backup rotation on retries, ← key in input dialogs
