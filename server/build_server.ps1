# Exporte le serveur dédié Linux de Cybervor vers server/game/build (utilisé par le Dockerfile).
# Usage : powershell -ExecutionPolicy Bypass -File server/build_server.ps1 [-Godot "C:\chemin\godot_console.exe"]
param([string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe")
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force "$root\server\game\build" | Out-Null
& $Godot --headless --path $root --export-release "Serveur Linux" "$root\server\game\build\cybervor_server.x86_64"
Write-Host "Serveur exporté dans server\game\build"
