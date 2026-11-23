# User guide

## Overview

timeTracker lives in the system tray. Clicking the icon or pressing **Ctrl+Alt+Z** opens the menu.
The icon shows the time logged today (Windows: tooltip, Linux: label next to the icon); it is
also shown as the first menu item and is updated after every entry, when the menu opens, when
hovering over the icon and every minute (including entries from other computers). On Windows,
errors are logged to `%APPDATA%\Zeiterfassung\zeiterfassung.log`.

| Menu item | Function |
|---|---|
| Add task | log work time |
| Remove task | delete saved tasks you no longer need |
| Task report | show the weekly report of a selected week |
| Add / remove category/subcategory | maintain the structure |
| Add todo / Show todos / Todo report | manage todos |
| Export reports | save weekly report and todo report as files |
| Settings | user name, export path, language, columns |
| Exit | close the program (all data is already saved) |

### Keyboard

In all lists: **↑/↓** select, **Enter** or **→** confirm, **Esc** or **←** back, typing letters
jumps to an entry. **F5** refreshes report windows. In input fields **←** only means “back” while
the field is empty.

## Concepts

- **Category** – e.g. a project or IT service (CSV column “Projekt oder IT-Service”)
- **Subcategory** – type of activity (CSV column “Tätigkeitskategorie”)
- **Task** – short description (CSV column “kurze Tätigkeitsbeschreibung”). Tasks are remembered
  per category/subcategory and offered again next time.

The default CSV headers follow the interface language (German: the original format shown in the
README; English: “Date;Project or IT service;Activity category;Short activity description;Effort / duration”).
You can rename them (see *Configuring columns*). If computers with different languages share one
data folder, save the column configuration once – it is then stored in `columns.json` and used by all.

## Getting started

1. Open **Settings** and enter your name, export path and language.
2. **Add category/subcategory** → *[Create new category]* → name → subcategory.
3. **Add task** (or **Ctrl+Alt+A**): category → subcategory → task (or *[Enter new task]* at the
   bottom) → duration dialog.

Categories, subcategories and tasks are always sorted alphabetically (case-insensitive, accented
letters with their base letter). Items such as *[Enter new task]* are always at the end.

## Entering the duration

![Duration dialog](../images/entry-dialog-linux.png)

The cursor is in **Duration (minutes)** – for a normal entry just type the minutes and press
**Enter**. Use **Tab** to reach:

| Field | Default | Use |
|---|---|---|
| Week | current week | ↑/↓ – up to 52 weeks back |
| Day | today | ↑/↓ – Monday to Sunday of the selected week |
| Time | now | only shown if the *Time* or *End time* column is active; format `HH:MM` |
| custom fields | empty | one per active custom field (e.g. “Ticket”) |

**Enter** saves, **Esc** cancels. The entry is written to the file of the selected week, so
forgotten times can be added later. The same dialog appears when a todo is marked as done.

Every entry is written immediately to `worklogs/<monday of the week>_worklog.csv`.

## Removing tasks

**Remove task** → category → subcategory → select task → confirm. The task disappears from the
selection list (`tasks.json`); entries already logged in the worklog stay unchanged. The list of
remaining tasks is shown again, **Esc** ends.

## Task report

**Task report** → select a week (the current week is preselected; shown as `CW 45 / 2026 (2026-11-02 .. 2026-11-08)`).
Entries with the same date, category, subcategory and description are summed up. The window
title shows the weekly total.

## Todos

- **Add todo:** scope (week, month, year, other) → category → subcategory → task → description
  (multi-line).
- **Show todos:** select a scope; Enter opens a todo. In the detail window you can edit the
  description, **move** the todo to another scope or mark it as **done**. When marking it done you
  are asked for the minutes and a worklog entry is created.
- **Todo report:** open todos of week, month and year as Markdown.

## Export reports

Exports the selected week into the export path:

- `<name>_CW<nn>_<year>_Worktime.csv` – the weekly report
- `<name>_CW<nn>_<year>_Todos.md` – the todo report (week, month and year only)

With the German interface the files are named `<Name>_KW<nn>_<Jahr>_Arbeitszeit.csv` and `…_Todos.md`.
Existing files of the same week are overwritten.

## Settings

| Setting | Meaning | Stored |
|---|---|---|
| User name | used in export file names and the “User” column | locally per computer |
| Export path | target folder for “Export reports” | locally per computer |
| Language | German or English (interface, report headings, weekdays) | locally per computer |
| Worklog / todo report columns | see below | `columns.json` in the data folder (shared) |

## Configuring columns

![Columns dialog](../images/columns-dialog-linux.png)

**Settings → Worklog columns…** shows all available columns as a checklist. Checked columns are
written to the worklog CSV, the report and the CSV export – in the order shown.

- **Space** or click on the checkbox: check/uncheck a column
- **Move up / Move down**: change the order
- **Header…** (or double-click): change the column header in the CSV
- **Custom field…**: add a new field (e.g. “Ticket”); it is asked for in the duration dialog
- **Delete field**: remove a custom field (standard columns can only be unchecked)
- **Default**: restore the original format

Unchecked columns keep their header, custom fields are kept and can be checked again later.

| Field | Content |
|---|---|
| Date | `yyyy-MM-dd` (required) |
| Weekday | e.g. “Tuesday” (in the selected language) |
| Time | `HH:MM` – in the duration dialog (default: now) |
| End time | `HH:MM` – time + duration |
| Category (project) | column “Projekt oder IT-Service” |
| Subcategory (activity category) | column “Tätigkeitskategorie” |
| Task (description) | column “kurze Tätigkeitsbeschreibung” |
| Duration in minutes | column “Aufwand bzw. Dauer” |
| Duration h:mm | e.g. `1:30` |
| User | user name from the settings |
| Custom field | any name, e.g. “Ticket”; the value is asked for in the duration dialog |

Date and one duration column (minutes or h:mm) are required. **Default** restores the original
format (with English interface: English headers).

Notes:

- Files are recognised by their header line when read, so older weeks remain readable even if
  the columns change later.
- Changing the columns does **not** modify any existing file. Only when an entry is written to a
  week file (also retroactively to an old week) is exactly that file converted to the current
  layout: missing columns are added (empty for older rows), unchecked ones removed. The previous
  version is kept in `worklogs/backups`. New week files are created in the current layout.
- The report shows every week in the current layout, even if its file still has the old one.
- If the time is a column, entries with different times are not merged in the report.

**Settings → Todo report columns…** defines each todo line: `* column1 | column2 | …`. Every column
has a **format** in which `{value}` stands for the value – e.g. `({value})` for the date in
brackets or `Prio: {value}` for a custom field. Available: Category->Subcategory, Category,
Subcategory, Task, Description (1st line), Scope, Created (date), Id and custom fields (asked for
when creating a todo). Default: `* Category->Subcategory | Task | (date)`.

## Several computers

- Data is read fresh from the files **before** every action and saved **immediately**. Nothing is
  written on exit.
- If a file cannot be read (e.g. while it is being synchronised) you get a message and **nothing**
  is saved – no data is lost.
- A backup is created before every write (`backups/<file>.0` … `.9`).
- If two computers change the same file within a few seconds before it was synchronised, the sync
  client may create a conflict copy (e.g. “… (conflicted copy) …”). Check for these occasionally.

## Restoring data

Exit the program, copy the desired backup from `backups/` (or `worklogs/backups/`), remove the
`.0`/`.1`/… suffix and replace the original file with it.
