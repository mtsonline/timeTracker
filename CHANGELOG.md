# Changelog

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
