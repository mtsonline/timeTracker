@echo off
rem timeTracker - startet zeiterfassung.ps1 ohne Konsolenfenster
rem Fuer den Autostart eine Verknuepfung auf diese Datei in "shell:startup" anlegen.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0zeiterfassung.ps1"
